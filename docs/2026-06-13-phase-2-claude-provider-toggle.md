# Phase 2 — Claude Provider Toggle (Items 1, 2, 4)

**Date:** 2026-06-13
**Status:** Completed
**Branch:** feature/2026-06-13-claude-provider-toggle

---

## Overview

**Original request:** Implement Phase 2 of `PHASE2.md`, scoped to Items 1, 2, and 4 only (Item 3 — `EinsteinTranslationProvider` — deferred to a future phase, per user decision B2). The goal was to make natural-language-to-SOQL translation work end-to-end for the **Claude** provider, with:

- **A2** — A minimal External Credential shell linked to the existing `AnthropicAPI` Named Credential, so the org treats the Claude callout as a permitted/authenticated route, **without** the Named Credential injecting any `x-api-key` header or storing any secret in metadata. `ClaudeTranslationProvider` continues to set `x-api-key` itself in Apex from the existing `AnthropicSettings__c` protected custom setting.
- **B2** — `EinsteinTranslationProvider` stays stubbed/untouched this phase.
- **C2** — A new `SOQL_Whisperer_Setting__mdt` custom metadata type with a `Provider__c` Text field, so an admin can toggle between "Claude" and "Einstein" without a code change. Defaults to `"Claude"` when no record exists or the value is blank, preserving the existing loose-string-compare semantics in `TranslationProviderFactory.getProvider()`.
- **Item 4** — Verify (and lock in via tests) that `QueryService.runQuery()` always calls `validate()` before executing any query in `USER_MODE`. This required no new runtime code — `runQuery()` already had this guarantee — so the work was test-only.

**Summary:** This phase wires up the org-level plumbing that lets `ClaudeTranslationProvider` make its callout (External Credential shell + Named Credential linkage), introduces an admin-configurable provider toggle (`SOQL_Whisperer_Setting__mdt.Provider__c`) that `TranslationProviderFactory.resolveConfiguredProvider()` now reads instead of a hardcoded `'Claude'`, and adds tests that lock in both the provider-selection logic and the read-only validate-before-run guarantee of `QueryService`. No DML, no secrets in metadata, and no changes to `ClaudeTranslationProvider` or `EinsteinTranslationProvider` were made.

---

## Components created

### Admin (declarative)

| Type | API name | Description |
|------|----------|-------------|
| External Credential | `AnthropicAPI_EC` | Minimal shell (label "AnthropicAPI EC") using `NoAuthentication` with a single `NamedPrincipal` (`AnthropicApiPrincipal`). Configures **no** header-injecting parameters and stores **no** secrets — exists solely so `AnthropicAPI` Named Credential is a valid, linkable authenticated callout route. |
| Named Credential (modified) | `AnthropicAPI` | Added `<externalCredential>AnthropicAPI_EC</externalCredential>` linkage. Endpoint (`https://api.anthropic.com`), `generateAuthorizationHeader=false`, and `principalType=NamedUser` are unchanged — no header parameters added, no key stored. |
| Custom Metadata Type | `SOQL_Whisperer_Setting__mdt` | New CMDT, label "SOQL Whisperer Setting", visibility `Public`. Configures which translation provider (`Claude` or `Einstein`) the app uses. |
| Custom field | `SOQL_Whisperer_Setting__mdt.Provider__c` | Text(40), not required, not unique. Holds the provider name (`"Claude"` or `"Einstein"`). Description documents the loose-compare/fallback contract for future maintainers. |
| Custom Metadata record | `SOQL_Whisperer_Setting.Default` | Ships with `Provider__c = "Claude"`, `protected=false`. Provides Setup visibility into the active provider; not a hard dependency since the code defaults to `"Claude"` even if this record is absent. |

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Apex class (modified) | `TranslationProviderFactory` | `resolveConfiguredProvider()` no longer hardcodes `return 'Claude';`. It now reads `SOQL_Whisperer_Setting__mdt.getAll()`, prefers the record named `Default`, falls back to any other available record, and returns `'Claude'` if no record exists or `Provider__c` is blank. `getProvider()`'s loose `== 'Einstein'` compare and the `@TestVisible overrideProvider` seam are unchanged. |
| Test class (new) | `TranslationProviderFactoryTest` | 5 test methods covering: no-override (uses shipped `Default` CMDT record → Claude), override = `'Einstein'` → Einstein provider, override = `'Claude'` → Claude provider, override = unrecognized value → falls back to Claude, and an explicit confirmation that the shipped `Default` record (`Provider__c = "Claude"`) resolves to Claude. Documents a known coverage gap (see Known limitations). |
| Test class (modified) | `QueryServiceTest` | Added 2 new test methods locking in Item 4: `runQueryRejectsNonSelectBeforeExecution` (a `DELETE FROM Account` statement is rejected via `validate()` before any query execution is attempted) and `runQueryRejectsBlankInput` (blank input is rejected with an "empty" message). Both assert a `QueryService.QueryException` is thrown with a descriptive message. |

