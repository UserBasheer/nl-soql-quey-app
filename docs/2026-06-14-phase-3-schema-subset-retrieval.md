# Phase 3 — Schema-Subset Retrieval (Item 1)

**Date:** 2026-06-14
**Status:** Completed
**Branch:** feature/2026-06-14-schema-subset-retrieval

---

## Overview

**Original request:** Replace the hardcoded `objectScope` in the `soqlWhisperer` LWC (previously the fixed list `['Account', 'Contact', 'Case', 'Opportunity', 'Lead']`) with a dynamic, permission-scoped list of objects the running user can actually access, sourced from `SchemaService`. The user should be able to choose which object(s) ground the translation, rather than the app silently grounding on five hardcoded objects.

**Summary:** This phase consumes the already-existing `SoqlWhispererController.getObjects()` Apex method (which delegates to `SchemaService.listObjects()`) inside the `soqlWhisperer` LWC for the first time. `SchemaService.listObjects()` was refined to exclude noise objects (custom settings, deprecated/hidden objects, and `__Share`/`__History`/`__Feed`/`__ChangeEvent`/`__Tag`-suffixed system objects) and to return results sorted by label, while keeping the existing `isQueryable() && isAccessible()` permission gate under `with sharing` unchanged. The LWC now wires `getObjects` into a `lightning-dual-listbox` ("Objects to ground on") that the user controls directly, with a default preselection that preserves the prior five-object behavior when those objects are present. No DML, no `without sharing`, and no changes to `buildSchemaContext`'s data shape — the only path to the Claude translation provider remains object/field-name-and-type metadata.

---

## Components created

### Admin (declarative)

None. Per the design requirements, this is dev-only work — no new objects, fields, validation rules, permission sets, or layouts.

### Development (code)

| Type                     | Name                                             | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex class (modified)    | `SchemaService`                                  | `listObjects()` now additionally excludes `isCustomSetting()`, `isDeprecatedAndHidden()`, and objects whose API name ends in `__Share`, `__History`, `__Feed`, `__ChangeEvent`, or `__Tag` (case-insensitive). Results are sorted by label (case-insensitive, API-name tie-break) via a new private `ObjectInfoLabelComparator`. The existing `isQueryable() && isAccessible()` gate under `with sharing` is unchanged. `ObjectInfo`, `describeObject()`, and `buildSchemaContext()` are unchanged.                                         |
| Test class (modified)    | `SchemaServiceTest`                              | Added 3 new test methods (9 total, up from 6): `listObjectsResultIsSortedByLabelCaseInsensitiveWithApiNameTieBreak`, `listObjectsExcludesKnownSystemNoiseSuffixes`, `listObjectsExcludesCustomSettingsAndDeprecatedHiddenObjects`. The 6 pre-existing methods were retained (with descriptive assertion messages).                                                                                                                                                                                                                          |
| LWC (modified)           | `soqlWhisperer` (`.js` / `.html`)                | Replaced the hardcoded `objectScope` array with a `getObjects`-wired `lightning-dual-listbox` ("Objects to ground on"). New state: `objectOptions`, `objectScope`, `objectsReady`, `objectsError`. `computeDefaultSelection()` preselects `Account`/`Contact`/`Case`/`Opportunity`/`Lead` if present, otherwise the first 5 options by label. Generate/Refine are disabled when the scope is empty (`hasScope`/`actionsDisabled`). Empty-result and wire-error states are surfaced via the existing `showError`/validation-message styling. |
| Jest test (new)          | `soqlWhisperer.test.js`                          | First `__tests__` directory in the repo. 7 tests covering: options populated from `getObjects` wire data, default preselection (preferred objects present), fallback to first-5-alphabetical (no preferred objects present), empty-list warning state, wire-error state, and that the user-selected `objectScope` (not the full option set) is passed to `generateQuery`/`refineQuery`.                                                                                                                                                     |
| Design pattern doc (new) | `docs/design-patterns/SchemaService-patterns.md` | Documents the Repository/Selector pattern for `SchemaService`, the Phase 3 `listObjects()` scope refinement, alternatives considered, trade-offs, and Apex constraints (read-only, `with sharing`, data-egress shape).                                                                                                                                                                                                                                                                                                                      |

### Unchanged (verified, not modified)

