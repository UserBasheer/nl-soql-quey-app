
---
Deployed: 2026-06-13 20:55 (local)
Source: main (PR #2 merged, @3664163)
Scratch org validation: PASSED (35/35 tests, 100% pass, 95% org-wide coverage)
Target org: vscodeOrg / basheerprojects@runapex.com (Developer Edition, non-production)
Deployed: 20/22 components (5 schema/CMDT + 8 non-test classes + 6 test classes + 1 LWC)
Not deployed: AnthropicAPI_EC (ExternalCredential), AnthropicAPI (NamedCredential)
  Reason: sf CLI v2.30.8 Metadata API parse limitation on modern credential schema.
  Action: deploy manually via Setup UI or upgrade CLI and re-run credential-only deploy.

---
Deployed: 2026-09-15 21:31 EDT (2026-09-16T01:31:26Z)
Source: main (PR #8 merged, @2b0164f) — Phase 4: export / query history / saved queries
Deploy ID: 0AfgK00000TL89xSAD
Scratch org validation: PASSED (sf-agents-20260915212304, deploy 0AfAw00000PliAVKAZ)
  39/39 components Succeeded; 91/91 Apex tests pass, 0 failures; 97% org-wide / 98% test-run coverage
  Coverage: QueryHistoryService 100%, SavedQueryService 100%, ClaudeTranslationProvider 100%,
  TranslationRequest 100%, SchemaService 99%, SoqlWhispererController 98%, QueryService 94%,
  TranslationProviderFactory 87%, EinsteinTranslationProvider 82%. Scratch org deleted after run.
Target org: vscodeOrg / basheerprojects@runapex.com (Developer Edition, non-production)
Deployed: 39/39 components, 0 errors, status Succeeded
  Created: SOQL_Query_History__c (+6 fields), SOQL_Saved_Query__c (+3 fields),
           Export_Query_Results (CustomPermission), SOQL_Whisperer_User (PermissionSet),
           QueryHistoryService + QueryHistoryServiceTest, SavedQueryService + SavedQueryServiceTest
  Updated: SoqlWhispererController + SoqlWhispererControllerTest, QueryService, soqlWhisperer LWC,
           SOQL Query History Layout, SOQL Saved Query Layout, SOQL_Whisperer_Setting__mdt.Provider__c
Test level: NoTestRun (tests validated separately in the scratch org, 91/91)
  Reason: vscodeOrg's own org-wide coverage is 70% due to unrelated pre-existing apps, so
  RunLocalTests would have rolled the deploy back on the 75% gate. Same approach as Phase 3.
Not deployed: AnthropicAPI (NamedCredential), AnthropicAPI_EC (ExternalCredential)
  Reason: sf CLI v2.30.8 Metadata API parse limitation (unchanged since 2026-06-13).
  Status: both already exist in vscodeOrg, created manually via Setup on 2026-06-14.
  Note: org copies use the newer SecuredEndpoint format; force-app/ still holds the legacy
  format, so these two files remain drifted from org truth.
Post-deploy manual step: assign the SOQL_Whisperer_User permission set to intended users
  (required — MDAPI-deployed custom fields grant FLS to nobody, not even System Administrator).
  Handled by the orchestrator immediately after this deploy.
