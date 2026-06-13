/**
 * TranslationProvider backed by the Anthropic Claude API via an HTTP callout.
 * Endpoint lives in the 'AnthropicAPI' Named Credential. The API key is read from the
 * AnthropicSettings__c protected custom setting (set via Setup > Custom Settings,
 * never stored in source).
 * Used by orgs WITHOUT an Einstein entitlement.
 *
 * PHI NOTE: this path sends schemaContext (and only schemaContext + the user's text)
 * outside the Salesforce boundary. Do not place record-level data in the request for
 * Health Cloud orgs without the appropriate BAA/DPA in place.
 */
public with sharing class ClaudeTranslationProvider implements TranslationProvider {

    private static final String NAMED_CREDENTIAL = 'callout:AnthropicAPI';
    private static final String MODEL = 'claude-sonnet-4-6';

    public String translate(TranslationRequest req) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(NAMED_CREDENTIAL + '/v1/messages');
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setHeader('anthropic-version', '2023-06-01');
        httpReq.setHeader('x-api-key', AnthropicSettings__c.getInstance().ApiKey__c);
        httpReq.setTimeout(120000);

        Map<String, Object> body = new Map<String, Object>{
            'model' => MODEL,
            'max_tokens' => 1024,
            'system' => buildSystemPrompt(),
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => buildUserPrompt(req)
                }
            }
        };
        httpReq.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(httpReq);
        if (res.getStatusCode() != 200) {
            throw new TranslationException('Claude API error ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return extractSoql(res.getBody());
    }

    private String buildSystemPrompt() {
        return 'You translate natural-language requests into a single valid Salesforce SOQL query. '
             + 'Rules: output ONLY the SOQL, no prose, no markdown fences. '
             + 'Generate read-only SELECT queries only — never DML. '
             + 'Use ONLY the objects and fields provided in the schema. Never invent API names. '
             + 'Always include a LIMIT unless the user explicitly asks for all rows.';
    }

    private String buildUserPrompt(TranslationRequest req) {
        String p = 'Schema:\n' + req.schemaContext + '\n\n';
        if (req.isRefinement == true && String.isNotBlank(req.existingQuery)) {
            p += 'Existing query:\n' + req.existingQuery + '\n\n'
               + 'Adjust the existing query per this instruction: ' + req.naturalLanguage;
        } else {
            p += 'Request: ' + req.naturalLanguage;
        }
        return p;
    }

    @SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
    private String extractSoql(String responseBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> content = (List<Object>) parsed.get('content');
        for (Object block : content) {
            Map<String, Object> b = (Map<String, Object>) block;
            if (b.get('type') == 'text') {
                return ((String) b.get('text')).trim();
            }
        }
        throw new TranslationException('No text content in Claude response.');
    }

    public class TranslationException extends Exception {}
}
