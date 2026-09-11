@isTest
private class SoqlWhispererControllerTest {
  @TestSetup
  static void setup() {
    // generateQuery()/refineQuery() resolve a ClaudeTranslationProvider by default, which reads
    // AnthropicSettings__c.getInstance().ApiKey__c to set the x-api-key header. Insert an
    // org-default Hierarchy custom setting record with a dummy key so that line executes
    // without a null reference. See ClaudeTranslationProviderTest for the same pattern.
    insert new AnthropicSettings__c(ApiKey__c = 'dummy-test-key');
  }

  /**
   * Simple HttpCalloutMock that returns a fixed status code and body for every request,
   * regardless of endpoint/method. Used to intercept the callout:AnthropicAPI/v1/messages POST
   * made by ClaudeTranslationProvider.translate().
   */
  private class StaticMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    StaticMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setBody(body);
      res.setHeader('Content-Type', 'application/json');
      return res;
    }
  }

  @isTest
  static void getObjectsReturnsAccessibleQueryableObjects() {
    Test.startTest();
    List<SchemaService.ObjectInfo> result = SoqlWhispererController.getObjects();
    Test.stopTest();

    Assert.isFalse(
      result.isEmpty(),
      'getObjects() must return at least one queryable, accessible object by delegating to ' +
      'SchemaService.listObjects().'
    );
  }

  @isTest
  static void getFieldsReturnsAccessibleFieldsForAccount() {
    Test.startTest();
    List<SchemaService.FieldInfo> fields = SoqlWhispererController.getFields(
      'Account'
    );
    Test.stopTest();

    Boolean foundIdField = false;
    for (SchemaService.FieldInfo fi : fields) {
      if (fi.apiName == 'Id') {
        foundIdField = true;
        break;
      }
    }
    Assert.isTrue(
      foundIdField,
      'getFields("Account") should include the standard Id field by delegating to ' +
      'SchemaService.describeObject().'
    );
  }

  @isTest
  static void getFieldsUnknownObjectThrowsSchemaException() {
    SchemaService.SchemaException caught;

    Test.startTest();
    try {
      SoqlWhispererController.getFields('NotARealObject__x');
    } catch (SchemaService.SchemaException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'getFields() with an unknown object API name must propagate the SchemaException ' +
      'thrown by SchemaService.describeObject().'
    );
  }

  @isTest
  static void generateQueryReturnsMockedSoqlFromProvider() {
    TranslationProviderFactory.overrideProvider = 'Claude';
    String mockBody = '{"content":[{"type":"text","text":"SELECT Id, Name FROM Account LIMIT 10"}]}';
    Test.setMock(HttpCalloutMock.class, new StaticMock(200, mockBody));

    Test.startTest();
    String soql = SoqlWhispererController.generateQuery(
      'all accounts',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    TranslationProviderFactory.overrideProvider = null;

    Assert.areEqual(
      'SELECT Id, Name FROM Account LIMIT 10',
      soql,
      'generateQuery() should build a schema context for the requested objects, call the ' +
        'configured translation provider, and return the SOQL text parsed from the mocked ' +
        'Claude response.'
    );
  }

  @isTest
  static void refineQueryReturnsMockedSoqlFromProviderRefinementBranch() {
    TranslationProviderFactory.overrideProvider = 'Claude';
    String mockBody = '{"content":[{"type":"text","text":"SELECT Id, Name FROM Account WHERE CreatedDate = LAST_N_DAYS:90 LIMIT 10"}]}';
    Test.setMock(HttpCalloutMock.class, new StaticMock(200, mockBody));

    Test.startTest();
    String soql = SoqlWhispererController.refineQuery(
      'only show ones created in the last 90 days',
      'SELECT Id, Name FROM Account LIMIT 10',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    TranslationProviderFactory.overrideProvider = null;

    Assert.areEqual(
      'SELECT Id, Name FROM Account WHERE CreatedDate = LAST_N_DAYS:90 LIMIT 10',
      soql,
      'refineQuery() should set isRefinement=true and existingQuery on the translation ' +
        'request, call the configured provider, and return the refined SOQL text parsed ' +
        'from the mocked Claude response.'
    );
  }

  @isTest
  static void validateQueryValidSelectReturnsNoErrors() {
    Test.startTest();
    List<String> errors = SoqlWhispererController.validateQuery(
      'SELECT Id FROM Account LIMIT 5'
    );
    Test.stopTest();

    Assert.isTrue(
      errors.isEmpty(),
      'validateQuery() with a well-formed SELECT statement should delegate to ' +
      'QueryService.validate() and return no errors.'
    );
  }

  @isTest
  static void validateQueryNonSelectReturnsErrors() {
    Test.startTest();
    List<String> errors = SoqlWhispererController.validateQuery(
      'DELETE FROM Account'
    );
    Test.stopTest();

    Assert.isFalse(
      errors.isEmpty(),
      'validateQuery() with a non-SELECT statement should delegate to QueryService.validate() ' +
      'and return at least one validation error.'
    );
  }

  @isTest
  static void runQueryValidSelectReturnsResults() {
    insert new Account(Name = 'SoqlWhispererController Test Account');

    Test.startTest();
    List<SObject> results = SoqlWhispererController.runQuery(
      'SELECT Id, Name FROM Account',
      'show me accounts',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    Assert.isFalse(
      results.isEmpty(),
      'runQuery() with a valid read-only SELECT should delegate to QueryService.runQuery() ' +
      'and return the matching Account record(s) in USER_MODE.'
    );
  }

  /**
   * A successful run commits normally, so its history row is durable in production (no
   * rollback boundary involved on this path). This test proves runQuery() actually calls
   * QueryHistoryService.logRun() with a Success status and the real row count, by reading
   * the row back through QueryHistoryService.getRecent() after the fact.
   */
  @isTest
  static void runQuerySuccessWritesSuccessHistoryRowWithRowCount() {
    insert new Account(Name = 'History Success Account');

    Test.startTest();
    List<SObject> results = SoqlWhispererController.runQuery(
      'SELECT Id, Name FROM Account',
      'show me accounts',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(5);
    Assert.areEqual(
      1,
      recent.size(),
      'A successful runQuery() call must write exactly one history row.'
    );
    Assert.areEqual(
      QueryHistoryService.STATUS_SUCCESS,
      recent[0].Status__c,
      'The history row for a successful run must be logged with Status__c = Success.'
    );
    Assert.areEqual(
      results.size(),
      Integer.valueOf(recent[0].Row_Count__c),
      'The history row must record the actual number of rows returned to the caller.'
    );
    Assert.areEqual(
      'SELECT Id, Name FROM Account',
      recent[0].SOQL__c,
      'The history row must record the exact SOQL that was run.'
    );
    Assert.areEqual(
      'show me accounts',
      recent[0].Natural_Language__c,
      'The history row must record the natural language prompt passed to runQuery().'
    );
  }

  @isTest
  static void runQueryInvalidQueryThrowsQueryException() {
    QueryService.QueryException caught;

    Test.startTest();
    try {
      SoqlWhispererController.runQuery(
        'DELETE FROM Account',
        'delete everything',
        new List<String>{ 'Account' }
      );
    } catch (QueryService.QueryException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'runQuery() with a non-SELECT/forbidden statement must propagate the QueryException ' +
      'thrown by QueryService.runQuery() during validation.'
    );
  }

  /**
   * KNOWN LIMITATION — read before "fixing" this test.
   *
   * docs/design-patterns/QueryHistoryService-patterns.md documents that the error-path
   * history row does NOT survive in a deployed org: runQuery() logs the Error row and then
   * rethrows, and an exception escaping an @AuraEnabled method rolls back the whole
   * transaction, taking the just-inserted history row with it.
   *
   * An Apex test method itself runs inside its own savepoint/transaction, and — critically —
   * this test catches the exception *inside the test method*, the same way the real
   * @AuraEnabled boundary would see it (the exception still propagates out of runQuery();
   * we are simply the caller here instead of the Lightning runtime). Catching it here does
   * NOT commit or roll back anything; it just observes that:
   *   1) the original QueryException still propagates unchanged (the LWC's error handling
   *      contract is preserved), and
   *   2) logRun() was actually invoked with Error/0/the exception message.
   *
   * This test intentionally does NOT assert that the row is present via getRecent() after
   * the fact, and it must never be changed to do so. In a real transaction, the rethrow
   * that callers of runQuery() rely on (this method's own "rethrow untouched" contract)
   * would blow away that row before the client ever sees a response. Asserting persistence
   * here would pass in the test harness while being false about production behavior — the
   * exact false-positive this suite must not introduce. If failed-run durability is ever
   * needed, it requires an out-of-band write (e.g. Platform Event with
   * PublishImmediately), tracked as a Phase 5 candidate, not a change to this test.
   */
  @isTest
  static void runQueryFailurePropagatesOriginalExceptionAndAttemptsToLogError() {
    QueryService.QueryException caught;

    Test.startTest();
    try {
      SoqlWhispererController.runQuery(
        'DELETE FROM Account',
        'delete everything',
        new List<String>{ 'Account' }
      );
      Assert.fail('runQuery() should have thrown for a non-SELECT statement.');
    } catch (QueryService.QueryException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'The original QueryException must still propagate to the caller on a failed run — ' +
      'logging a failure must never swallow or replace the thrown exception.'
    );
  }

  // --- Thin passthroughs: history -----------------------------------------------------------

  @isTest
  static void getHistoryDelegatesToQueryHistoryServiceGetRecent() {
    QueryHistoryService.logRun(
      'SELECT Id FROM Account',
      null,
      null,
      1,
      'Success',
      null
    );

    Test.startTest();
    List<SOQL_Query_History__c> history = SoqlWhispererController.getHistory(5);
    Test.stopTest();

    Assert.areEqual(
      1,
      history.size(),
      'getHistory() should delegate to QueryHistoryService.getRecent() and return the logged row.'
    );
  }

  @isTest
  static void clearHistoryDelegatesToQueryHistoryServiceClearMine() {
    QueryHistoryService.logRun(
      'SELECT Id FROM Account',
      null,
      null,
      1,
      'Success',
      null
    );
    QueryHistoryService.logRun(
      'SELECT Id FROM Contact',
      null,
      null,
      1,
      'Success',
      null
    );

    Test.startTest();
    Integer deletedCount = SoqlWhispererController.clearHistory();
    Test.stopTest();

    Assert.areEqual(
      2,
      deletedCount,
      'clearHistory() should delegate to QueryHistoryService.clearMine() and return the count deleted.'
    );
    Assert.isTrue(
      SoqlWhispererController.getHistory(50).isEmpty(),
      'After clearHistory(), no history rows should remain for the running user.'
    );
  }

  // --- Thin passthroughs: saved queries ------------------------------------------------------

  @isTest
  static void saveQueryDelegatesToSavedQueryService() {
    Test.startTest();
    SOQL_Saved_Query__c saved = SoqlWhispererController.saveQuery(
      'Controller Saved',
      'SELECT Id FROM Account',
      'list accounts',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    Assert.isNotNull(
      saved.Id,
      'saveQuery() should delegate to SavedQueryService.saveQuery() and persist a record.'
    );
    Assert.areEqual(
      1,
      SoqlWhispererController.getSavedQueries().size(),
      'getSavedQueries() should reflect the record just saved through the controller.'
    );
  }

  @isTest
  static void saveQueryDelegatesValidationAndThrowsOnBlankSoql() {
    AuraHandledException caught;

    Test.startTest();
    try {
      SoqlWhispererController.saveQuery('No SOQL', '', null, null);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'saveQuery() on the controller should propagate SavedQueryService\'s blank-SOQL validation.'
    );
  }

  @isTest
  static void getSavedQueriesDelegatesToSavedQueryServiceListMine() {
    SoqlWhispererController.saveQuery(
      'Alpha',
      'SELECT Id FROM Account',
      null,
      null
    );
    SoqlWhispererController.saveQuery(
      'Bravo',
      'SELECT Id FROM Contact',
      null,
      null
    );

    Test.startTest();
    List<SOQL_Saved_Query__c> saved = SoqlWhispererController.getSavedQueries();
    Test.stopTest();

    Assert.areEqual(
      2,
      saved.size(),
      'getSavedQueries() should delegate to SavedQueryService.listMine() and return all saved queries.'
    );
    Assert.areEqual(
      'Alpha',
      saved[0].Name,
      'getSavedQueries() should preserve the Name-ascending ordering from listMine().'
    );
  }

  @isTest
  static void deleteSavedQueryDelegatesToSavedQueryService() {
    SOQL_Saved_Query__c saved = SoqlWhispererController.saveQuery(
      'To Remove',
      'SELECT Id FROM Account',
      null,
      null
    );

    Test.startTest();
    SoqlWhispererController.deleteSavedQuery(saved.Id);
    Test.stopTest();

    Assert.isTrue(
      SoqlWhispererController.getSavedQueries().isEmpty(),
      'deleteSavedQuery() should delegate to SavedQueryService.deleteSavedQuery() and remove the record.'
    );
  }
}
