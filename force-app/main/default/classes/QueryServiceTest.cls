@isTest
private class QueryServiceTest {

    @isTest
    static void validRejectsNonSelect() {
        List<String> errs = QueryService.validate('UPDATE Account SET Name = X');
        System.assert(!errs.isEmpty(), 'DML-style input should be rejected');
    }

    @isTest
    static void validRejectsDmlKeyword() {
        List<String> errs = QueryService.validate('SELECT Id FROM Account; delete something');
        System.assert(!errs.isEmpty(), 'Embedded DML keyword should be rejected');
    }

    @isTest
    static void validAcceptsSelect() {
        List<String> errs = QueryService.validate('SELECT Id, Name FROM Account LIMIT 5');
        System.assertEquals(0, errs.size(), 'Clean SELECT should pass');
    }

    @isTest
    static void runQueryReturnsRows() {
        insert new Account(Name = 'Test Co');
        Test.startTest();
        List<SObject> rows = QueryService.runQuery('SELECT Id, Name FROM Account LIMIT 10');
        Test.stopTest();
        System.assert(!rows.isEmpty(), 'Should return the inserted account');
    }

    @isTest
    static void runQueryBlocksWrite() {
        try {
            QueryService.runQuery('UPDATE Account SET Name = 1');
            System.assert(false, 'Should have thrown');
        } catch (QueryService.QueryException e) {
            System.assert(true);
        }
    }
}
