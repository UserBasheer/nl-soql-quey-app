# Provider Callout Test Coverage (Phase 2 follow-up)

**Date:** 2026-06-13
**Status:** Completed
**Branch:** feature/2026-06-13-provider-callout-coverage

---

## Overview

**Original request:** Add Apex test coverage for both provider classes using `HttpCalloutMock` (`Test.setMock`) so the org-wide 75% coverage gate is met. Test-only — no production logic changes to either class.

**Summary:** This branch is a direct follow-up to Phase 2 PR #1 (`feature/2026-06-13-claude-provider-toggle`, merged via PR #1). When `salesforce-devops` ran scratch-org validation after that merge, deployment failed at Salesforce's 75% org-wide Apex code coverage gate — overall coverage was 24%, because `ClaudeTranslationProvider.cls` (80 lines) and `EinsteinTranslationProvider.cls` (39 lines) both sat at 0% coverage. All 13 existing tests still passed; this was purely a missing-tests gap, not a functional defect. This branch adds four new test classes in two commits:

1. `ClaudeTranslationProviderTest` and `EinsteinTranslationProviderTest` — exercise both provider classes via `Test.setMock(HttpCalloutMock.class, ...)`, with **zero changes** to either production class.
2. `SchemaServiceTest` and `SoqlWhispererControllerTest` (follow-up commit) — closed the *remaining* coverage gap on `SchemaService.cls` and `SoqlWhispererController.cls`, which were still at 0% after the first commit.