### Unchanged (verified, not modified)

| Type | Name | Note |
|------|------|------|
| Apex class | `ClaudeTranslationProvider` | Byte-for-byte unchanged. Still sets `x-api-key` from `AnthropicSettings__c.getInstance().ApiKey__c` and calls `callout:AnthropicAPI/v1/messages`. |
| Apex class | `EinsteinTranslationProvider` | Unchanged stub, per B2 — deferred to a future phase. |
| Apex class | `QueryService` | Unchanged. `runQuery()` already called `validate()` before `Database.queryWithBinds(..., AccessLevel.USER_MODE)`; this phase only added tests that lock in that behavior. |

---

## Data flow

1. **Provider selection** — When `TranslationProviderFactory.getProvider()` is called:
   - If `@TestVisible overrideProvider` is set (test-only seam), that value is used.
   - Otherwise, `resolveConfiguredProvider()` reads `SOQL_Whisperer_Setting__mdt.getAll()`, looks for a record named `Default`, falls back to the first available record if `Default` doesn't exist, and returns `'Claude'` if no record exists or `Provider__c` is blank.
   - `getProvider()` then does a loose compare: if the resolved value `== 'Einstein'`, return `new EinsteinTranslationProvider()`; otherwise return `new ClaudeTranslationProvider()`. With the shipped `Default` record (`Provider__c = "Claude"`), this resolves to `ClaudeTranslationProvider`.

2. **Claude translation callout** — `ClaudeTranslationProvider.translate()` builds an HTTP POST to `callout:AnthropicAPI/v1/messages`, sets `x-api-key` from `AnthropicSettings__c.getInstance().ApiKey__c` (custom setting, configured via Setup, never in source), sends `schemaContext` + the user's natural-language text + (optionally) an existing query for refinement, and parses the Claude response to extract the generated SOQL string.

3. **Callout authorization plumbing (Item 1/A2)** — The `AnthropicAPI` Named Credential is linked to the new `AnthropicAPI_EC` External Credential shell so the org permits the callout as an authenticated route. The shell uses `NoAuthentication` and injects no headers — `ClaudeTranslationProvider` remains solely responsible for setting `x-api-key`.

4. **Validate-before-run (Item 4)** — Whatever SOQL string comes back from the translation provider, `QueryService.runQuery(soql)`:
   - Calls `validate(soql)` first, which checks the input is non-blank, starts with `SELECT`, and contains no forbidden DML keywords (`insert`, `update`, `delete`, `upsert`, `merge`, `undelete`).
   - If `validate()` returns any errors, throws `QueryService.QueryException` and **never** reaches `Database.queryWithBinds()`.
   - If valid, executes via `Database.queryWithBinds(soql, new Map<String, Object>(), AccessLevel.USER_MODE)`, enforcing FLS and sharing as the running user — a second, independent safety layer beyond the structural validation.

---

## File locations

| Component | Path |
|-----------|------|
| External Credential | `force-app/main/default/externalCredentials/AnthropicAPI_EC.externalCredential-meta.xml` |
| Named Credential | `force-app/main/default/namedCredentials/AnthropicAPI.namedCredential-meta.xml` |
| CMDT object | `force-app/main/default/objects/SOQL_Whisperer_Setting__mdt/SOQL_Whisperer_Setting__mdt.object-meta.xml` |
| CMDT field | `force-app/main/default/objects/SOQL_Whisperer_Setting__mdt/fields/Provider__c.field-meta.xml` |
| CMDT default record | `force-app/main/default/customMetadata/SOQL_Whisperer_Setting.Default.md-meta.xml` |
| Apex classes (modified/new) | `force-app/main/default/classes/TranslationProviderFactory.cls`, `force-app/main/default/classes/TranslationProviderFactoryTest.cls` |
| Apex test (modified) | `force-app/main/default/classes/QueryServiceTest.cls` |
| Unchanged provider classes | `force-app/main/default/classes/ClaudeTranslationProvider.cls`, `force-app/main/default/classes/EinsteinTranslationProvider.cls` |
| Unchanged query service | `force-app/main/default/classes/QueryService.cls` |

