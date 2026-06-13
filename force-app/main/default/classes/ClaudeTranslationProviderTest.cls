@isTest
private class ClaudeTranslationProviderTest {

    @TestSetup
    static void setup() {
        // ClaudeTranslationProvider.translate() reads AnthropicSettings__c.getInstance().ApiKey__c
        // to set the x-api-key header. Insert an org-default Hierarchy custom setting record
        // with a dummy key so that line executes without a null reference.
        insert new AnthropicSettings__c(ApiKey__c = 'dummy-test-key');
    }

    /**
     * Simple HttpCalloutMock that returns a fixed status code and body for every request,
     * regardless of endpoint/method. Used to intercept the callout:AnthropicAPI/v1/messages POST.
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
    static void translateReturns200SuccessTrimmedSoql() {
        String mockBody = '{"content":[{"type":"text","text":"  SELECT Id FROM Account LIMIT 10  "}]}';
        Test.setMock(HttpCalloutMock.class, new StaticMock(200, mockBody));

        TranslationRequest req = new TranslationRequest(
            'all accounts',
            'Account(Id, Name)'
        );

        Test.startTest();
        String result = new ClaudeTranslationProvider().translate(req);
        Test.stopTest();

        Assert.areEqual(
            'SELECT Id FROM Account LIMIT 10',
            result,
            'translate() must return the SOQL text from the Claude response trimmed of ' +
            'leading/trailing whitespace.'
        );
    }

    @isTest
    static void translateRefinementBranchReturnsMockedSoql() {
        String mockBody = '{"content":[{"type":"text","text":"SELECT Id, Name FROM Account WHERE CreatedDate = LAST_N_DAYS:90 LIMIT 10"}]}';
        Test.setMock(HttpCalloutMock.class, new StaticMock(200, mockBody));

        TranslationRequest req = new TranslationRequest(
            'only show ones created in the last 90 days',
            'Account(Id, Name, CreatedDate)'
        );
        req.isRefinement = true;
        req.existingQuery = 'SELECT Id, Name FROM Account LIMIT 10';

        Test.startTest();
        String result = new ClaudeTranslationProvider().translate(req);
        Test.stopTest();

        Assert.areEqual(
            'SELECT Id, Name FROM Account WHERE CreatedDate = LAST_N_DAYS:90 LIMIT 10',
            result,
            'translate() with isRefinement=true and an existingQuery set must exercise the ' +
            'refinement branch of buildUserPrompt() and still return the SOQL parsed from the ' +
            'Claude response.'
        );
    }

    @isTest
    static void translateNon200ResponseThrowsTranslationException() {
        Test.setMock(HttpCalloutMock.class, new StaticMock(500, 'Internal Server Error'));

        TranslationRequest req = new TranslationRequest(
            'all accounts',
            'Account(Id, Name)'
        );

        ClaudeTranslationProvider.TranslationException caught;

        Test.startTest();
        try {
            new ClaudeTranslationProvider().translate(req);
        } catch (ClaudeTranslationProvider.TranslationException e) {
            caught = e;
        }
        Test.stopTest();

        Assert.isNotNull(
            caught,
            'A non-200 response from the Claude API must cause translate() to throw a ' +
            'ClaudeTranslationProvider.TranslationException.'
        );
        Assert.isTrue(
            caught.getMessage().contains('500'),
            'The TranslationException message should include the non-200 status code returned ' +
            'by the mocked HTTP response. Actual message: ' + caught.getMessage()
        );
    }

    @isTest
    static void translateNoTextContentBlockThrowsTranslationException() {
        String mockBody = '{"content":[{"type":"image","source":{"type":"base64","data":"abc123"}}]}';
        Test.setMock(HttpCalloutMock.class, new StaticMock(200, mockBody));

        TranslationRequest req = new TranslationRequest(
            'all accounts',
            'Account(Id, Name)'
        );

        ClaudeTranslationProvider.TranslationException caught;

        Test.startTest();
        try {
            new ClaudeTranslationProvider().translate(req);
        } catch (ClaudeTranslationProvider.TranslationException e) {
            caught = e;
        }
        Test.stopTest();

        Assert.isNotNull(
            caught,
            'A 200 response whose content array contains no block with type "text" must cause ' +
            'extractSoql() to throw a ClaudeTranslationProvider.TranslationException.'
        );
        Assert.isTrue(
            caught.getMessage().contains('No text content'),
            'The TranslationException message should indicate that no text content was found ' +
            'in the Claude response. Actual message: ' + caught.getMessage()
        );
    }
}
