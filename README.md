# NL SOQL Editor (SOQL Whisperer)

Natural-language -> SOQL editor for Salesforce. Native managed-package approach:
LWC UI + Apex backend. Strictly read-only, permission-aware (runs in user mode).

## Architecture (Phase 1)
- **soqlWhisperer** (LWC) — UI: NL input, editable SOQL, results datatable.
- **SoqlWhispererController** — @AuraEnabled orchestration for the LWC.
- **SchemaService** — native describe introspection; builds grounded schema context.
- **QueryService** — read-only execution. Two layers: structural validation + USER_MODE.
- **TranslationProvider** (interface) with two implementations:
  - **EinsteinTranslationProvider** — native Models API (PHI stays in-platform). *Stubbed pending Einstein enablement.*
  - **ClaudeTranslationProvider** — HTTP callout via the `AnthropicAPI` Named Credential.
  - **TranslationProviderFactory** — picks the provider per org (defaults to Claude).

## Deploy
    sf project deploy start
    sf apex run test --tests QueryServiceTest --result-format human

## Open items
- Wire the Einstein Models API call in EinsteinTranslationProvider.
- Provider toggle via custom metadata (SOQL_Whisperer_Setting__mdt).
- PHI/data-egress review for the Claude path on Health Cloud orgs.
- Schema-subset retrieval for large orgs (Phase 3).
