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
  public static String generateQuery(
    String naturalLanguage,
    List<String> objectScope
  ) {
    TranslationRequest req = new TranslationRequest(
      naturalLanguage,
      SchemaService.buildSchemaContext(objectScope)
    );
    String soql = TranslationProviderFactory.getProvider().translate(req);
    return soql;
  }

  /** Refine an existing query from a follow-up instruction. */
  @AuraEnabled
  public static String refineQuery(
    String instruction,
    String existingQuery,
    List<String> objectScope
  ) {
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

  /**
   * Run a query and record the attempt in history.
   *
   * `QueryService.runQuery` is unchanged and still the only executor: validate() then
   * USER_MODE execution. History logging happens HERE, after the fact — never inside
   * QueryService — which is what keeps QueryService provably DML-free.
   *
   * Logging can never block results: QueryHistoryService.logRun swallows its own failures,
   * and logSafely below guards the call a second time.
   */
  @AuraEnabled
  public static List<SObject> runQuery(
    String soql,
    String naturalLanguage,
    List<String> objectScope
  ) {
    List<SObject> rows;
    try {
      rows = QueryService.runQuery(soql);
    } catch (Exception e) {
      logSafely(
        soql,
        naturalLanguage,
        objectScope,
        0,
        QueryHistoryService.STATUS_ERROR,
        e.getMessage()
      );
      // Rethrow untouched so the LWC's existing error handling is unchanged.
      throw e;
    }
    logSafely(
      soql,
      naturalLanguage,
      objectScope,
      rows == null ? 0 : rows.size(),
      QueryHistoryService.STATUS_SUCCESS,
      null
    );
    return rows;
  }

  /** Defense in depth around the never-throw logging contract. See runQuery. */
  private static void logSafely(
    String soql,
    String naturalLanguage,
    List<String> objectScope,
    Integer rowCount,
    String status,
    String errorMessage
  ) {
    try {
      QueryHistoryService.logRun(
        soql,
        naturalLanguage,
        objectScope,
        rowCount,
        status,
        errorMessage
      );
    } catch (Exception loggingFailure) {
      // Unreachable while logRun honours its contract. Kept so that a future regression
      // in QueryHistoryService can never turn history logging into a blocker for the
      // user's query results.
    }
  }

  // --- Thin passthroughs. No business logic lives in the controller. ---
  // getHistory / getSavedQueries are deliberately NOT cacheable=true: both change within a
  // session (every run, save and delete) and must refresh imperatively.

  @AuraEnabled
  public static List<SOQL_Query_History__c> getHistory(Integer limitSize) {
    return QueryHistoryService.getRecent(limitSize);
  }

  @AuraEnabled
  public static Integer clearHistory() {
    return QueryHistoryService.clearMine();
  }

  @AuraEnabled
  public static SOQL_Saved_Query__c saveQuery(
    String name,
    String soql,
    String naturalLanguage,
    List<String> objectScope
  ) {
    return SavedQueryService.saveQuery(
      name,
      soql,
      naturalLanguage,
      objectScope
    );
  }

  @AuraEnabled
  public static List<SOQL_Saved_Query__c> getSavedQueries() {
    return SavedQueryService.listMine();
  }

  @AuraEnabled
  public static void deleteSavedQuery(Id recordId) {
    SavedQueryService.deleteSavedQuery(recordId);
  }
}
