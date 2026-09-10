# Fix — SchemaService noise-filter missed standard-object system siblings

**Date:** 2026-09-10
**Status:** Completed
**Branch:** feature/2026-09-10-fix-system-object-filter (off `main`, includes the already-merged Phase 3 schema-subset retrieval work)

---

## Overview

**Trigger:** Not a new user-facing request. A scratch-org validation run of the Phase 3
schema-subset retrieval work (`docs/2026-06-14-phase-3-schema-subset-retrieval.md`) failed
the test `SchemaServiceTest.listObjectsExcludesKnownSystemNoiseSuffixes` before that work
could be deployed, surfacing a real defect in `SchemaService.listObjects()`'s noise-object
filter.

**The bug:** `SchemaService`'s noise-suffix filter (`isSystemObject()`) stored its exclusion
list only in double-underscore form — `__Share`, `__History`, `__Feed`, `__ChangeEvent`,
`__Tag` — and matched with a plain `endsWith`. That form only ever occurs for siblings of
**custom** parent objects (`MyObject__c` → `MyObject__Share`). Standard parent objects
produce siblings **without** an underscore — `AccountShare`, `CaseHistory`,
`OpportunityFeed`, `AccountChangeEvent`, etc. Because none of those bare-suffix names ever
matched a `__`-prefixed pattern, the entire standard-object half of the noise set —
in practice the majority of real-org noise objects — passed straight through the filter and
would have reached the object picker in the `soqlWhisperer` LWC.

**Summary:** `isSystemObject()`'s signature was changed from a single `String apiName`
parameter to `isSystemObject(String apiName, Boolean isCustomObject)`, called from
`listObjects()` as `isSystemObject(d.getName(), d.isCustom())`. The predicate is now
describe-informed: the `'__'+suffix` form is matched unconditionally (a reserved
double-underscore platform pattern), while the bare-suffix form is matched only when
`isCustomObject != true` (i.e. for standard objects). This closes the standard-object gap
without introducing over-matching against legitimately named custom objects. No permission
logic changed — this is a narrowing-only fix, consistent with the constraints in the
original Phase 3 design.

---

## Components changed

### Development (code)

