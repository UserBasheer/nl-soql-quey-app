# NL SOQL Editor — Phase 1 (SOQL Whisperer)

**Date:** 2026-06-13
**Status:** Completed (Phase 1, documented retroactively)
**Branch:** N/A — this work predates the sf-agents pipeline and was built directly (Claude
browser app) before this repo's branch/PR workflow existed. The repo currently has no git
history (`git init` has not been run).

---

## Overview

**Original request:** Build a natural-language-to-SOQL editor for Salesforce — users connect
their org, write requests in plain English, and the tool generates an executable SOQL query
and returns the data. It is built as a native Salesforce LWC + Apex bundle (not an external
web app or browser extension) so that it runs inside the user's authenticated Salesforce
session and inherits their permissions.

**Summary:** Phase 1 delivers the full UI shell, native schema introspection, a two-layer
read-only query validator/executor, and a pluggable translation-provider abstraction with a
Claude (Anthropic API) implementation and a stubbed Einstein implementation. Everything
**except** natural-language translation is working end-to-end: a user can type raw SOQL into
the editable box, validate it, run it, and see results in a datatable, all permission-scoped
to the running user. The "Generate SOQL" and "Refine" buttons call through to the translation
layer, but that path is not yet usable until the `AnthropicAPI` Named Credential is
authenticated in the target org (Claude path) or the Einstein provider is implemented
(currently throws on call).

---

## Components created

### Admin (declarative)

| Type | API name | Description |
|------|----------|-------------|
| Custom object (Hierarchy Custom Setting) | `AnthropicSettings__c` | Protected custom setting that holds the Anthropic API key. Visibility `Protected`, type `Hierarchy`. Set via Setup > Custom Settings > Manage (org default) — the key is never stored in source. |
| Custom field | `AnthropicSettings__c.ApiKey__c` | Text(255). Holds the Anthropic Claude `x-api-key` header value. |
| Named Credential | `AnthropicAPI` | Endpoint `https://api.anthropic.com`, `principalType` = `NamedUser`, `generateAuthorizationHeader` = `false`. Auth (External Credential + `x-api-key` header) must be configured post-deploy in the target org — not part of source. Orgs using the Einstein path can ignore this entirely. |

### Development (code)

| Type | Name | Description |
|------|------|-------------|
| Apex class | `SoqlWhispererController` | `@AuraEnabled` orchestration layer exposed to the LWC. Entry points: `getObjects`, `getFields`, `generateQuery`, `refineQuery`, `validateQuery`, `runQuery`. `with sharing`. |
| Apex class | `SchemaService` | Native describe-based schema introspection (`Schema.getGlobalDescribe`). Lists queryable/accessible objects, describes accessible fields per object, and builds the compact schema-context string sent to the translation provider. `with sharing`. |
| Apex class | `QueryService` | Read-only query execution with two independent safety layers (see Security below). Exposes `validate(soql)` and `runQuery(soql)`. `with sharing`. |
| Apex class | `TranslationProvider` | Interface defining the NL→SOQL translation contract (`String translate(TranslationRequest request)`). |
| Apex class | `TranslationRequest` | Plain DTO carrying `naturalLanguage`, `schemaContext`, `existingQuery`, and `isRefinement` to a translation provider. |
| Apex class | `TranslationProviderFactory` | Selects a `TranslationProvider` implementation. Currently hardcoded to return `ClaudeTranslationProvider` (`resolveConfiguredProvider()` is a stub returning `'Claude'`). Has a `@TestVisible` `overrideProvider` static for tests. `with sharing`. |
| Apex class | `ClaudeTranslationProvider` | `TranslationProvider` implementation using an HTTP callout to the Anthropic Messages API via the `AnthropicAPI` Named Credential. Model: `claude-sonnet-4-6`. `with sharing`. |
| Apex class | `EinsteinTranslationProvider` | `TranslationProvider` implementation intended for the native Salesforce Einstein/Models API (keeps requests inside the Salesforce trust boundary — preferred for Health Cloud/PHI orgs). **Currently stubbed**: `translate()` always throws `EinsteinTranslationProvider.TranslationException` with a "not yet wired" message. `with sharing`. |
| Test class | `QueryServiceTest` | Covers `QueryService.validate()` (rejects non-SELECT, rejects embedded DML keywords, accepts a clean SELECT) and `QueryService.runQuery()` (returns rows for a valid SELECT, throws `QueryException` for a write statement). |
| LWC | `soqlWhisperer` | UI: natural-language textarea, Generate/Refine/Clear/Run/Validate-only buttons, an editable SOQL textarea, a validation status banner, and a `lightning-datatable` for results. Exposed to `lightning__AppPage`, `lightning__Tab`, `lightning__HomePage`. |