| Type       | Name                                                           | Note                                                                                                                                                                               |
| ---------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex class | `SchemaService.describeObject()` / `buildSchemaContext()`      | Unchanged. `buildSchemaContext` still produces `apiName: field (TYPE), ...` blocks joined by newline — the only data shape that reaches the translation provider.                  |
| Apex class | `SoqlWhispererController`                                      | Unchanged. `getObjects()` already existed as `@AuraEnabled(cacheable=true)` and already delegated to `SchemaService.listObjects()`; this phase is the first time the LWC calls it. |
| LWC wiring | `generateQuery`/`refineQuery`/`validateQuery`/`runQuery` calls | Argument contract unchanged — `objectScope` is still passed as `List<String>` of API names, now sourced from the user's dual-listbox selection instead of a hardcoded array.       |

---

## Data flow

1. **Object list retrieval** — On component connect, `soqlWhisperer.js` issues a `@wire(getObjects)` call to `SoqlWhispererController.getObjects()`, which delegates to `SchemaService.listObjects()`.
2. **Permission + noise filtering (Apex)** — `listObjects()` iterates `Schema.getGlobalDescribe().values()`. For each `SObjectType`, it keeps the object only if:
   - `isQueryable() && isAccessible()` (existing permission gate — running user's effective object visibility under `with sharing`), **and**
   - it is not a custom setting (`isCustomSetting()`), not deprecated/hidden (`isDeprecatedAndHidden()`), and its API name does not end in `__Share`, `__History`, `__Feed`, `__ChangeEvent`, or `__Tag` (case-insensitive, via the new `isSystemObject()` helper).
     The surviving `ObjectInfo{apiName, label}` list is sorted by `ObjectInfoLabelComparator` (label, case-insensitive, then API name as tie-break) and returned.
3. **Picker population (LWC)** — `wiredObjects({ data, error })` maps the returned `ObjectInfo[]` to `{ label, value }` pairs for `objectOptions`, used by the `lightning-dual-listbox` in `soqlWhisperer.html`.
4. **Default selection** — `computeDefaultSelection(objectOptions)` checks for `Account`, `Contact`, `Case`, `Opportunity`, `Lead` (in that priority order) among the available options. If any are present, those become the initial `objectScope`. Otherwise, the first 5 options (already label-sorted from `SchemaService`) are preselected. This preserves the pre-Phase-3 default grounding behavior on first load when the prior hardcoded objects are accessible.
5. **User selection** — Changing the dual-listbox fires `handleObjectScopeChange`, which sets `objectScope` directly from `e.detail.value`. `hasScope` (non-empty `objectScope`) gates `actionsDisabled` — Generate and Refine are disabled until at least one object is selected.
6. **Translation request** — `handleGenerate`/`handleRefine` pass `objectScope` (the user-selected `List<String>` of API names) unchanged to `generateQuery`/`refineQuery`, exactly as before. `SoqlWhispererController` -> `SchemaService.buildSchemaContext(objectScope)` builds the metadata-only schema context (object + field API names + types) sent to the configured translation provider (per `feature/2026-06-13-claude-provider-toggle`, Claude by default via `TranslationProviderFactory`).
7. **Empty / error states** —
   - If `getObjects` returns an empty list, no dual-listbox is rendered and a warning box ("No queryable objects are accessible to you. Ask an admin for object access.") is shown via the existing `validationMessage`/`validationClass` styling.
   - If the wire errors, `objectOptions`/`objectScope` are cleared, no picker is rendered, and the error is surfaced via the existing `showError()` path (`.slds-theme_error`).

---

## File locations

| Component                         | Path                                                                       |
| --------------------------------- | -------------------------------------------------------------------------- |
| Apex class (modified)             | `force-app/main/default/classes/SchemaService.cls`                         |
| Apex class meta (apiVersion bump) | `force-app/main/default/classes/SchemaService.cls-meta.xml`                |
| Apex test class (modified)        | `force-app/main/default/classes/SchemaServiceTest.cls`                     |
| LWC JS (modified)                 | `force-app/main/default/lwc/soqlWhisperer/soqlWhisperer.js`                |
| LWC HTML (modified)               | `force-app/main/default/lwc/soqlWhisperer/soqlWhisperer.html`              |
| LWC meta (apiVersion bump)        | `force-app/main/default/lwc/soqlWhisperer/soqlWhisperer.js-meta.xml`       |
| Jest test (new)                   | `force-app/main/default/lwc/soqlWhisperer/__tests__/soqlWhisperer.test.js` |
| Design pattern doc (new)          | `docs/design-patterns/SchemaService-patterns.md`                           |

---

## Test coverage summary

### `SchemaServiceTest` (9 methods, 3 new)

| Method                                                               | New?     | Verifies                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `listObjectsReturnsAccessibleQueryableObjectsIncludingAccount`       | existing | `listObjects()` returns a non-empty list and includes `Account` (`apiName == 'Account'`, `label == 'Account'`).                                                                                                                                                                     |
| `listObjectsResultIsSortedByLabelCaseInsensitiveWithApiNameTieBreak` | **new**  | The returned `ObjectInfo[]` is sorted by `label` (case-insensitive ascending); entries with the same label are ordered by `apiName` ascending as a tie-break.                                                                                                                       |
| `listObjectsExcludesKnownSystemNoiseSuffixes`                        | **new**  | No returned `apiName` ends in `__share`, `__history`, `__feed`, `__changeevent`, or `__tag` (case-insensitive). Spot-checks that `Account` is retained while `AccountShare`/`AccountHistory`/`AccountFeed`/`AccountChangeEvent` (if present in `getGlobalDescribe()`) are excluded. |
| `listObjectsExcludesCustomSettingsAndDeprecatedHiddenObjects`        | **new**  | Every returned `ObjectInfo` corresponds to a real `getGlobalDescribe()` entry that is not a custom setting (`isCustomSetting() == false`), not deprecated/hidden (`isDeprecatedAndHidden() == false`), and still passes `isQueryable() && isAccessible()`.                          |
| `describeObjectReturnsAccessibleFieldsForAccount`                    | existing | `describeObject('Account')` returns a non-empty list including the `Id` field with `type == 'ID'`.                                                                                                                                                                                  |
| `describeObjectUnknownObjectThrowsSchemaException`                   | existing | `describeObject('NotARealObject__x')` throws `SchemaService.SchemaException` whose message contains the unrecognized API name.                                                                                                                                                      |
| `buildSchemaContextSingleObjectIncludesFieldNamesAndTypes`           | existing | `buildSchemaContext(['Account'])` starts with `'Account: '` and contains `'Id (ID)'`.                                                                                                                                                                                               |
| `buildSchemaContextMultipleObjectsJoinedByNewline`                   | existing | `buildSchemaContext(['Account', 'Contact'])` produces two newline-separated blocks starting with `'Account: '` and `'Contact: '`.                                                                                                                                                   |
| `buildSchemaContextEmptyListReturnsEmptyString`                      | existing | `buildSchemaContext([])` returns `''`.                                                                                                                                                                                                                                              |

All methods run against live org/scratch-org schema (no mocking required) and are wrapped in `Test.startTest()`/`Test.stopTest()` with descriptive assertion failure messages.

### `soqlWhisperer.test.js` (7 methods, new — first Jest `__tests__` dir in repo)

| Method                                                                                              | Verifies                                                                                                                                                           |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `populates the dual-listbox options from the getObjects wire data`                                  | `objectOptions` (and the rendered `lightning-dual-listbox.options`) match the `{ label, value }` mapping of the wired `ObjectInfo[]`.                              |
| `preselects the preferred default objects (Account, Contact, Case, Opportunity, Lead) when present` | When all five preferred objects are in the wired data, `objectScope` (dual-listbox `value`) equals exactly that list, in that order.                               |
| `falls back to the first five label-sorted objects when no preferred defaults are present`          | When none of the preferred objects are present, `objectScope` defaults to the first 5 options (already label-sorted from `SchemaService`).                         |
| `shows an empty-state warning and renders no picker when getObjects returns an empty list`          | An empty `getObjects` result renders no `lightning-dual-listbox` and shows a `.slds-theme_warning` box containing "No queryable objects are accessible to you".    |
| `handles a getObjects wire error by clearing options/scope and showing an error message`            | A wire error renders no picker and shows a `.slds-theme_error` box via `showError()`.                                                                              |
| `passes the user-selected objectScope (not the full option set) to generateQuery`                   | Narrowing the dual-listbox selection to `['Contact']` and clicking "Generate SOQL" calls `generateQuery` with `objectScope: ['Contact']`, not the full option set. |
| `passes the user-selected objectScope to refineQuery when refining an existing query`               | Selecting `['Account', 'Opportunity']` and clicking "Refine" calls `refineQuery` with `objectScope: ['Account', 'Opportunity']`.                                   |

Jest mocks use `createApexTestWireAdapter` (from `@salesforce/wire-service-jest-util`) for the cacheable `getObjects` wire, and plain `jest.fn()`s for the imperative `generateQuery`/`refineQuery`/`validateQuery`/`runQuery` calls.

### Code review result

APPROVED WITH WARNINGS on first pass; warnings were fixed before this commit (apiVersion bumped to `66.0` on `SchemaService.cls-meta.xml` and `soqlWhisperer.js-meta.xml`, matching the project convention). All hard constraints (read-only / no DML, permission-aware / `with sharing` + `isAccessible`/FLS narrowed only, PHI/data-egress shape unchanged) were verified intact.

---

## Security

- `SchemaService` remains `with sharing`. `listObjects()`'s permission gate (`isQueryable() && isAccessible()`) is unchanged — the Phase 3 changes only **narrow** the result (exclude custom settings, deprecated/hidden objects, and system-suffix objects), never widen access.
- Field-level security in `describeObject()` (`fd.isAccessible()`) and the data shape returned by `buildSchemaContext()` are unchanged.
- No DML anywhere in this diff — `SchemaService` and the LWC changes are describe-reads and UI state only. `QueryService.validate()`/`runQuery()` (USER_MODE enforcement) are untouched.
- **Data egress / PHI:** the only path to the translation provider (Claude, per the Phase 2 provider toggle) is `buildSchemaContext(objectScope)`, whose shape (`apiName: field (TYPE), ...` per object, newline-joined) is unchanged. Letting the user select more objects can increase the _size_ of this metadata-only context (a prompt-budget consideration), but never changes the _kind_ of data sent — no record data, no PHI, ever leaves the org via this path.
- The empty-accessible-objects case (`objectOptions.length === 0`) is handled explicitly with a warning message rather than silently grounding on nothing or erroring.

---

## Notes

- **Limitations:**
  - The system-suffix exclusion (`__Share`, `__History`, `__Feed`, `__ChangeEvent`, `__Tag`) is a fixed heuristic. A (rare) legitimately named custom object ending in one of these suffixes — e.g. a custom `__Tag` business object — would be hidden from the picker even if accessible. This is an accepted trade-off per the design pattern doc, since these suffixes are reserved system patterns in practice.
  - No hard cap is applied to the number of objects returned by `listObjects()` or selectable in the picker, per the design requirement to never silently truncate entitled objects. In orgs with very large numbers of accessible custom objects, the dual-listbox "Available objects" side could become long; `lightning-dual-listbox` does not provide built-in search/filter, so this is a candidate for a future UX enhancement (see below) rather than a current defect.
  - Selecting many objects increases the size of the schema context sent to the translation provider (prompt-budget concern, flagged during design — not a PHI/egress concern). No per-request object-count limit or warning was added in this phase; the field-level help text on the dual-listbox ("fewer is faster and cheaper") is the only current mitigation.

- **Future enhancement suggestions:**
  - Add client-side search/filter to the object picker if the "Available objects" list becomes unwieldy in large orgs (preferred over any server-side truncation, per the design constraints).
  - Consider surfacing an explicit warning or soft limit in the UI if the user selects a very large number of objects, to manage the schema-context size sent to the translation provider.
  - If a future iteration needs an admin-configurable allow/deny list of objects (beyond the fixed exclusion heuristic), that would be new Custom Metadata-backed admin work — explicitly out of scope for this phase.

- **Dependencies:**
  - The LWC's object picker depends on `SoqlWhispererController.getObjects()` and `SchemaService.listObjects()` being deployed (both existed prior to this phase; only `listObjects()`'s filtering/sorting changed).
  - `computeDefaultSelection()`'s preferred-defaults list (`Account`, `Contact`, `Case`, `Opportunity`, `Lead`) assumes those standard objects are queryable/accessible in the target org for the pre-Phase-3 default behavior to be preserved exactly; if none are accessible, the fallback (first 5 by label) applies.

---

## Change history

| Date       | Change                                                                                                                                                                                                                                                                                                                                                              |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-06-14 | Initial creation — Phase 3, Item 1 (schema-subset retrieval). `SchemaService.listObjects()` scope refinement (noise exclusion + label sort), `soqlWhisperer` LWC object picker wired to `getObjects`, new Jest test suite, new `SchemaService` design pattern doc, apiVersion bumped to 66.0. Code review APPROVED WITH WARNINGS, warnings fixed prior to this doc. |