| Type                         | Name                                             | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ---------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex class (modified)        | `SchemaService`                                  | `isSystemObject()` signature changed to `isSystemObject(String apiName, Boolean isCustomObject)`, marked `@TestVisible`. `SYSTEM_SUFFIXES` now stores bare suffix words (`Share`, `History`, `Feed`, `ChangeEvent`, `Tag`); the `'__'+suffix` form is derived and checked unconditionally, the bare form is checked only when `isCustomObject != true`. Both forms require the API name to be strictly longer than the matched suffix. `listObjects()` now calls `isSystemObject(d.getName(), d.isCustom())`. No other method changed.                                                                                                                                                                                                                                                                                                                   |
| Test class (modified)        | `SchemaServiceTest`                              | Added 3 test methods (12 total, up from 9): a synthetic-input regression guard for the `'__'+suffix` custom-sibling branch (via direct `@TestVisible` calls to `isSystemObject`, since this org's schema has no fixture custom object that produces a real `__Share`/`__History`/`__Feed`/`__ChangeEvent`/`__Tag` sibling), a false-positive guard confirming objects that _contain but do not end with_ a noise word (`FeedItem`, `FeedComment`, `FieldHistoryArchive`, `TagDefinition`) are kept, and a boundary guard confirming an object named exactly equal to a bare suffix (e.g. hypothetical `Tag`) is not excluded while one character longer is. Class-level doc comment and assertion messages were revised across two follow-up commits to precisely state what each assertion does and does not isolate (see Test coverage summary below). |
| Design pattern doc (updated) | `docs/design-patterns/SchemaService-patterns.md` | New "Fix — noise matching must be describe-informed, not string-only" section explaining the bug, why a blanket bare `endsWith` was rejected (over-matching would hide legitimate business objects), and the updated trade-offs table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |

### Unchanged (verified, not modified)

| Type            | Name                                                                   | Note                                                                                                                                                                           |
| --------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Apex class      | `SchemaService.listObjects()` permission gate                          | `isQueryable() && isAccessible()` gate and `with sharing` context are untouched — this fix only narrows the noise exclusion, it never widens or changes object/FLS visibility. |
| Apex class      | `describeObject()` / `buildSchemaContext()`                            | Byte-identical to the pre-fix version. Data-egress shape to the translation provider is unaffected.                                                                            |
| LWC             | `soqlWhisperer` (`.js` / `.html`)                                      | Not touched by this fix. The picker already consumed `getObjects()`; this fix only changes which objects that call returns.                                                    |
| Apex class meta | Both `SchemaService.cls-meta.xml` and `SchemaServiceTest.cls-meta.xml` | Already `apiVersion 66.0` from Phase 3; no drift introduced.                                                                                                                   |

---

## Data flow

The fix changes one internal predicate; the surrounding flow described in
`docs/2026-06-14-phase-3-schema-subset-retrieval.md` is otherwise unchanged. The corrected
step is:

1. `listObjects()` iterates `Schema.getGlobalDescribe().values()` and, for each object
   passing `isQueryable() && isAccessible()` and not a custom setting or
   deprecated/hidden, calls `isSystemObject(d.getName(), d.isCustom())`.
2. `isSystemObject()` checks, per suffix in `SYSTEM_SUFFIXES` (`Share`, `History`, `Feed`,
   `ChangeEvent`, `Tag`):
   - `'__' + suffix` — matched **unconditionally**, regardless of `isCustomObject` (covers
     custom-parent siblings such as `MyObject__Share`, and is checked for every object
     since the double-underscore form is a reserved pattern that never occurs for
     legitimate standard-object names).
   - bare `suffix` — matched **only when `isCustomObject != true`** (covers standard-parent
     siblings such as `AccountShare`, `CaseHistory`, `OpportunityFeed`,
     `AccountChangeEvent`).
   - Both checks require `apiName.length() > suffix.length()`, so an object literally named
     `Tag` or `Feed` is never excluded by a sibling rule that does not apply to it.
3. Objects that match either form are excluded from the `ObjectInfo` list before sorting
   and returning — same as before, just with the standard-object gap closed.

---

## File locations

| Component                                   | Path                                                   |
| ------------------------------------------- | ------------------------------------------------------ |
| Apex class (modified)                       | `force-app/main/default/classes/SchemaService.cls`     |
| Apex test class (modified)                  | `force-app/main/default/classes/SchemaServiceTest.cls` |
| Design pattern doc (updated)                | `docs/design-patterns/SchemaService-patterns.md`       |
| Prior phase doc (annotated, not superseded) | `docs/2026-06-14-phase-3-schema-subset-retrieval.md`   |

---

## Test coverage summary

`SchemaServiceTest` — 12 methods total (3 new for this fix):

| Method                                                                 | New?                          | Verifies                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `listObjectsExcludesKnownSystemNoiseSuffixes`                          | existing (previously failing) | No returned `apiName` ends in a `'__'+suffix` form; spot-checks that `Account` is kept while its bare-form siblings (`AccountShare`, `AccountHistory`, `AccountFeed`, `AccountChangeEvent`), if present in org schema, are excluded. This is the assertion the scratch-org validation run caught failing pre-fix, and it now passes unconditionally against live org schema.                                                                                                                                                                                                                                         |
| `listObjectsExcludesCustomObjectNoiseSuffixesWhenPresentInOrg`         | **new**                       | Direct `@TestVisible` calls to `isSystemObject()` with synthetic inputs, since this org has no fixture custom object producing a real `__`-suffixed sibling. Only the `isSystemObject('Foo__Share', true)` assertion isolates the `'__'+suffix` branch (the bare-suffix branch cannot fire when `isCustomObject == true`); the `isCustomObject = false` assertions on the same inputs are documented as non-isolating (they also match the bare-suffix branch) and are kept as an OR'd non-regression guard only — see the method's doc comment and inline comments for the exact guarantee each assertion provides. |
| `listObjectsKeepsStandardObjectsThatContainButDoNotEndWithNoiseSuffix` | **new**                       | False-positive guard: `FeedItem`, `FeedComment`, `FieldHistoryArchive`, `TagDefinition` (contain but do not _end with_ a noise word) are not excluded, when present and otherwise eligible in org schema.                                                                                                                                                                                                                                                                                                                                                                                                            |
| `listObjectsDoesNotExcludeObjectNamedExactlyEqualToBareSuffix`         | **new**                       | Boundary guard via synthetic `isSystemObject()` calls: a name exactly equal to a bare suffix (e.g. `"Tag"`) is not excluded; one character longer (e.g. `"ATag"`) is.                                                                                                                                                                                                                                                                                                                                                                                                                                                |

All other existing `SchemaServiceTest` methods (Account inclusion, label sort,
custom-setting/deprecated-hidden exclusion, `describeObject`, `buildSchemaContext`) are
unchanged and unaffected by this fix.

### Code review result

Three review passes on this branch, all **APPROVED WITH WARNINGS**, no critical issues at
any point:

- **Round 1** (`dab59f6` / `329edd4`) — fix and initial test coverage approved.
- **Round 2** (`ebf3065`) — closed a coverage gap (the two new edge-case tests were
  originally schema-dependent and gave zero live protection in an org lacking the right
  fixture objects); rewritten to call `isSystemObject()` directly via `@TestVisible` with
  synthetic inputs. One warning raised: a doc comment overclaimed that the
  `isCustomObject = false` assertions on `'__'+suffix` inputs isolated that branch, which
  isn't provable (those inputs also match the independent bare-suffix branch).
- **Round 3 / final** (`11c15e6`) — resolved Round 2's warning by rewording the doc comment
  and `Assert` messages to state precisely what each assertion does and does not prove, with
  no logic or assertion-input changes. Final verdict: **APPROVED WITH WARNINGS**, the one
  remaining (non-blocking) warning being the stale Phase 3 doc addressed by this
  documentation pass — see `agent-output/review-verdict.md` for the full three-round history.

---

## Security

- `SchemaService` remains `public with sharing`; the `isQueryable() && isAccessible()`
  permission gate in `listObjects()` is byte-for-byte unchanged by this fix.
- This is a **narrowing-only** fix: it excludes more noise objects than before (closing the
  standard-object gap); it never widens object or field-level access.
- No DML anywhere in this diff. `QueryService.validate()`/`runQuery()` (`USER_MODE`
  enforcement) are untouched and were re-verified as part of code review.
- **Data egress / PHI:** `buildSchemaContext()`/`describeObject()` are byte-identical to the
  pre-fix version — no new data reaches the translation provider, and the fix has no effect
  on data-egress shape.

---

## Notes

- **Limitations (carried over from Phase 3, still accepted):** the noise-suffix exclusion
  remains a fixed heuristic. A legitimately named standard object ending in `Share`,
  `History`, `Feed`, `ChangeEvent`, or `Tag` would still be hidden from the picker — this
  fix does not change that trade-off, it only makes the _intended_ heuristic (standard-object
  siblings excluded via bare suffix, custom-object siblings excluded via `'__'+suffix`)
  actually work as designed.
- **Testing limitation:** the `'__'+suffix` custom-sibling branch and the exact-suffix
  boundary case cannot be exercised against `listObjects()` end-to-end in this org, because
  its schema has no fixture custom object producing those sibling names. Coverage for those
  branches instead calls the `@TestVisible` `isSystemObject()` helper directly with
  synthetic inputs — a deliberate, documented trade-off, not a gap.
- **Dependencies:** none beyond `SchemaService.cls` itself; no other class, LWC, or metadata
  needed to change for this fix.
- **Related doc:** `docs/2026-06-14-phase-3-schema-subset-retrieval.md` describes the
  original Phase 3 feature that this fix corrects. That doc has been annotated in place
  (not rewritten) to flag the sections that described the pre-fix, `'__'-form-only`
  exclusion behavior — see its "Note" callouts pointing back to this doc.

---

## Change history

| Date       | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-09-10 | Initial creation. Fixes `SchemaService.isSystemObject()` to correctly exclude standard-object noise siblings (`AccountShare`, `CaseHistory`, etc.), not just custom-object `'__'+suffix` siblings. Three commits: `dab59f6` (fix + design pattern doc), `329edd4`/`ebf3065`/`11c15e6` (test coverage and two rounds of test-comment precision fixes). Code review APPROVED WITH WARNINGS across three rounds; final warning (this doc) resolved here. |
