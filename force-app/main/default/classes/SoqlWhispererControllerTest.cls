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
        List<SchemaService.FieldInfo> fields = SoqlWhispererController.getFields('Account');
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
        List<String> errors = SoqlWhispererController.validateQuery('SELECT Id FROM Account LIMIT 5');
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
        List<String> errors = SoqlWhispererController.validateQuery('DELETE FROM Account');
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
        List<SObject> results = SoqlWhispererController.runQuery('SELECT Id, Name FROM Account');
        Test.stopTest();

        Assert.isFalse(
            results.isEmpty(),
            'runQuery() with a valid read-only SELECT should delegate to QueryService.runQuery() ' +
            'and return the matching Account record(s) in USER_MODE.'
        );
    }

    @isTest
    static void runQueryInvalidQueryThrowsQueryException() {
        QueryService.QueryException caught;

        Test.startTest();
        try {
            SoqlWhispererController.runQuery('DELETE FROM Account');
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
}