A subsequent `salesforce-devops` re-validation confirmed org-wide coverage rose from 61% to **95%**, with `SchemaService` and `SoqlWhispererController` each going from 0% to 100%, and **all 35 tests passing**. See [Final validation result](#final-validation-result) below.

---

## Components created

### Admin (declarative)

None. This is a test-only branch.

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Test class (new) | `ClaudeTranslationProviderTest` | 4 test methods covering `ClaudeTranslationProvider.translate()` end to end via `Test.setMock`, including success, refinement, and both error branches. |
| Test class (new) | `EinsteinTranslationProviderTest` | 1 test method covering `EinsteinTranslationProvider.translate()`'s prompt-build + unconditional "not yet wired" throw. |
| Test class (new, follow-up commit) | `SchemaServiceTest` | 6 test methods covering `SchemaService.listObjects()`, `describeObject()`, `buildSchemaContext()`, and the `SchemaException` error path. |
| Test class (new, follow-up commit) | `SoqlWhispererControllerTest` | 8 test methods covering every `@AuraEnabled` method on `SoqlWhispererController` (`getObjects`, `getFields`, `generateQuery`, `refineQuery`, `validateQuery`, `runQuery`), including mocked-callout and error-path cases. |

### Unchanged (verified, not modified)

| Type | Name | Note |
|------|------|------|
| Apex class | `ClaudeTranslationProvider` | Byte-for-byte unchanged. Still POSTs to `callout:AnthropicAPI/v1/messages`, sets `x-api-key` from `AnthropicSettings__c.getInstance().ApiKey__c`. |
| Apex class | `EinsteinTranslationProvider` | Unchanged stub — still throws `TranslationException('Einstein provider not yet wired...')` after building the prompt. |
| Apex class | `SchemaService` | Unchanged. `listObjects()`, `describeObject()`, and `buildSchemaContext()` (plus inner `SchemaException`, `ObjectInfo`, `FieldInfo`) are exercised but not modified. |
| Apex class | `SoqlWhispererController` | Unchanged. All six `@AuraEnabled` methods (`getObjects`, `getFields`, `generateQuery`, `refineQuery`, `validateQuery`, `runQuery`) are exercised but not modified. |
| Apex class | `QueryService` | Unchanged. `validate()` and `runQuery()` (with `Database.queryWithBinds(..., AccessLevel.USER_MODE)`) are exercised indirectly via `SoqlWhispererController.runQuery()`/`validateQuery()`. |
| Apex class | `TranslationProviderFactory` | Unchanged. `@TestVisible overrideProvider` static is used by `SoqlWhispererControllerTest` to force resolution to `ClaudeTranslationProvider` for `generateQuery()`/`refineQuery()` tests. |

---

## Data flow

This branch adds no new runtime data flow — it only adds tests that exercise the existing flow inside `ClaudeTranslationProvider.translate()`, `EinsteinTranslationProvider.translate()`, `SchemaService`, and `SoqlWhispererController`:

1. **`ClaudeTranslationProviderTest.setup()`** (`@TestSetup`) inserts one `AnthropicSettings__c` Hierarchy custom setting record with `ApiKey__c = 'dummy-test-key'`, so line 23 of `ClaudeTranslationProvider` (`AnthropicSettings__c.getInstance().ApiKey__c`) executes without a null reference. This is test fixture data only — never a real key.
2. Each `ClaudeTranslationProviderTest` method calls `Test.setMock(HttpCalloutMock.class, new StaticMock(statusCode, body))` before invoking `new ClaudeTranslationProvider().translate(req)`, inside `Test.startTest()` / `Test.stopTest()`. `StaticMock` is a private inner class implementing `HttpCalloutMock` that returns a fixed status code and body for any request, intercepting the real `Http().send()` call to `callout:AnthropicAPI/v1/messages`.
3. `EinsteinTranslationProviderTest` makes no callout at all — `EinsteinTranslationProvider.translate()` builds its grounded prompt via `buildPrompt(req)` and then unconditionally throws, so the test simply calls `translate()` and asserts the thrown exception.
4. `SchemaServiceTest` calls `SchemaService.listObjects()`, `describeObject('Account')`, `describeObject('NotARealObject__x')`, and `buildSchemaContext(...)` directly against the test org's live schema (no mocking needed — these are pure metadata describes).
5. `SoqlWhispererControllerTest` reuses the same `@TestSetup` + `StaticMock` pattern (its own copy of the inner `StaticMock` class implementing `HttpCalloutMock`) to mock the Claude callout for `generateQuery()`/`refineQuery()`, after setting `TranslationProviderFactory.overrideProvider = 'Claude'` to force provider resolution. `getObjects()`/`getFields()`/`validateQuery()` call through to `SchemaService`/`QueryService` against live org schema. `runQuery()` inserts a test `Account` record and asserts `QueryService.runQuery()` returns it via `Database.queryWithBinds(..., AccessLevel.USER_MODE)`.

---

## Test coverage summary

### `ClaudeTranslationProviderTest` (4 methods)

| Method | Scenario | Verifies |
|--------|----------|----------|
| `translateReturns200SuccessTrimmedSoql` | Mock returns 200 with `{"content":[{"type":"text","text":"  SELECT Id FROM Account LIMIT 10  "}]}` | `translate()` returns the SOQL **trimmed** of whitespace (`extractSoql()` line 73, `.trim()`) |
| `translateRefinementBranchReturnsMockedSoql` | `TranslationRequest.isRefinement = true`, `existingQuery` set, mock returns 200 with a refined SOQL string | The refinement branch of `buildUserPrompt()` (lines 57-59) executes and the mocked SOQL is returned |
| `translateNon200ResponseThrowsTranslationException` | Mock returns 500 / `'Internal Server Error'` | `ClaudeTranslationProvider.TranslationException` is thrown with a message containing `'500'` (line 42: `'Claude API error ' + res.getStatusCode() + ': ' + res.getBody()`) |
| `translateNoTextContentBlockThrowsTranslationException` | Mock returns 200 with `content: [{"type":"image", ...}]` (no `"text"` block) | `extractSoql()` throws `ClaudeTranslationProvider.TranslationException` containing `'No text content'` (line 76) |

All four methods are wrapped in `Test.startTest()` / `Test.stopTest()` and use a shared `@TestSetup` that inserts a single `AnthropicSettings__c` record (`ApiKey__c = 'dummy-test-key'`).

### `EinsteinTranslationProviderTest` (1 method)

| Method | Scenario | Verifies |
|--------|----------|----------|
| `translateThrowsNotYetWiredException` | Calls `translate()` with a basic `TranslationRequest` | `buildPrompt(req)` runs (and is therefore covered) before `translate()` unconditionally throws `EinsteinTranslationProvider.TranslationException` containing `'not yet wired'` (lines 21-24) |

### `SchemaServiceTest` (6 methods, follow-up commit)

Added in a follow-up commit (`2bd9eab`) to close the remaining 0% coverage gap on `SchemaService.cls`, which was untouched by the first commit above.

| Method | Scenario | Verifies |
|--------|----------|----------|
| `listObjectsReturnsAccessibleQueryableObjectsIncludingAccount` | Calls `SchemaService.listObjects()` | Returns a non-empty `List<ObjectInfo>`; the standard `Account` object is present with `apiName == 'Account'` and `label == 'Account'` |
| `describeObjectReturnsAccessibleFieldsForAccount` | Calls `SchemaService.describeObject('Account')` | Returns a non-empty `List<FieldInfo>`; the `Id` field is present with `type == 'ID'` and a non-null `label` |
| `describeObjectUnknownObjectThrowsSchemaException` | Calls `SchemaService.describeObject('NotARealObject__x')` | Throws `SchemaService.SchemaException` whose message contains `'NotARealObject__x'` (matches `'Unknown object: ' + objectApiName`) |
| `buildSchemaContextSingleObjectIncludesFieldNamesAndTypes` | Calls `SchemaService.buildSchemaContext(['Account'])` | Returned string starts with `'Account: '` and contains `'Id (ID)'` (format: `apiName + ' (' + type + ')'`) |
| `buildSchemaContextMultipleObjectsJoinedByNewline` | Calls `SchemaService.buildSchemaContext(['Account', 'Contact'])` | Returned string splits into 2 newline-separated blocks, starting with `'Account: '` and `'Contact: '` respectively |
| `buildSchemaContextEmptyListReturnsEmptyString` | Calls `SchemaService.buildSchemaContext([])` | Returns `''` (Apex `String.join` of an empty list of blocks) |

All six methods call into live org schema describes (no mocking required) and are wrapped in `Test.startTest()`/`Test.stopTest()`. This brought `SchemaService.cls` from 0% to 100% coverage.

### `SoqlWhispererControllerTest` (8 methods, follow-up commit)

Added alongside `SchemaServiceTest` in the same follow-up commit (`2bd9eab`) to close the remaining 0% coverage gap on `SoqlWhispererController.cls`, exercising every `@AuraEnabled` method.

| Method | Scenario | Verifies |
|--------|----------|----------|
| `getObjectsReturnsAccessibleQueryableObjects` | Calls `SoqlWhispererController.getObjects()` | Returns a non-empty list by delegating to `SchemaService.listObjects()` |
| `getFieldsReturnsAccessibleFieldsForAccount` | Calls `SoqlWhispererController.getFields('Account')` | Returned `List<FieldInfo>` includes the standard `Id` field, via `SchemaService.describeObject()` |
| `getFieldsUnknownObjectThrowsSchemaException` | Calls `SoqlWhispererController.getFields('NotARealObject__x')` | Propagates `SchemaService.SchemaException` unwrapped (the controller method has no try/catch) |
| `generateQueryReturnsMockedSoqlFromProvider` | Sets `TranslationProviderFactory.overrideProvider = 'Claude'`, mocks a 200 response (`{"content":[{"type":"text","text":"SELECT Id, Name FROM Account LIMIT 10"}]}`), calls `generateQuery('all accounts', ['Account'])` | Builds a schema context for the requested objects, resolves `ClaudeTranslationProvider` via the factory, and returns the SOQL parsed from the mocked response |
| `refineQueryReturnsMockedSoqlFromProviderRefinementBranch` | Same mock setup, mocked response is a `WHERE CreatedDate = LAST_N_DAYS:90` refinement; calls `refineQuery('only show ones created in the last 90 days', 'SELECT Id, Name FROM Account LIMIT 10', ['Account'])` | `refineQuery()` sets `isRefinement = true` and `existingQuery` on the `TranslationRequest` before calling `translate()`, exercising the refinement branch of `buildUserPrompt()`; returns the mocked refined SOQL |
| `validateQueryValidSelectReturnsNoErrors` | Calls `validateQuery('SELECT Id FROM Account LIMIT 5')` | Delegates to `QueryService.validate()`; returns an empty error list for a well-formed SELECT |
| `validateQueryNonSelectReturnsErrors` | Calls `validateQuery('DELETE FROM Account')` | Delegates to `QueryService.validate()`; returns a non-empty error list (both "must start with SELECT" and "Write operation 'delete' is not allowed") |
| `runQueryValidSelectReturnsResults` | Inserts a test `Account` record, calls `runQuery('SELECT Id, Name FROM Account')` | Delegates to `QueryService.runQuery()` -> `Database.queryWithBinds(..., AccessLevel.USER_MODE)`; returns the inserted record |
| `runQueryInvalidQueryThrowsQueryException` | Calls `runQuery('DELETE FROM Account')` | `QueryService.validate()` returns errors, so `runQuery()` throws `QueryService.QueryException` before any `Database` call |

Both `generateQueryReturnsMockedSoqlFromProvider` and `refineQueryReturnsMockedSoqlFromProviderRefinementBranch` reuse the same `@TestSetup` (inserting `AnthropicSettings__c` with `ApiKey__c = 'dummy-test-key'`) and an inner `StaticMock implements HttpCalloutMock` class — the identical pattern from `ClaudeTranslationProviderTest`, with an explicit code comment pointing back to it. Both tests set `TranslationProviderFactory.overrideProvider` immediately before use and reset it to `null` immediately after `Test.stopTest()`. This brought `SoqlWhispererController.cls` from 0% to 100% coverage.

### Coverage gap (documented, not fixed)

`EinsteinTranslationProvider.translate()` has exactly one execution path: it always throws after calling `buildPrompt()`. There is no conditional logic, so 100% of the *current* lines are exercised by the single test above. However, this means **only the "not yet wired" throw path can ever be covered** — there is no way to reach a successful-translation branch because none exists yet. When Item 3 (Einstein provider wiring, deferred per decision B2 — see `docs/2026-06-13-phase-2-claude-provider-toggle.md`) is implemented in a future phase, the native Models API call will need its own test seam (e.g., a mockable HTTP/ConnectApi call similar to `ClaudeTranslationProvider`'s `HttpCalloutMock` approach) — that seam does not exist today and was intentionally not added by this branch, per the constraint to make zero production changes.

---

## Final validation result

After both commits on this branch (`bc292c9` and `2bd9eab`), `salesforce-devops` re-ran scratch-org validation:

| Metric | Before (post-PR #1) | After this branch |
|--------|----------------------|---------------------|
| Org-wide Apex coverage | 24% | **61% -> 95%** (final, after both commits) |
| `ClaudeTranslationProvider.cls` | 0% | 100% |
| `EinsteinTranslationProvider.cls` | 0% | 100% |
| `SchemaService.cls` | 0% | 100% |
| `SoqlWhispererController.cls` | 0% | 100% |
| Tests passing | 13 / 13 | **35 / 35** |

The 95% result clears Salesforce's 75% org-wide Apex code coverage gate with significant margin. All four classes that previously sat at 0% (the two translation providers from the first commit, plus `SchemaService` and `SoqlWhispererController` from the follow-up commit) are now at 100% coverage, and the full org test suite of 35 tests passes with zero failures. No further test-coverage work is required for this branch.

---

## File locations

| Component | Path |
|-----------|------|
| New test class | `force-app/main/default/classes/ClaudeTranslationProviderTest.cls` |
| New test class meta | `force-app/main/default/classes/ClaudeTranslationProviderTest.cls-meta.xml` |
| New test class | `force-app/main/default/classes/EinsteinTranslationProviderTest.cls` |
| New test class meta | `force-app/main/default/classes/EinsteinTranslationProviderTest.cls-meta.xml` |
| New test class (follow-up commit) | `force-app/main/default/classes/SchemaServiceTest.cls` |
| New test class meta (follow-up commit) | `force-app/main/default/classes/SchemaServiceTest.cls-meta.xml` |
| New test class (follow-up commit) | `force-app/main/default/classes/SoqlWhispererControllerTest.cls` |
| New test class meta (follow-up commit) | `force-app/main/default/classes/SoqlWhispererControllerTest.cls-meta.xml` |
| Unchanged provider under test | `force-app/main/default/classes/ClaudeTranslationProvider.cls` |
| Unchanged provider under test | `force-app/main/default/classes/EinsteinTranslationProvider.cls` |
| Unchanged service under test | `force-app/main/default/classes/SchemaService.cls` |
| Unchanged controller under test | `force-app/main/default/classes/SoqlWhispererController.cls` |

All four new `.cls-meta.xml` files declare `apiVersion 66.0`, matching the project convention (no recurrence of the apiVersion-drift warning flagged in Phase 2).

---

## Security

- No production classes were modified across either commit — `with sharing`/`without sharing` and `USER_MODE` posture on `ClaudeTranslationProvider`, `EinsteinTranslationProvider`, `SchemaService`, `SoqlWhispererController`, and `QueryService` is unchanged.
- **No real HTTP callouts**: every `ClaudeTranslationProviderTest` method, plus `SoqlWhispererControllerTest`'s `generateQueryReturnsMockedSoqlFromProvider` and `refineQueryReturnsMockedSoqlFromProviderRefinementBranch`, use `Test.setMock(HttpCalloutMock.class, new StaticMock(...))` to intercept the `callout:AnthropicAPI/v1/messages` POST. `EinsteinTranslationProviderTest` and the remaining `SchemaServiceTest`/`SoqlWhispererControllerTest` methods perform no callout at all.
- **No secrets**: the `@TestSetup`-inserted `AnthropicSettings__c.ApiKey__c = 'dummy-test-key'` (used identically in both `ClaudeTranslationProviderTest` and `SoqlWhispererControllerTest`) is an obviously fake value, used only so the `x-api-key` header-setting line executes without a null-reference error.
- **DML scope**: the only DML in this branch is (1) the `@TestSetup` insert of an `AnthropicSettings__c` Hierarchy custom setting record (in both `ClaudeTranslationProviderTest` and `SoqlWhispererControllerTest`), and (2) a single `insert new Account(...)` inside `SoqlWhispererControllerTest.runQueryValidSelectReturnsResults` so `runQuery()` has a record to return. Both are isolated test fixtures, not production mutations.
- **`USER_MODE` preserved on the query path**: `SoqlWhispererControllerTest.runQueryValidSelectReturnsResults` and `runQueryInvalidQueryThrowsQueryException` exercise `SoqlWhispererController.runQuery()` -> `QueryService.runQuery()`, which still calls `Database.queryWithBinds(soql, new Map<String,Object>(), AccessLevel.USER_MODE)` (unchanged).
- **`overrideProvider` reset hygiene**: `TranslationProviderFactory.overrideProvider` is `@TestVisible private static String`. Both `SoqlWhispererControllerTest` methods that set it (`generateQueryReturnsMockedSoqlFromProvider`, `refineQueryReturnsMockedSoqlFromProviderRefinementBranch`) reset it to `null` immediately after `Test.stopTest()` and before the final `Assert`.
- No `@SeeAllData`, no hardcoded record IDs, no `System.debug()` calls in any of the four test classes.

---

## Notes

- **Why this branch exists:** Phase 2 PR #1 (`feature/2026-06-13-claude-provider-toggle`) was merged to `main`, but `salesforce-devops`'s scratch-org validation failed at the platform's 75% org-wide Apex coverage gate (actual: 24%), entirely because `ClaudeTranslationProvider` and `EinsteinTranslationProvider` had 0% coverage. The first commit on this branch closed that gap, raising org-wide coverage to 61% — still short of where `salesforce-devops` wanted headroom, and `SchemaService`/`SoqlWhispererController` remained at 0%. The follow-up commit (`2bd9eab`) added `SchemaServiceTest` and `SoqlWhispererControllerTest`, raising org-wide coverage to **95%** with all 35 tests passing — see [Final validation result](#final-validation-result).
- **Limitations:**
  - `EinsteinTranslationProvider` can only ever cover its single "not yet wired" throw path until Item 3 (native Models API wiring) is implemented in a future phase — see Coverage gap above.
  - The Phase 2 limitation regarding `TranslationProviderFactoryTest`'s unreachable "no CMDT record" fallback branch (documented in `docs/2026-06-13-phase-2-claude-provider-toggle.md`) is unrelated to this branch and remains open.
- **Dependencies:**
  - `ClaudeTranslationProviderTest` and `SoqlWhispererControllerTest` both depend on the `AnthropicSettings__c` custom setting object being deployed (it was deployed as part of an earlier phase; this branch does not deploy metadata).
  - All four test classes depend on `TranslationRequest`, `SchemaService`, `SoqlWhispererController`, `QueryService`, `TranslationProviderFactory`, and the respective provider classes (`ClaudeTranslationProvider`, `EinsteinTranslationProvider`) being present, which they are as of the Phase 2 merge.

---

## Change history

| Date | Change |
|------|--------|
| 2026-06-13 | Initial creation — adds `ClaudeTranslationProviderTest` (4 methods) and `EinsteinTranslationProviderTest` (1 method) to close the 0%-coverage gap that blocked devops scratch-org validation of Phase 2 PR #1. No production code changes. |
| 2026-06-13 | Updated — documents follow-up commit `2bd9eab`, which adds `SchemaServiceTest` (6 methods) and `SoqlWhispererControllerTest` (8 methods) to close the remaining coverage gap on `SchemaService.cls` and `SoqlWhispererController.cls` (both 0% -> 100%). Records final devops re-validation result: org-wide coverage 61% -> 95%, 35/35 tests passing. No production code changes. |