---

## Test coverage summary

| Test class | Methods | Coverage focus |
|------------|---------|----------------|
| `TranslationProviderFactoryTest` | 5 | All four `getProvider()` branches (no override using shipped Default CMDT, override=`Einstein`, override=`Claude`, override=unrecognized → Claude fallback), plus an explicit check that the shipped `Default` CMDT record (`Provider__c = "Claude"`) resolves to `ClaudeTranslationProvider`. |
| `QueryServiceTest` | 7 (5 existing + 2 new) | Existing: rejects non-SELECT, rejects embedded DML keyword, accepts clean SELECT, `runQuery` returns rows, `runQuery` blocks writes. New: `runQueryRejectsNonSelectBeforeExecution` (non-SELECT statement throws `QueryException` before execution), `runQueryRejectsBlankInput` (blank input throws `QueryException` with an "empty" message). |

All new/modified test methods include descriptive assertion failure messages.

---

## Security

- `with sharing` preserved on `TranslationProviderFactory` and `QueryService` (no regressions).
- `QueryService.runQuery()` continues to enforce **two independent layers**: (1) structural `validate()` — must be `SELECT`, no DML keywords; (2) `Database.queryWithBinds(..., AccessLevel.USER_MODE)` — FLS and sharing enforced as the running user.
- **No secrets in metadata**: `AnthropicAPI_EC.externalCredential-meta.xml` uses `NoAuthentication` with a single `NamedPrincipal` and no `externalCredentialParameters`. The Anthropic API key remains exclusively in `AnthropicSettings__c.ApiKey__c` (protected custom setting, configured via Setup, never committed to source).
- `AnthropicAPI.namedCredential-meta.xml` keeps `generateAuthorizationHeader=false` — the Named Credential injects no headers; `ClaudeTranslationProvider` sets `x-api-key` itself.
- `SOQL_Whisperer_Setting__mdt` has `visibility=Public`, appropriate for a Setup-visible admin toggle readable via `getAll()`. CMDT is globally readable by design; no new permission set was created or required.
- No DML (insert/update/delete/upsert/merge/undelete) introduced anywhere in this phase's diff.

---

## Notes

- **Limitations:**
  - **Coverage gap (documented in `TranslationProviderFactoryTest`)**: the "no CMDT record" / "blank `Provider__c`" fallback branch inside `resolveConfiguredProvider()` cannot be exercised in isolation — CMDT records can't be inserted via DML or `Test.loadData` in Apex tests, and the factory has no dependency-injection seam for `SOQL_Whisperer_Setting__mdt.getAll()`. Both the "shipped Default record" and "no record" paths converge on `'Claude'`, so behavior is covered end-to-end, but the fallback branch itself is not independently asserted. A future phase could add a `@TestVisible` static override map for `SOQL_Whisperer_Setting__mdt` records if isolated coverage becomes a hard requirement.
  - **Item 3 (`EinsteinTranslationProvider`) remains a stub** — deferred per user decision B2. Setting `SOQL_Whisperer_Setting__mdt.Provider__c = "Einstein"` will route to `EinsteinTranslationProvider`, which currently throws a "not yet wired" exception.
  - Two **pre-existing, non-blocking apiVersion-drift warnings** were flagged in code review (APPROVED WITH WARNINGS): `QueryServiceTest.cls-meta.xml` and `TranslationProviderFactory.cls-meta.xml` remain at `61.0` vs. the project's `66.0` convention. Neither affects functionality, security, or the hard constraints (read-only, USER_MODE, no secrets in metadata) — all of which pass. Can be bundled into a future housekeeping pass.

- **Dependencies:**
  - `TranslationProviderFactory.resolveConfiguredProvider()` depends on the `SOQL_Whisperer_Setting__mdt` CMDT and its shipped `Default` record being deployed.
  - `ClaudeTranslationProvider` depends on `AnthropicSettings__c.ApiKey__c` (custom setting) being populated by an admin via Setup, and on the `AnthropicAPI` Named Credential (now linked to `AnthropicAPI_EC`) being deployed.
  - To switch the org to Einstein once Item 3 is implemented, an admin would update the `SOQL_Whisperer_Setting.Default` CMDT record's `Provider__c` value to `"Einstein"` — no code change required.

---

## Change history

| Date | Change |
|------|--------|
| 2026-06-13 | Initial creation — Phase 2, Items 1, 2, 4 (Claude provider toggle, External Credential shell, validate-before-run lock-in). Item 3 (Einstein) deferred. |