All Apex classes are at `apiVersion` 61.0 and the LWC bundle is at `apiVersion` 61.0 (project
convention in `CLAUDE.md` specifies 66.0 for new work going forward — Phase 1 predates that
convention and was not retroactively bumped).

---

## Data flow

1. **Page load** — the LWC can call `getObjects()` / `getFields(objectApiName)` (both
   `cacheable=true`) to enumerate queryable, accessible objects/fields via `SchemaService`.
   (Not currently wired into the UI's rendered output, but available to the controller.)
2. **Natural language input** — user types a request (e.g. "Show me accounts in California
   created in the last 30 days") into the NL textarea and clicks **Generate SOQL**.
3. **`generateQuery(naturalLanguage, objectScope)`** (LWC → `SoqlWhispererController`):
   - `objectScope` is currently **hardcoded in the LWC** to
     `['Account', 'Contact', 'Case', 'Opportunity', 'Lead']` (a known Phase 1 limitation —
     see Notes).
   - `SchemaService.buildSchemaContext(objectScope)` builds a compact text block of
     `ObjectName: field1 (Type), field2 (Type), ...` for each in-scope object, using only
     fields the running user can access (`isAccessible()`).
   - A `TranslationRequest` (NL text + schema context, `isRefinement = false`) is built and
     passed to `TranslationProviderFactory.getProvider().translate(req)`.
   - The factory currently always returns `ClaudeTranslationProvider`, which sends a system
     prompt + the schema context + the user's text to the Anthropic Messages API
     (`callout:AnthropicAPI/v1/messages`, model `claude-sonnet-4-6`) and extracts the raw SOQL
     text from the response. The result is **unvalidated** — the controller returns it
     directly to the LWC.
4. **Refine** — `handleRefine()` calls `refineQuery(instruction, existingQuery, objectScope)`,
   which builds a `TranslationRequest` with `isRefinement = true` and `existingQuery` set to
   the current SOQL box contents, asking the provider to adjust the existing query per the
   new instruction.
5. **Auto-validation after generate/refine** — the LWC immediately calls
   `runValidation()` → `validateQuery(soql)` → `QueryService.validate(soql)`, which returns a
   list of human-readable error strings (empty = valid). The UI shows a green "✓ Valid" banner
   or a red "✗ &lt;errors&gt;" banner accordingly.
6. **Manual validate** — the "Validate Only" button calls the same `validateQuery` path
   without running the query.
7. **Run** — the "Run Query" button calls `runQuery(soql)` →
   `QueryService.runQuery(soql)`, which re-runs `validate()` (throwing
   `QueryService.QueryException` if it fails) and then executes via
   `Database.queryWithBinds(soql, new Map<String, Object>(), AccessLevel.USER_MODE)`.
8. **Results** — returned `List<SObject>` rows are passed back to the LWC, which derives
   datatable columns from the keys of the first row (excluding `attributes`) and renders a
   `lightning-datatable`.
9. **Errors** — any thrown Apex exception (validation failure, query failure, Claude API
   error, Einstein "not wired" error) is caught in the LWC and shown in the same banner via
   `showError()`, reading `err.body.message`.

---

## File locations

| Component | Path |
|-----------|------|
| LWC bundle | `force-app/main/default/lwc/soqlWhisperer/` (`soqlWhisperer.html`, `.js`, `.css`, `.js-meta.xml`) |
| Apex classes | `force-app/main/default/classes/` |
| — Controller | `force-app/main/default/classes/SoqlWhispererController.cls` |
| — Schema introspection | `force-app/main/default/classes/SchemaService.cls` |
| — Query validation/execution | `force-app/main/default/classes/QueryService.cls` |
| — Query test class | `force-app/main/default/classes/QueryServiceTest.cls` |
| — Translation abstraction | `force-app/main/default/classes/TranslationProvider.cls`, `TranslationRequest.cls`, `TranslationProviderFactory.cls` |
| — Claude provider | `force-app/main/default/classes/ClaudeTranslationProvider.cls` |
| — Einstein provider (stub) | `force-app/main/default/classes/EinsteinTranslationProvider.cls` |
| Named Credential | `force-app/main/default/namedCredentials/AnthropicAPI.namedCredential-meta.xml` |
| Custom setting object | `force-app/main/default/objects/AnthropicSettings__c/AnthropicSettings__c.object-meta.xml` |
| Custom setting field | `force-app/main/default/objects/AnthropicSettings__c/fields/ApiKey__c.field-meta.xml` |

---

## Test coverage summary

- **`QueryServiceTest`** is the only test class in Phase 1. It covers:
  - `validate()` rejects a non-`SELECT` statement (e.g. `UPDATE Account SET Name = X`).
  - `validate()` rejects a `SELECT` with an embedded DML keyword (e.g. `... ; delete
    something`).
  - `validate()` accepts a clean `SELECT ... LIMIT 5`.
  - `runQuery()` returns rows for a valid `SELECT` after inserting a test `Account`.
  - `runQuery()` throws `QueryService.QueryException` for a write-style statement.
- No test classes exist yet for `SchemaService`, `SoqlWhispererController`,
  `TranslationProviderFactory`, `ClaudeTranslationProvider`, or `EinsteinTranslationProvider`.
  Note that `ClaudeTranslationProvider` makes a real HTTP callout and would need an
  `HttpCalloutMock` to be tested; `EinsteinTranslationProvider.translate()` currently always
  throws, so a test could only assert that exception.

---

## Security model

Two independent, intentionally redundant layers enforce **read-only** behavior
("belt-and-suspenders" per the code comments in `QueryService.cls`):

1. **Structural validation (`QueryService.validate(soql)`)** — runs before any execution:
   - Rejects blank input.
   - Requires the trimmed query to start with `select` (case-insensitive).
   - Scans for the forbidden keyword set `{insert, update, delete, upsert, merge, undelete}`
     anywhere in the query using word-boundary regex (`(?i)\bKEYWORD\b`), rejecting the query
     if any are found — this catches embedded/chained statements, not just the leading verb.
   - Returns a list of human-readable error strings; an empty list means the query is valid.
   - `runQuery()` re-runs `validate()` and throws `QueryService.QueryException` if any errors
     are present, **before** attempting execution.

2. **`AccessLevel.USER_MODE` execution** — valid queries are executed via
   `Database.queryWithBinds(soql, new Map<String, Object>(), AccessLevel.USER_MODE)`, which
   enforces field-level security (FLS) and sharing rules as the running user. A query
   referencing a field or object the user cannot see will fail or omit data accordingly,
   regardless of what the validator allowed through.

**Class-level sharing** — every Apex class in this bundle (`SoqlWhispererController`,
`SchemaService`, `QueryService`, `TranslationProviderFactory`, `ClaudeTranslationProvider`,
`EinsteinTranslationProvider`) is declared `with sharing`, so org-wide sharing rules are
respected in addition to `USER_MODE`'s FLS enforcement.

**Schema visibility** — `SchemaService.listObjects()` filters on `isQueryable() &&
isAccessible()`, and `SchemaService.describeObject()` filters fields on `isAccessible()`, so
the schema context sent to the translation provider — and the object/field lists available to
the UI — are already scoped to what the running user can see. This also reduces the chance of
the model "hallucinating" inaccessible fields into generated SOQL.

**Secrets handling** — the Anthropic API key is stored in the `AnthropicSettings__c` protected
Hierarchy custom setting (`ApiKey__c`, Text(255)), set via Setup > Custom Settings > Manage
(org default). It is read at runtime via `AnthropicSettings__c.getInstance().ApiKey__c` and
sent as the `x-api-key` header on the Claude callout. The key is never committed to source.
The `AnthropicAPI` Named Credential defines only the endpoint
(`https://api.anthropic.com`) with `generateAuthorizationHeader = false` and
`principalType = NamedUser`; per-org callout authentication (External Credential) must be
configured after deploy.

**PHI / data egress (Claude path only)** — per the header comment in
`ClaudeTranslationProvider.cls`, the request to the external Anthropic API carries **only**
`schemaContext` (object/field names and types) and the user's natural-language text — never
record-level data. For Health Cloud / PHI-bearing orgs, this path should not be enabled
without a security review and appropriate BAA/DPA, per `PHASE2.md`. The
`EinsteinTranslationProvider` (when implemented) is intended to keep the request inside the
Salesforce trust boundary (Einstein Trust Layer) as the PHI-safe alternative.

**Generated SOQL is never trusted** — both `generateQuery` and `refineQuery` return raw,
unvalidated SOQL text from the model. The LWC immediately calls `validateQuery` after either
action, and `runQuery` independently re-validates before execution — so model output can never
reach `Database.queryWithBinds` without passing the same `validate()` check as hand-typed SOQL.

---

## Notes

### Known limitations

- **Generate / Refine are not yet functional end-to-end.** The Claude path requires the
  `AnthropicAPI` Named Credential's auth (External Credential, `x-api-key` header) to be
  configured in the target org post-deploy; the Einstein path always throws
  `EinsteinTranslationProvider.TranslationException`. Until one of these is completed, users
  can only hand-type SOQL into the editable box and use Validate/Run.
- **`objectScope` is hardcoded** in `soqlWhisperer.js` to `['Account', 'Contact', 'Case',
  'Opportunity', 'Lead']`. This limits NL translation grounding to those five objects
  regardless of what the user actually asks about, and does not scale to large orgs with many
  custom objects. Flagged in `PHASE2.md` as a Phase 3 item (relevance-based schema retrieval).
- **`TranslationProviderFactory.resolveConfiguredProvider()` is hardcoded** to return
  `'Claude'`. There is no admin-facing toggle yet; `PHASE2.md` proposes a custom metadata type
  (e.g. `SOQL_Whisperer_Setting__mdt` with `Provider__c`) for Phase 2.
- **`getObjects()` / `getFields()` are not called from the LWC UI** in Phase 1 — they exist on
  the controller and `SchemaService` but the current `soqlWhisperer.html`/`.js` do not render
  an object/field picker.
- **No test coverage** beyond `QueryServiceTest`. `SchemaService`,
  `SoqlWhispererController`, `TranslationProviderFactory`, and the two translation providers
  are untested.
- **API version mismatch** — all Phase 1 metadata is at API version 61.0; the project
  convention (`CLAUDE.md`) specifies 66.0 for new work. Not retroactively changed for this
  doc.
- **No "assumption" surfacing** — the LWC has an `assumption` field and a corresponding
  warning banner in the template, but nothing in `soqlWhisperer.js` or the controller
  currently sets `this.assumption`. This appears to be a placeholder for a future feature
  (e.g. the model explaining assumptions it made while translating).

### Dependencies

- Standard objects `Account`, `Contact`, `Case`, `Opportunity`, `Lead` (referenced by the
  hardcoded `objectScope` and exercised by `QueryServiceTest`).
- `AnthropicSettings__c` custom setting + `AnthropicAPI` Named Credential, required only for
  the Claude translation path.
- No dependency on Health Cloud objects in Phase 1 — the PHI/data-egress constraints in
  `PHASE2.md` are forward-looking guardrails for when this tool is used in a Health Cloud org,
  not something Phase 1 code currently interacts with.

---

## Change history

| Date | Change |
|------|--------|
| 2026-06-13 | Phase 1 documented retroactively. Original Phase 1 build (LWC, Apex controller/services, translation provider abstraction, Claude provider, stubbed Einstein provider, `AnthropicSettings__c`/`AnthropicAPI` config) was completed and deployed prior to this repo's branch/PR workflow being established (built via the Claude browser app). See `PHASE2.md` for the handoff context driving Phase 2 work. |
