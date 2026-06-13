# NL SOQL Editor — Phase 2 Handoff

Context document for continuing in Claude Code (VS Code).

## What this project is
A natural-language-to-SOQL editor for Salesforce. Users connect their org, write requests in
plain English, and the tool generates an executable SOQL query and returns the data. Built as a
native Salesforce managed package (LWC + Apex), not an external web app or Chrome
extension — chosen deliberately so the tool runs inside the user's authenticated Salesforce
session and inherits their permissions.

## Hard requirements (do not violate)
- **STRICTLY READ-ONLY.** Never add insert/update/delete/upsert/merge paths anywhere.
  Read-only is enforced in two independent layers and both must stay.
- **Permission-aware.** Queries run in user mode so field-level security and sharing are
  enforced as the running user. Never bypass this with `without sharing` or system-mode
  queries.
- **PHI / data egress.** This is used with Health Cloud. The translation request must carry
  only schema context + the user's text — never record-level data — when using the
  external (Claude) provider. A security review is required before any PHI-bearing org
  uses the external path.

## Current architecture (Phase 1 — complete & deployed)
All under `force-app/main/default/`

### LWC: soqlWhisperer
- UI: natural-language input, editable SOQL box, validation banner, results datatable.
  Calls the Apex controller. `objectScope` is currently hardcoded to five common objects —
  this is a known limitation, see Phase 3.

### Apex classes
- **SoqlWhispererController** — `@AuraEnabled` orchestration exposed to the LWC
  (`getObjects`, `getFields`, `generateQuery`, `refineQuery`, `validateQuery`, `runQuery`).
- **SchemaService** — native describe introspection (`Schema.getGlobalDescribe`). Filters on
  `isAccessible()` so schema is permission-scoped. Builds the compact schema-context
  string used to ground translation.
- **QueryService** — read-only execution. Layer 1: `validate()` blocks non-SELECT and any
  DML keyword. Layer 2: `Database.queryWithBinds(..., AccessLevel.USER_MODE)`.
  Covered by `QueryServiceTest`.
- **TranslationProvider** (interface) + **TranslationRequest** (DTO) — the swappable translation
  abstraction.
- **ClaudeTranslationProvider** — HTTP callout to the Anthropic API via the `Claude_API`
  Named Credential. For orgs without Einstein.
- **EinsteinTranslationProvider** — native Models API path (keeps PHI in-platform).
  CURRENTLY STUBBED: throws a 'not yet wired' exception.
- **TranslationProviderFactory** — selects the provider. Currently defaults to Claude;
  intended to read an admin setting per org.

## What works now vs. what doesn't
- **WORKS after deploy:** schema introspection, SOQL validation, query execution, results
  table, permission scoping. You can type SOQL directly and run it.
- **DOES NOT WORK yet:** the Generate and Refine buttons. The Claude path needs the
  Named Credential auth configured in the org; the Einstein path is stubbed.

## Phase 2 — the goal
Make natural-language translation actually work end-to-end. Recommended order:
1. Wire the Claude callout path: configure the External Credential + Named Credential auth
   (`x-api-key` header) in the org, then verify `generateQuery` returns valid SOQL from a
   plain-English request.
2. Add the provider toggle: create a custom metadata type (e.g.
   `SOQL_Whisperer_Setting__mdt` with a `Provider__c` field) and have
   `TranslationProviderFactory.resolveConfiguredProvider()` read it instead of the hardcoded
   'Claude'.
3. Implement `EinsteinTranslationProvider` against the org's available Einstein Models API
   surface, for orgs that have the entitlement.
4. Verify the validate-before-run loop still holds for model output: generated SOQL must
   pass `QueryService.validate()` before execution. Never run unvalidated model output.

## Suggested first commands
```
sf project deploy start
sf apex run test --tests QueryServiceTest --result-format human
```
Then configure the Named Credential auth in the org and exercise the Generate button against
the connected Developer Edition org.

## Open items being tracked
- Einstein Models API implementation (stubbed).
- Provider toggle via custom metadata.
- PHI / data-egress security review before any Health Cloud org uses the external Claude
  path.
- Large-org schema-subset retrieval (replace the hardcoded `objectScope`) — Phase 3.
- Result export, query history, saved queries — Phase 3 polish.

## A note on suggesting changes
If a simpler or better approach than what's described here becomes apparent while building —
say so rather than following this document literally. The read-only and permission/PHI
requirements are firm; most other choices are open to improvement.
