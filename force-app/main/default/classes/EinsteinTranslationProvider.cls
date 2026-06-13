/**
 * TranslationProvider backed by the native Salesforce Einstein / Models API.
 * Keeps the request inside the Salesforce trust boundary (Einstein Trust Layer:
 * masking, zero-retention) — preferred for Health Cloud / PHI-adjacent orgs.
 * Requires an Einstein entitlement; orgs without one use ClaudeTranslationProvider.
 *
 * NOTE: the exact Models API invocation surface (ConnectApi / aiplatform namespace)
 * depends on the org's enabled features and API version. This class isolates that
 * call so the rest of the system is unaffected by how the native call is made.
 */
public with sharing class EinsteinTranslationProvider implements TranslationProvider {

    public String translate(TranslationRequest req) {
        // Build the same grounded prompt used for the Claude path.
        String prompt = buildPrompt(req);

        // ---- Native Models API invocation goes here. ----
        // Implemented against the org's available Einstein Models API surface
        // (e.g. aiplatform.ModelsAPI / ConnectApi generation endpoints). Stubbed
        // so the pipeline compiles and is wired end-to-end before Einstein is enabled.
        throw new TranslationException(
            'Einstein provider not yet wired. Enable Einstein and implement the Models API call, '
          + 'or switch the provider toggle to Claude.'
        );
    }

    private String buildPrompt(TranslationRequest req) {
        String base = 'Translate to a single read-only SOQL SELECT using ONLY the provided schema. '
                    + 'Output only SOQL. Always include LIMIT unless the user asks for all.\n\n'
                    + 'Schema:\n' + req.schemaContext + '\n\n';
        if (req.isRefinement == true && String.isNotBlank(req.existingQuery)) {
            return base + 'Existing query:\n' + req.existingQuery
                 + '\n\nAdjust per: ' + req.naturalLanguage;
        }
        return base + 'Request: ' + req.naturalLanguage;
    }

    public class TranslationException extends Exception {}
}
