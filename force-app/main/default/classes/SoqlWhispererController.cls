/**
 * @AuraEnabled entry points for the LWC. Orchestrates:
 *   schema introspection -> translation (provider chosen by factory) -> validation -> execution.
 */
public with sharing class SoqlWhispererController {

    @AuraEnabled(cacheable=true)
    public static List<SchemaService.ObjectInfo> getObjects() {
        return SchemaService.listObjects();
    }

    @AuraEnabled(cacheable=true)
    public static List<SchemaService.FieldInfo> getFields(String objectApiName) {
        return SchemaService.describeObject(objectApiName);
    }

    /** Generate a fresh SOQL query from natural language. Returns the SOQL (unexecuted). */
    @AuraEnabled
    public static String generateQuery(String naturalLanguage, List<String> objectScope) {
        TranslationRequest req = new TranslationRequest(
            naturalLanguage,
            SchemaService.buildSchemaContext(objectScope)
        );
        String soql = TranslationProviderFactory.getProvider().translate(req);
        return soql;
    }

    /** Refine an existing query from a follow-up instruction. */
    @AuraEnabled
    public static String refineQuery(String instruction, String existingQuery, List<String> objectScope) {
        TranslationRequest req = new TranslationRequest(
            instruction,
            SchemaService.buildSchemaContext(objectScope)
        );
        req.existingQuery = existingQuery;
        req.isRefinement = true;
        return TranslationProviderFactory.getProvider().translate(req);
    }

    @AuraEnabled
    public static List<String> validateQuery(String soql) {
        return QueryService.validate(soql);
    }

    @AuraEnabled
    public static List<SObject> runQuery(String soql) {
        return QueryService.runQuery(soql);
    }
}
