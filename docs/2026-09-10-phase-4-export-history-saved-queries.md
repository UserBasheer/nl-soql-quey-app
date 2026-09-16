# Phase 4 — Result Export, Query History, Saved Queries

**Date:** 2026-09-10 (metadata corrected 2026-09-11, see "Post-merge metadata corrections" below;
test suite corrected 2026-09-11, see "Post-merge test corrections" below)
**Status:** Completed (code review APPROVED, no warnings) — awaiting PR merge + devops deploy
**Branch:** feature/2026-09-10-export-history-saved-queries (off `main` @ 53b997a, PR #4 merged)

---

## Overview

**Original request:** The three "Phase 3 polish" backlog items tracked in `PHASE2.md`:

1. **Result export** — export the current query results.
2. **Query history** — a record of queries the user has run.
3. **Saved queries** — named queries the user can store and reload.

`EinsteinTranslationProvider` was explicitly out of scope for this phase (still deferred, see
Phase 5 backlog below).

**Summary:** This phase adds the first DML this project has ever written. Two new,
tool-owned custom objects (`SOQL_Query_History__c`, `SOQL_Saved_Query__c`) store query text
and run metadata — never result rows — behind two new `with sharing` service classes
(`QueryHistoryService`, `SavedQueryService`), both using `AccessLevel.USER_MODE` exclusively.
`QueryService.cls`, the SOQL executor, remains **100% DML-free** and unmodified apart from
removing a stray `@AuraEnabled` annotation that would otherwise have let a component call it
directly and bypass history logging. `SoqlWhispererController.runQuery` now logs every run
(success or failure) after `QueryService` executes it, then returns/rethrows exactly as
before. The `soqlWhisperer` LWC gained a client-side CSV export button (gated on a new
`Export_Query_Results` custom permission), a saved-query toolbar, and a lazy-loaded query
history accordion. No new Apex query, callout, or persisted copy of result data was
introduced anywhere in this phase.

---

## Components created

### Admin (declarative)

| Type              | API name                                          | Description                                                                                                                                                                                                                                                                                                                        |
| ----------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom object     | `SOQL_Query_History__c`                           | System-logged record of every query run (success or failure). OWD Private (internal and external). Name = Auto Number `QH-{00000000}`. Reports/Activities/History tracking/Search all disabled.                                                                                                                                    |
| Custom field      | `SOQL_Query_History__c.SOQL__c`                   | Long Text Area (5000), **not** platform-required — the SOQL that was run. See "Post-merge metadata corrections" below: the platform rejects `required=true` on a LongTextArea field, so this field can hold `null` on the error-logging path; there is no supported path that inserts a blank/non-error history row.               |
| Custom field      | `SOQL_Query_History__c.Natural_Language__c`       | Long Text Area (1000) — the originating prompt; null for a directly-typed/edited SOQL run.                                                                                                                                                                                                                                         |
| Custom field      | `SOQL_Query_History__c.Object_Scope__c`           | Long Text Area (1000) — comma-separated API names of the objects the run was grounded on.                                                                                                                                                                                                                                          |
| Custom field      | `SOQL_Query_History__c.Row_Count__c`              | Number(9,0) — rows returned; `0` on error.                                                                                                                                                                                                                                                                                         |
| Custom field      | `SOQL_Query_History__c.Status__c`                 | Restricted picklist, values exactly `Success` / `Error`.                                                                                                                                                                                                                                                                           |
| Custom field      | `SOQL_Query_History__c.Error_Message__c`          | Text(255) — exception message only, truncated. Never contains result data.                                                                                                                                                                                                                                                         |
| Custom object     | `SOQL_Saved_Query__c`                             | User-named, permanent saved query. OWD Private (internal and external). Name = Text, label "Saved Query Name", required, **not** unique (uniqueness is org-wide; per-user dedupe happens in Apex).                                                                                                                                 |
| Custom field      | `SOQL_Saved_Query__c.SOQL__c`                     | Long Text Area (5000), **not** platform-required (the platform rejects `required=true` on a LongTextArea field — see "Post-merge metadata corrections" below); a blank/null value can never reach this field through the supported path because `SavedQueryService.saveQuery` throws before any DML if the SOQL argument is blank. |
| Custom field      | `SOQL_Saved_Query__c.Natural_Language__c`         | Long Text Area (1000) — originating prompt, restored on load.                                                                                                                                                                                                                                                                      |
| Custom field      | `SOQL_Saved_Query__c.Object_Scope__c`             | Long Text Area (1000) — comma-separated object API names, restored on load so a subsequent Refine is grounded the same way.                                                                                                                                                                                                        |
| Page layout       | `SOQL_Query_History__c-SOQL Query History Layout` | All fields, no tabs — records are surfaced only through the LWC.                                                                                                                                                                                                                                                                   |
| Page layout       | `SOQL_Saved_Query__c-SOQL Saved Query Layout`     | All fields, no tabs.                                                                                                                                                                                                                                                                                                               |
| Custom permission | `Export_Query_Results`                            | Gates the "Export CSV" button in the LWC.                                                                                                                                                                                                                                                                                          |
| Permission set    | `SOQL_Whisperer_User`                             | Required post-deploy assignment — see "Deployment / setup" below.                                                                                                                                                                                                                                                                  |

### Development (code)

| Type                            | Name                                                                                           | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex class (new)                | `QueryHistoryService` (`with sharing`)                                                         | Owns all persistence for `SOQL_Query_History__c`. `logRun(...)` — inserts one row, **never throws** (wrapped in try/catch, swallowed); defensively truncates every text value to its field length first. `getRecent(Integer limitSize)` — clamps to `[1, 200]`, default 25 when null, `ORDER BY CreatedDate DESC, Name DESC`. `clearMine()` — deletes the running user's own rows (`WHERE OwnerId = :UserInfo.getUserId()`, the one deliberate exception to "no manual owner filters"), `LIMIT 10000`, returns the count deleted.                                                                                                                                                                                                                                                                                           |
| Apex class (new)                | `SavedQueryService` (`with sharing`)                                                           | Owns all persistence for `SOQL_Saved_Query__c`. `saveQuery(name, soql, nl, scope)` — throws `AuraHandledException` on blank name/SOQL; overwrite semantics matched on `Name` + `OwnerId = UserInfo.getUserId()` (insert if no match, update if one does). `listMine()` — `ORDER BY Name ASC LIMIT 200`, no manual owner filter (sharing model does the work). `deleteSavedQuery(Id)` — user-mode `SELECT ... WHERE Id = :recordId` first; another user's id simply returns no rows, so delete is unreachable across users without any hand-rolled check.                                                                                                                                                                                                                                                                    |
| Apex class (modified)           | `SoqlWhispererController`                                                                      | `runQuery` signature changed from `runQuery(String soql)` to `runQuery(String soql, String naturalLanguage, List<String> objectScope)` (Apex has no `@AuraEnabled` overloads). Calls `QueryService.runQuery(soql)`; on success logs `('Success', rows.size(), null)` and returns; on exception logs `('Error', 0, e.getMessage())` then rethrows unchanged so the LWC's error handling is unaffected. Logging is wrapped in a second try/catch (`logSafely`) as defense-in-depth on top of `logRun`'s own never-throw contract. New thin `@AuraEnabled` passthroughs with no business logic: `getHistory(Integer limitSize)`, `clearHistory()`, `saveQuery(...)`, `getSavedQueries()`, `deleteSavedQuery(Id)`. `getHistory`/`getSavedQueries` are deliberately **not** `cacheable=true` since both change within a session. |
| Apex class (modified, one-line) | `QueryService`                                                                                 | The only change: the stray `@AuraEnabled` was removed from `runQuery(String soql)`. `QueryService` is otherwise byte-identical — still zero DML, still `validate()` + `Database.queryWithBinds(..., AccessLevel.USER_MODE)`. Removing the annotation closes a pre-existing gap where an LWC could call the executor directly and bypass history logging entirely; `SoqlWhispererController.runQuery` is now the only LWC-reachable execution path.                                                                                                                                                                                                                                                                                                                                                                          |
| Test class (new)                | `QueryHistoryServiceTest`                                                                      | 22 test methods (see Test coverage summary).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Test class (new)                | `SavedQueryServiceTest`                                                                        | 17 test methods (see Test coverage summary).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Test class (extended)           | `SoqlWhispererControllerTest`                                                                  | Extended with history-logging assertions on both the success and failure paths of `runQuery` (18 methods total in the file after this phase).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| LWC module (new)                | `csvUtils.js` (in `soqlWhisperer` bundle)                                                      | Pure, DOM-free, exported helper functions: `toCsvCell`, `buildCsv`, `buildCsvFileName`, `toCsvDataUri`, plus the exported `CSV_BOM` constant. See "CSV export mechanics" below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| LWC (modified)                  | `soqlWhisperer` (`.js` / `.html`)                                                              | New "Export CSV" button (gated on `hasResults && hasExportPermission`); new toolbar (`lightning-combobox` of saved queries + Save current / Delete, with an inline `lightning-input` name field for save instead of a modal); new `lightning-accordion` "Query history" section (datatable of recent runs with a "Load into editor" row action, Refresh / Show more / Clear my history with confirm). History loads lazily — `getHistory` is not called until the accordion section is first expanded; saved queries load on `connectedCallback` since that combobox is visible immediately.                                                                                                                                                                                                                                |
| Jest test (new)                 | `csvUtils.test.js`                                                                             | 24 tests, 100% coverage of `csvUtils.js` — RFC 4180 escaping, null handling, formula-injection prefixing, BOM, header-row correctness.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Jest test (extended)            | `soqlWhisperer.test.js`                                                                        | Extended with saved-query selection (repopulates `soql`/`naturalLanguage`/`objectScope`) and history-lazy-load assertions (27 tests total in the file after this phase).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Jest test (new)                 | `soqlWhispererExportPermissionGranted.test.js` / `soqlWhispererExportPermissionDenied.test.js` | Two dedicated files (3 + 1 tests) because `@salesforce/customPermission/*` is a static, per-module-registry import that can only be set once per test file — can't be flipped mid-suite. Together they prove the Export button is rendered only when the custom permission is granted.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Design pattern doc (new)        | `docs/design-patterns/QueryHistoryService-patterns.md`                                         | Service Layer + Audit-Log pattern analysis.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Design pattern doc (new)        | `docs/design-patterns/SavedQueryService-patterns.md`                                           | Service Layer over a per-user Repository (upsert-by-natural-key) pattern analysis.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### Unchanged (verified, not modified)

| Type       | Name                                                                                                | Note                                                                                                                                                                      |
| ---------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex class | `SchemaService`, `TranslationProvider*`, `ClaudeTranslationProvider`, `EinsteinTranslationProvider` | Not touched by this phase. No object/field/permission changes affect schema introspection or translation.                                                                 |
| Apex class | `QueryService.validate()` / `runQuery()` internals                                                  | Unchanged beyond the `@AuraEnabled` removal noted above — still zero DML, still the two independent safety layers (structural SELECT-only check + `USER_MODE` execution). |

---

## Data flow

### Query run + history logging

1. User clicks **Run**. `soqlWhisperer.js` calls `runQuery({ soql, naturalLanguage, objectScope })`.
2. `SoqlWhispererController.runQuery` calls `QueryService.runQuery(soql)` — validation, then
   `Database.queryWithBinds(soql, {}, AccessLevel.USER_MODE)`. This step is unchanged from
   prior phases.
3. **On success:** the controller calls `QueryHistoryService.logRun(soql, naturalLanguage,
objectScope, rows.size(), 'Success', null)`, then returns `rows` to the LWC.
4. **On failure:** the controller calls `logRun(..., 0, 'Error', e.getMessage())`, then
   rethrows the original exception untouched, so the LWC's existing error-handling path is
   unaffected.
5. `logRun` inserts one `SOQL_Query_History__c` row (`AccessLevel.USER_MODE`), after
   defensively truncating every text value to its field's max length. If the insert fails
   for any reason (most commonly: the running user lacks the `SOQL_Whisperer_User`
   permission set), the failure is swallowed inside `logRun` — the user's query result is
   never affected.
6. If the history accordion is already open, `soqlWhisperer.js` calls `loadHistory()` again
   after the run completes so the new row appears without a manual refresh. If the accordion
   has never been opened, no history call is made at all (see "Lazy history load" below).

### Saved queries

1. On `connectedCallback`, `soqlWhisperer.js` calls `getSavedQueries()` →
   `SavedQueryService.listMine()` (`ORDER BY Name ASC LIMIT 200`, user-mode, no manual
   `OwnerId` filter — sharing does that) to populate the toolbar combobox.
2. **Save current** reveals an inline `lightning-input` name field. Confirming calls
   `saveQuery({ name, soql, naturalLanguage, objectScope })` →
   `SavedQueryService.saveQuery`, which looks up `WHERE Name = :name AND OwnerId =
:UserInfo.getUserId()`: if found, updates it in place; if not, inserts a new row. The
   combobox is reloaded after save.
3. **Selecting a saved query** in the combobox restores `soql`, `naturalLanguage`, and
   `objectScope` into the editor (`applyQueryContext`), so a subsequent Refine is grounded
   exactly as the original run was. Any object in the saved scope the user can no longer see
   is dropped rather than left as a dangling selection.
4. **Delete** calls `deleteSavedQuery(recordId)` → `SavedQueryService.deleteSavedQuery`, which
   does a user-mode `SELECT` before delete; a record the running user can't see resolves to
   "not found" rather than any cross-user leak.

### Query history panel

1. The "Query history" accordion section is collapsed by default. `getHistory` is **not**
   called on component init.
2. On first expand, `handleHistoryToggle` calls `loadHistory()`, which calls
   `getHistory({ limitSize: 25 })` → `QueryHistoryService.getRecent(25)`.
3. **Refresh** re-calls `loadHistory()` at the current limit. **Show more** doubles the
   client-side limit (25 → 50 → 100 → 200, capped) and reloads — the server independently
   clamps to `[1, 200]` regardless of what the client asks for.
4. **Load into editor** (a datatable row action) calls `applyQueryContext` with that row's
   `SOQL__c` / `Natural_Language__c` / `Object_Scope__c`, identical to the saved-query load
   path.
5. **Clear my history** shows a confirm step, then calls `clearHistory()` →
   `QueryHistoryService.clearMine()`, which deletes the running user's own rows only
   (`LIMIT 10000`) and returns the count deleted for the confirmation toast.

### CSV export

1. The **Export CSV** button renders only when `hasResults` is true **and** the user holds
   the `Export_Query_Results` custom permission (checked via the static
   `@salesforce/customPermission/Export_Query_Results` import).
2. `handleExport()` calls `buildCsv(resultRows, resultColumns)` — a pure function in
   `csvUtils.js` that builds the CSV entirely from data already in the browser's memory. No
   Apex call, no new SOQL query, no callout, no `ContentVersion`.
3. `buildCsv` header row = `resultColumns[].fieldName` (the same columns the datatable
   already renders, so the export always matches what's on screen). Per cell: null/undefined
   → empty string; non-primitive (nested relationship) values → `JSON.stringify` (mirrors the
   datatable's existing flat-column limitation rather than changing query behavior);
   RFC 4180 quoting for `"`, `,`, `\n`, `\r` (embedded quotes doubled); and — run **before**
   quoting, so the guard character survives inside the quoted field — a leading `=`, `+`,
   `-`, `@`, tab, or CR is prefixed with a single quote to block CSV/spreadsheet formula
   injection.
4. A UTF-8 BOM is prepended so Excel renders non-ASCII correctly.
5. `toCsvDataUri` wraps the result as `data:text/csv;charset=utf-8,<encoded>`, downloaded via
   a programmatically-clicked anchor with `download="soql-results-YYYYMMDD-HHmmss.csv"`. A
   `data:` URI was used instead of `URL.createObjectURL` for Lightning Locker / LWS
   compatibility; the trade-off is a browser-imposed size ceiling on data URIs (low hundreds
   of MB in practice), far beyond anything the datatable can realistically hold.

---

## File locations

| Component                             | Path                                                                                                                                                                                           |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom object `SOQL_Query_History__c` | `force-app/main/default/objects/SOQL_Query_History__c/`                                                                                                                                        |
| Custom object `SOQL_Saved_Query__c`   | `force-app/main/default/objects/SOQL_Saved_Query__c/`                                                                                                                                          |
| Page layouts                          | `force-app/main/default/layouts/SOQL_Query_History__c-SOQL Query History Layout.layout-meta.xml`, `force-app/main/default/layouts/SOQL_Saved_Query__c-SOQL Saved Query Layout.layout-meta.xml` |
| Custom permission                     | `force-app/main/default/customPermissions/Export_Query_Results.customPermission-meta.xml`                                                                                                      |
| Permission set                        | `force-app/main/default/permissionsets/SOQL_Whisperer_User.permissionset-meta.xml`                                                                                                             |
| Apex classes (new)                    | `force-app/main/default/classes/QueryHistoryService.cls`, `force-app/main/default/classes/SavedQueryService.cls`                                                                               |
| Apex class (modified)                 | `force-app/main/default/classes/SoqlWhispererController.cls`                                                                                                                                   |
| Apex class (one-line change)          | `force-app/main/default/classes/QueryService.cls`                                                                                                                                              |
| Apex test classes                     | `force-app/main/default/classes/QueryHistoryServiceTest.cls`, `force-app/main/default/classes/SavedQueryServiceTest.cls`, `force-app/main/default/classes/SoqlWhispererControllerTest.cls`     |
| LWC bundle                            | `force-app/main/default/lwc/soqlWhisperer/` (`soqlWhisperer.js`, `soqlWhisperer.html`, `csvUtils.js`)                                                                                          |
| Jest tests                            | `force-app/main/default/lwc/soqlWhisperer/__tests__/csvUtils.test.js`, `soqlWhisperer.test.js`, `soqlWhispererExportPermissionGranted.test.js`, `soqlWhispererExportPermissionDenied.test.js`  |
| Design pattern docs                   | `docs/design-patterns/QueryHistoryService-patterns.md`, `docs/design-patterns/SavedQueryService-patterns.md`                                                                                   |

---

## Test coverage summary

### Apex

**`QueryHistoryServiceTest`** (22 methods) — success log, error log, the **swallow-on-failure**
contract (`logRunSwallowsInsertFailureAndDoesNotThrow` — proves the caller still proceeds when
the insert cannot succeed), limit clamping (`null` → 25, `0`/negative → 1, `5000` → 200,
in-range unchanged), `CreatedDate DESC` ordering verified with a genuine 205-row bulk scenario
(`getRecentNeverReturnsMoreThan200RowsRegardlessOfRequestedLimit`), truncation at and over the
field-length boundary, restricted-picklist normalization, and `clearMine()` deleting only the
running user's own records and returning an accurate count. Includes a two-user
`System.runAs` isolation test
(`userIsolationHistoryIsNotVisibleOrDeletableAcrossUsers`) proving User B cannot see or delete
User A's history via `getRecent`/`clearMine`.

**`SavedQueryServiceTest`** (17 methods) — create; overwrite-by-same-name
(`saveQueryOverwritesExistingRecordWithSameName` — asserts the record count stays 1 and the
SOQL was updated, not duplicated); a different name correctly creates a separate record; blank
name and blank SOQL both rejected with `AuraHandledException`; list ordering; delete, including
a null-id and an already-deleted-id rejection path; truncation of over-length values. Includes
two two-user `System.runAs` isolation tests: one proving User B cannot see or delete User A's
saved queries, and one proving the same name used by two different owners produces two separate
records rather than colliding (this is the direct proof that `Name` is deliberately not unique
at the platform level, per the design).

**`SoqlWhispererControllerTest`** (18 methods total after this phase) — extended to assert a
history row is written on both a successful `runQuery` and a failed one, and that the original
`QueryService.QueryException` still propagates unchanged on failure. The failure-path test is
documented as **not** asserting the row survives via `getRecent()` — see "Known limitations"
below; the test only proves `logRun` is invoked, not that the row is durable in production.

### Jest (LWC)

59 tests passing across 4 files (verified via `npx jest force-app/main/default/lwc/soqlWhisperer`):

| File                                           | Tests | Covers                                                                                                                                                                                                                                                                               |
| ---------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `csvUtils.test.js`                             | 24    | Pure-function CSV builder: comma/quote/newline escaping, embedded-quote doubling, null/undefined handling, formula-injection prefixing (`=`, `+`, `-`, `@`, tab, CR), BOM presence, header-row correctness, non-primitive `JSON.stringify` fallback. 100% coverage of `csvUtils.js`. |
| `soqlWhisperer.test.js`                        | 27    | Phase 3 object-picker tests plus Phase 4 additions: saved-query selection repopulates `soql`/`naturalLanguage`/`objectScope`; history section issues no Apex call until the accordion is expanded.                                                                                   |
| `soqlWhispererExportPermissionGranted.test.js` | 3     | Export button renders and functions when `Export_Query_Results` is granted.                                                                                                                                                                                                          |
| `soqlWhispererExportPermissionDenied.test.js`  | 1     | Export button is absent when the custom permission is not granted.                                                                                                                                                                                                                   |

The export-permission tests are split into two files because
`@salesforce/customPermission/*` resolves to a static value once per Jest module registry —
it cannot be toggled mid-suite, so "granted" and "denied" each need their own file.

### Code review result

**APPROVED**, no warnings outstanding (one earlier test-comment overclaim in
`SoqlWhispererControllerTest` was fixed in a follow-up commit and re-verified). All eight
priority checks from the review brief passed: `QueryService` unchanged/zero DML; all new DML
targets only the two new objects via `AccessLevel.USER_MODE` inside the two new service
classes only; no `without sharing` or system-mode query/DML anywhere; no record-level result
data persisted or sent to any callout; CSV export makes no Apex call/callout/`ContentVersion`;
formula-injection defense and RFC 4180 escaping are genuinely implemented; `logRun` cannot
throw under any code path; history reads are bounded server-side regardless of client input.
Full review: `agent-output/review-verdict.md`.

---

## Security

- **DML boundary (the core new guarantee this phase introduces):** the project rule is
  read-only against _queried org data_, not "no DML ever." `QueryService.cls` remains 100%
  DML-free — the only change to it in this phase is removing a stray `@AuraEnabled`
  annotation, which closes a pre-existing gap where an LWC could call the executor directly
  and bypass history logging. All new `insert`/`update`/`delete` calls live in exactly two
  classes (`QueryHistoryService`, `SavedQueryService`), target exactly two objects
  (`SOQL_Query_History__c`, `SOQL_Saved_Query__c` respectively), and use
  `AccessLevel.USER_MODE` on every statement. This is verifiable by grepping those two files
  for DML keywords rather than by trusting prose.
- **`with sharing` everywhere.** `QueryHistoryService`, `SavedQueryService`, and
  `SoqlWhispererController` are all `with sharing`. No `without sharing` and no system-mode
  query or DML exist anywhere in this phase's diff.
- **Private sharing model for both new objects, by design.** Both `SOQL_Query_History__c` and
  `SOQL_Saved_Query__c` are OWD Private (internal and external), with no sharing rules. This
  is the _entire_ isolation mechanism: `getRecent`/`listMine` have **no** manual `OwnerId`
  filter, because the platform (OWD + `with sharing` + `USER_MODE`) already restricts reads to
  the running user's own records — a hand-rolled filter would duplicate the sharing model and
  would silently mask a misconfiguration if OWD were ever loosened. Proven, not assumed: both
  new test classes include real `System.runAs` two-user isolation tests exercising read _and_
  delete paths.
  - **Why saved queries specifically default to owner-only:** the SOQL _text itself_ can
    contain PHI in `WHERE`-clause literals (`WHERE MRN__c = '00481923'`, `WHERE
Diagnosis__c = 'HIV'`). Sharing a saved query would **not** let a recipient see data
    they aren't otherwise entitled to (execution always stays user-mode), but it would leak
    the search _criteria_ — which is itself sensitive. Team-shared saved queries were
    explicitly deferred to a future, deliberate `Is_Shared__c` decision rather than defaulted
    open.
  - `clearMine()` is the one deliberate exception with a manual `OwnerId` filter — not for
    security, but as a blast-radius guard, since a sysadmin with View All / Modify All Data
    would otherwise wipe every user's history from a button labelled "Clear my history."
    `saveQuery`'s `OwnerId` filter is likewise not a security check but the natural-key
    lookup for the overwrite rule.
- **No record-level data is ever persisted by this phase.** Both objects store query text and
  run metadata only (`SOQL__c`, `Natural_Language__c`, `Object_Scope__c`, `Row_Count__c`,
  `Status__c`, `Error_Message__c`) — no field on either object is capable of holding a result
  row, and neither `logRun` nor `saveQuery` ever receives `resultRows` as an argument.
- **Export is client-side only — no new egress path.** The CSV is built entirely from rows
  already in the LWC's memory; there is no new Apex method, no callout, and no
  `ContentVersion`/Salesforce Files record created. **Files/`ContentVersion` was deliberately
  rejected** as the export mechanism: a Files record has its own sharing model, independent of
  the source records' sharing/FLS, so a file could become reachable by users who cannot see
  the underlying data — strictly worse for PHI than a browser download, and it would also
  require DML on a standard object, violating the DML boundary above.
  - **Honest trade-off, not eliminated:** a CSV download does put permission-scoped PHI on
    the user's local disk. This is functionally equivalent to Salesforce's own "Export
    Report," but the `Export_Query_Results` custom permission lets an admin withhold export
    from users who may view data on screen but should not extract it to a local file.
- **CSV injection and RFC 4180 defense are real, not just documented:** `toCsvCell` in
  `csvUtils.js` prefixes any value beginning with `=`, `+`, `-`, `@`, tab, or CR with a single
  quote _before_ RFC 4180 quoting is applied (so the guard character survives inside the
  quoted field), and doubles embedded quotes. Covered by `csvUtils.test.js`.

---

## Deployment / setup (post-deploy manual step)

The `SOQL_Whisperer_User` permission set must be **assigned to every user of this tool** after
deployment. It is not optional — with `AccessLevel.USER_MODE` DML, the feature is inert
without it:

- Without the permission set: queries still run normally (execution is unaffected), but
  `logRun`'s insert is rejected for lack of Create access and silently swallowed — **the
  history panel simply stays empty**, with no error shown to the user. Saved queries and the
  export button behave the same way (empty saved-query list; export button hidden because the
  `Export_Query_Results` custom permission isn't granted).
- The permission set grants: Read/Create/Delete/**Edit** on `SOQL_Query_History__c` (Edit was
  added post-merge — see "Post-merge metadata corrections" below, it is platform-required and
  does **not** mean history rows are actually editable in practice); full CRUD on
  `SOQL_Saved_Query__c`; Read+Edit field permissions on every custom field on both objects; Apex
  class access to `SoqlWhispererController`, `QueryHistoryService`, `SavedQueryService`; and the
  `Export_Query_Results` custom permission.
- **If a user reports "history/saved queries aren't showing up," the first thing to check is
  whether `SOQL_Whisperer_User` is assigned** — this is the expected first symptom of a
  missing assignment, not a bug.

No scheduled jobs, batch classes, or additional configuration are introduced by this phase.

---

## Notes

### Known limitations

- **Failed-run history rows do not reliably survive in a deployed org.** `logRun` for the
  error path runs inside the same transaction as the failed query. `SoqlWhispererController
.runQuery` logs the error and then rethrows the original exception so the LWC's error
  handling is unaffected — but an exception escaping an `@AuraEnabled` method rolls the whole
  transaction back, **including the just-inserted error history row**. This is inherent to
  same-transaction synchronous logging; no try/catch arrangement fixes it, since Apex has no
  explicit commit. The real fix is an out-of-band write — most likely a Platform Event
  published with `publishBehavior = PublishImmediately` — which was out of scope for Phase 4
  and is carried forward as a Phase 5 candidate. This is documented in three places
  independently: the doc comment on `SoqlWhispererController.runQuery`, the "Rollback
  semantics" section of `docs/design-patterns/QueryHistoryService-patterns.md`, and a comment
  on `SoqlWhispererControllerTest.runQueryFailurePropagatesOriginalException` explicitly
  noting that the Apex test proves `logRun` was invoked, not that the row survives commit in
  production (an Apex test that catches the exception itself never crosses the transaction
  boundary the way a real `@AuraEnabled` failure does).
- **No automatic history purge.** Retention is manual "Clear my history" only. History
  storage grows indefinitely for a user who never clears it; a scheduled Apex batch purge was
  considered and deferred (see Phase 5 backlog) to avoid adding an unrequested scheduled job
  and activation step to this phase.
- **CSV export puts PHI on the user's local disk.** Mitigated, not eliminated, by the
  `Export_Query_Results` custom permission — see "Security" above.
- **Nested relationship fields still render poorly** in both the results datatable and the
  CSV export (pre-existing limitation, unchanged by this phase): a relationship object is
  flattened via `JSON.stringify` rather than resolved to a readable value.
- **Saved queries can go stale.** `SavedQueryService` stores an opaque SOQL string and never
  parses or validates it; if a referenced object or field is later deleted or its access
  revoked, the saved query fails at _run_ time when reloaded, not at save time.

### Future enhancement suggestions (Phase 5 backlog)

- `EinsteinTranslationProvider` native implementation — deferred since Phase 2, still a stub.
- A scheduled Apex batch purge for `SOQL_Query_History__c`, so retention isn't manual-only.
- Durable failed-run history logging via a `PublishImmediately` platform event (or equivalent
  out-of-band write) so error rows survive transaction rollback.
- Optional team-shared saved queries via an explicit `Is_Shared__c` flag and a criteria-based
  sharing rule — a deliberate, separately-reviewed decision given the PHI-in-criteria concern
  documented above, not a default.

### Dependencies

- `QueryHistoryService` and `SavedQueryService` depend on their respective custom objects and
  the `SOQL_Whisperer_User` permission set being deployed and assigned; see "Deployment /
  setup" above.
- The LWC's Export button depends on the `Export_Query_Results` custom permission being
  granted (via the permission set) to see any effect; the button element itself always
  exists in the DOM only when both conditions (`hasResults` and the permission) are true.

---

## Post-merge metadata corrections (2026-09-11)

Scratch-org deploy validation of Phase 4 failed with 3 platform-validation errors, all in
admin metadata (no Apex/LWC involved). Branch `feature/2026-09-11-phase4-metadata-fix`, commit
`a2c6ccd` (5 files), fixed all three; code review re-verified and re-**APPROVED** with no
warnings (see `agent-output/review-verdict.md`). The corrected statements earlier in this doc
already reflect the fixed state; this section explains what changed and why.

1. **`SOQL__c` field no longer marked `required` on either object.** The platform rejects
   `required=true` on a LongTextArea field outright — this was never deployable, not a design
   choice. `<required>` was flipped to `false` on `SOQL_Query_History__c.SOQL__c` and
   `SOQL_Saved_Query__c.SOQL__c`. Blank-SOQL enforcement was already living in Apex and needed
   no change: `SavedQueryService.saveQuery` throws before any DML if the SOQL argument is
   blank, so a saved query can never be persisted blank through the supported path. On the
   history side, `QueryHistoryService.logRun`'s error-logging path can legitimately write a
   `null` `SOQL__c` (e.g. when `QueryService.validate()` rejects an empty query before it
   executes) — this is harmless, since `SOQL_Query_History__c` is the tool's own internal log
   object, never queried org data, and the row still carries `Error_Message__c` so the failure
   isn't silently lost.
2. **Trailing empty `<layoutColumns />` removed** from the `OneColumn` "SOQL" section on both
   Phase 4 page layouts (platform error: "Too many columns for section style"). Purely
   cosmetic/structural; no field visibility changed.
3. **`allowEdit` set to `true` on `SOQL_Query_History__c`** in the `SOQL_Whisperer_User`
   permission set. The platform requires Edit access before it will grant Delete, and
   `QueryHistoryService.clearMine()` needs Delete under `AccessLevel.USER_MODE` — so this was
   also never deployable as originally written, not a scope change.
   - **Design consequence for future maintainers:** history-row immutability is **no longer
     platform-enforced by FLS**. It now holds only by convention: there is no update path
     against `SOQL_Query_History__c` anywhere in Apex or the LWC (`QueryHistoryService` exposes
     only `logRun`/insert and `clearMine`/delete; `SoqlWhispererController` has no history
     update passthrough; `soqlWhisperer.js` has no update call). If a future change adds an
     "edit history row" method, nothing in the permission set will stop it — the permission set
     alone can no longer be relied on to prove history rows can't be mutated after insert.
     Anyone touching `QueryHistoryService.cls` or the history data model should treat
     "history is insert/delete-only" as an intentional design rule to preserve, not something
     the platform still guarantees. (Flagged as a non-blocking suggestion by code review; a
     guard comment on the class, or a `before update`-always-fails validation rule if this ever
     becomes trigger-driven, would restore a platform-level check — deferred as a Phase 5
     candidate, out of scope for this metadata-only fix.)

The "Security" and "Deployment / setup" sections above, and the affected rows in "Components
created", have been updated in place to reflect these three fixes rather than the pre-fix
metadata.

### Round 2 — first real scratch-org deploy attempt (2026-09-11, commit `0539c4f`)

The `a2c6ccd` fix above was validated in a scratch org for the first time and still failed
deploy, with a generic `An unexpected error occurred. Please include this ErrorId...` on both
Phase 4 page layouts. Bisected the layout XML in the scratch org: the cause was an empty
self-closing `<summaryLayout />` element at the end of both layout files — the same defect
family as the empty `<layoutColumns />` fixed in `a2c6ccd` and previously in PR #6 (empty
self-closing elements the Metadata API's XML parser rejects unpredictably rather than with a
clear validation message). The line was removed from both files with no other change; removing
it lets the platform fall back to its own default compact/summary layout. Code review
re-**APPROVED**, no warnings (see "Prior review" round in `agent-output/review-verdict.md`).

---

## Post-merge test corrections (2026-09-11)

The same scratch-org validation pass that surfaced the layout defect above also ran the full
Apex test suite for the first time against a real scratch org (all prior test runs had been in
the design/dev sandbox where the running user was already a full admin with implicit access).
**22 of 91 Apex tests failed** with errors like `No such column 'SOQL__c'` and "field ... is not
accessible" against both `SOQL_Query_History__c` and `SOQL_Saved_Query__c`.

**Root cause:** custom fields deployed via the Metadata API grant Field-Level Security to
**nobody** by default, including System Administrator — this repo has no `profiles/` directory,
so there is no profile metadata granting FLS on deploy. `QueryHistoryService` and
`SavedQueryService` deliberately enforce `AccessLevel.USER_MODE` (SOQL `WITH USER_MODE`, DML
`AccessLevel.USER_MODE`) rather than system mode, per the project's permission-aware hard
constraint. A scratch-org test running in the default admin context — with no permission set
assigned — therefore has zero FLS on either object's fields, and `USER_MODE` correctly rejects
the access. This was never a service-code bug; it is exactly what `USER_MODE` is supposed to do
when the running identity is under-permissioned, and it had simply never been exercised by a
real scratch-org test run before now.

**Fix (commit `ce2b312`, salesforce-unit-testing, no production code changed):** every test
method that touches `SOQL_Query_History__c` or `SOQL_Saved_Query__c` — directly or via
`QueryHistoryService`/`SavedQueryService`/`SoqlWhispererController` — now runs inside
`System.runAs(<a user with the SOQL_Whisperer_User permission set assigned>)`, reusing the same
test-user factory pattern already established by the pre-existing two-user isolation tests. 26
methods were wrapped across `QueryHistoryServiceTest`, `SavedQueryServiceTest`, and
`SoqlWhispererControllerTest`. Methods that never reach SOQL/DML against either object (pure
`@TestVisible` helper tests, and tests that throw on blank-input validation before any query
runs) were correctly left unwrapped. No assertion was weakened or removed — each wrapped test
still asserts exactly what its unwrapped predecessor asserted; only the running identity
changed. Mixed-DML in `SoqlWhispererControllerTest`'s `@TestSetup` (a non-setup custom-setting
insert alongside setup-object `User`/`PermissionSetAssignment` inserts) is handled by isolating
just the two setup-object inserts inside `System.runAs(new User(Id = UserInfo.getUserId()))`,
the standard pattern for avoiding `MIXED_DML_OPERATION`. The three pre-existing two-user
`System.runAs` isolation tests (proving cross-user read/delete isolation) were already passing
and are unchanged — they remain the security proof that `USER_MODE` + OWD Private isolation
works; this fix only extends the same pattern to every other test that touches these objects.
Code review re-**APPROVED**, no warnings (see `agent-output/review-verdict.md`, "scratch-org
validation round 2").

> **Testing gotcha for future maintainers — read this before adding a new test.**
> Any Apex test that reads or writes `SOQL_Query_History__c` or `SOQL_Saved_Query__c` — whether
> directly or indirectly through `QueryHistoryService`, `SavedQueryService`, or
> `SoqlWhispererController` — **must** run inside `System.runAs()` as a user who has the
> `SOQL_Whisperer_User` permission set assigned. This repo has no `profiles/` directory, so
> Metadata-API-deployed custom fields have no FLS for **any** user, including the default
> System Administrator test context, and both services enforce field/object access via
> `AccessLevel.USER_MODE` rather than system mode. A test written against these objects without
> `System.runAs(<permission-set user>)` will pass in a design/dev sandbox where the running user
> already has broad implicit access, but will fail in a real scratch org with `No such column`
> or "field is not accessible" errors. See the existing `buildTestUser`/permission-set-assignment
> helper pattern already present in `QueryHistoryServiceTest`, `SavedQueryServiceTest`, and
> `SoqlWhispererControllerTest` and reuse it rather than re-deriving it.

---

## Change history

| Date       | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-09-10 | Initial creation — Phase 4 (result export, query history, saved queries). Two new custom objects + layouts + custom permission + permission set (admin), `QueryHistoryService`/`SavedQueryService`/controller changes + LWC export/saved-query/history UI + two design pattern docs (developer), full Apex + Jest test suites including two-user `System.runAs` isolation tests (unit testing), code review APPROVED with no warnings outstanding.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| 2026-09-11 | Post-merge metadata fix (scratch-org deploy validation failure) — `required=false` on both `SOQL__c` fields, removed a trailing empty `<layoutColumns />` from both Phase 4 layouts, `allowEdit=true` on `SOQL_Query_History__c` in `SOQL_Whisperer_User` (platform-required for `clearMine()`'s delete). 5 files, metadata-only, no Apex/LWC changed. Code review re-APPROVED, no warnings. History-row immutability is now enforced by convention (no update path in code), not by FLS — see "Post-merge metadata corrections" above.                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 2026-09-11 | Round 2 scratch-org validation, two fixes on branch `feature/2026-09-11-phase4-layout-and-test-fls-fix`: (1) removed an empty `<summaryLayout />` from both Phase 4 layouts, same defect family as the `<layoutColumns />` fix above, which was still breaking scratch-org deploy (commit `0539c4f`, admin). (2) 22/91 Apex tests failed on the first real scratch-org test run because metadata-deployed custom fields grant FLS to nobody and both services enforce `USER_MODE` — fixed by wrapping every test that touches `SOQL_Query_History__c`/`SOQL_Saved_Query__c` in `System.runAs(<SOQL_Whisperer_User user>)`, 26 methods across three test classes, zero assertions weakened, zero production code changed (commit `ce2b312`, unit testing). Code review re-APPROVED, no warnings. See "Post-merge metadata corrections" (Round 2) and "Post-merge test corrections" above — the latter states a durable testing rule for all future tests against these two objects. |
