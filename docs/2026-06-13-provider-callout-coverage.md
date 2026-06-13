# Provider Callout Test Coverage (Phase 2 follow-up)

**Date:** 2026-06-13
**Status:** Completed
**Branch:** feature/2026-06-13-provider-callout-coverage

---

## Overview

**Original request:** Add Apex test coverage for both provider classes using `HttpCalloutMock` (`Test.setMock`) so the org-wide 75% coverage gate is met. Test-only — no production logic changes to either class.

**Summary:** This branch is a direct follow-up to Phase 2 PR #1 (`feature/2026-06-13-claude-provider-toggle`, merged via PR #1). When `salesforce-devops` ran scratch-org validation after that merge, deployment failed at Salesforce's 75% org-wide Apex code coverage gate — overall coverage was 24%, because `ClaudeTranslationProvider.cls` (80 lines) and `EinsteinTranslationProvider.cls` (39 lines) both sat at 0% coverage. All 13 existing tests still passed; this was purely a missing-tests gap, not a functional defect. This branch adds two new test classes — `ClaudeTranslationProviderTest` and `EinsteinTranslationProviderTest` — that exercise both provider classes via `Test.setMock(HttpCalloutMock.class, ...)`, with **zero changes** to either production class.

---

## Components created

### Admin (declarative)

None. This is a test-only branch.

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Test class (new) | `ClaudeTranslationProviderTest` | 4 test methods covering `ClaudeTranslationProvider.translate()` end to end via `Test.setMock`, including success, refinement, and both error branches. |
| Test class (new) | `EinsteinTranslationProviderTest` | 1 test method covering `EinsteinTranslationProvider.translate()`'s prompt-build + unconditional "not yet wired" throw. |

### Unchanged (verified, not modified)

| Type | Name | Note |
|------|------|------|
| Apex class | `ClaudeTranslationProvider` | Byte-for-byte unchanged. Still POSTs to `callout:AnthropicAPI/v1/messages`, sets `x-api-key` from `AnthropicSettings__c.getInstance().ApiKey__c`. |
| Apex class | `EinsteinTranslationProvider` | Unchanged stub — still throws `TranslationException('Einstein provider not yet wired...')` after building the prompt. |

---

## Data flow

This branch adds no new runtime data flow — it only adds tests that exercise the existing flow inside `ClaudeTranslationProvider.translate()` and `EinsteinTranslationProvider.translate()`:

1. **`ClaudeTranslationProviderTest.setup()`** (`@TestSetup`) inserts one `AnthropicSettings__c` Hierarchy custom setting record with `ApiKey__c = 'dummy-test-key'`, so line 23 of `ClaudeTranslationProvider` (`AnthropicSettings__c.getInstance().ApiKey__c`) executes without a null reference. This is test fixture data only — never a real key.
2. Each `ClaudeTranslationProviderTest` method calls `Test.setMock(HttpCalloutMock.class, new StaticMock(statusCode, body))` before invoking `new ClaudeTranslationProvider().translate(req)`, inside `Test.startTest()` / `Test.stopTest()`. `StaticMock` is a private inner class implementing `HttpCalloutMock` that returns a fixed status code and body for any request, intercepting the real `Http().send()` call to `callout:AnthropicAPI/v1/messages`.
3. `EinsteinTranslationProviderTest` makes no callout at all — `EinsteinTranslationProvider.translate()` builds its grounded prompt via `buildPrompt(req)` and then unconditionally throws, so the test simply calls `translate()` and asserts the thrown exception.

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

### Coverage gap (documented, not fixed)

`EinsteinTranslationProvider.translate()` has exactly one execution path: it always throws after calling `buildPrompt()`. There is no conditional logic, so 100% of the *current* lines are exercised by the single test above. However, this means **only the "not yet wired" throw path can ever be covered** — there is no way to reach a successful-translation branch because none exists yet. When Item 3 (Einstein provider wiring, deferred per decision B2 — see `docs/2026-06-13-phase-2-claude-provider-toggle.md`) is implemented in a future phase, the native Models API call will need its own test seam (e.g., a mockable HTTP/ConnectApi call similar to `ClaudeTranslationProvider`'s `HttpCalloutMock` approach) — that seam does not exist today and was intentionally not added by this branch, per the constraint to make zero production changes.

---

## File locations

| Component | Path |
|-----------|------|
| New test class | `force-app/main/default/classes/ClaudeTranslationProviderTest.cls` |
| New test class meta | `force-app/main/default/classes/ClaudeTranslationProviderTest.cls-meta.xml` |
| New test class | `force-app/main/default/classes/EinsteinTranslationProviderTest.cls` |
| New test class meta | `force-app/main/default/classes/EinsteinTranslationProviderTest.cls-meta.xml` |
| Unchanged provider under test | `force-app/main/default/classes/ClaudeTranslationProvider.cls` |
| Unchanged provider under test | `force-app/main/default/classes/EinsteinTranslationProvider.cls` |

Both new `.cls-meta.xml` files declare `apiVersion 66.0`, matching the project convention (no recurrence of the apiVersion-drift warning flagged in Phase 2).

---

## Security

- No production classes were modified — `with sharing` and `USER_MODE` posture on `ClaudeTranslationProvider` and `EinsteinTranslationProvider` is unchanged.
- **No real HTTP callouts**: every `ClaudeTranslationProviderTest` method uses `Test.setMock(HttpCalloutMock.class, new StaticMock(...))` to intercept the `callout:AnthropicAPI/v1/messages` POST. `EinsteinTranslationProviderTest` performs no callout at all (the class throws before any native call).
- **No secrets**: the `@TestSetup`-inserted `AnthropicSettings__c.ApiKey__c = 'dummy-test-key'` is an obviously fake value, used only so the `x-api-key` header-setting line executes without a null-reference error.
- **DML scope**: the only DML in this branch is the single `@TestSetup` insert of an `AnthropicSettings__c` Hierarchy custom setting record — isolated test fixture data, not a production mutation.
- No `@SeeAllData`, no hardcoded record IDs, no `System.debug()` calls.

---

## Notes

- **Why this branch exists:** Phase 2 PR #1 (`feature/2026-06-13-claude-provider-toggle`) was merged to `main`, but `salesforce-devops`'s scratch-org validation failed at the platform's 75% org-wide Apex coverage gate (actual: 24%), entirely because `ClaudeTranslationProvider` and `EinsteinTranslationProvider` had 0% coverage. This branch closes that gap with test-only additions so devops can re-run validation and proceed with deployment.
- **Limitations:**
  - `EinsteinTranslationProvider` can only ever cover its single "not yet wired" throw path until Item 3 (native Models API wiring) is implemented in a future phase — see Coverage gap above.
  - The Phase 2 limitation regarding `TranslationProviderFactoryTest`'s unreachable "no CMDT record" fallback branch (documented in `docs/2026-06-13-phase-2-claude-provider-toggle.md`) is unrelated to this branch and remains open.
- **Dependencies:**
  - `ClaudeTranslationProviderTest` depends on the `AnthropicSettings__c` custom setting object being deployed (it was deployed as part of an earlier phase; this branch does not deploy metadata).
  - Both test classes depend on `TranslationRequest` and the respective provider classes (`ClaudeTranslationProvider`, `EinsteinTranslationProvider`) being present, which they are as of the Phase 2 merge.

---

## Change history

| Date | Change |
|------|--------|
| 2026-06-13 | Initial creation — adds `ClaudeTranslationProviderTest` (4 methods) and `EinsteinTranslationProviderTest` (1 method) to close the 0%-coverage gap that blocked devops scratch-org validation of Phase 2 PR #1. No production code changes. |
