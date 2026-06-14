
---
Deployed: 2026-06-13 20:55 (local)
Source: main (PR #2 merged, @3664163)
Scratch org validation: PASSED (35/35 tests, 100% pass, 95% org-wide coverage)
Target org: vscodeOrg / basheerprojects@runapex.com (Developer Edition, non-production)
Deployed: 20/22 components (5 schema/CMDT + 8 non-test classes + 6 test classes + 1 LWC)
Not deployed: AnthropicAPI_EC (ExternalCredential), AnthropicAPI (NamedCredential)
  Reason: sf CLI v2.30.8 Metadata API parse limitation on modern credential schema.
  Action: deploy manually via Setup UI or upgrade CLI and re-run credential-only deploy.
