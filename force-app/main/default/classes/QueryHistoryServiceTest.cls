@isTest
private class QueryHistoryServiceTest {
  // --- Test user factory for the isolation test ---------------------------------------
  // Two distinct users, both assigned SOQL_Whisperer_User, so System.runAs can prove the
  // OWD Private + with-sharing + USER_MODE isolation model (D2 in design-requirements.md).
  // User/PermissionSetAssignment are the only objects touched here, so no non-setup-object
  // DML is mixed into this transaction and no System.runAs wrapper is required around the
  // insert itself.
  @TestSetup
  static void setup() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User userA = buildTestUser(standardProfile.Id, 'qhsvcA');
    User userB = buildTestUser(standardProfile.Id, 'qhsvcB');
    insert new List<User>{ userA, userB };

    PermissionSet whispererPermSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SOQL_Whisperer_User'
      LIMIT 1
    ];
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = userA.Id,
        PermissionSetId = whispererPermSet.Id
      ),
      new PermissionSetAssignment(
        AssigneeId = userB.Id,
        PermissionSetId = whispererPermSet.Id
      )
    };
  }

  private static User buildTestUser(Id profileId, String uniqueName) {
    return new User(
      ProfileId = profileId,
      LastName = 'Test',
      FirstName = uniqueName,
      Email = uniqueName + '@example.com.qhtest',
      Username = uniqueName +
        System.currentTimeMillis() +
        '@example.com.qhtest',
      Alias = uniqueName.left(8),
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  private static User queryTestUser(String uniqueName) {
    return [
      SELECT Id
      FROM User
      WHERE FirstName = :uniqueName
      LIMIT 1
    ];
  }

  // --- logRun: success / error / swallow ------------------------------------------------

  @isTest
  static void logRunSuccessInsertsRecordWithExpectedFields() {
    Test.startTest();
    QueryHistoryService.logRun(
      'SELECT Id FROM Account',
      'show me accounts',
      new List<String>{ 'Account', 'Contact' },
      3,
      QueryHistoryService.STATUS_SUCCESS,
      null
    );
    Test.stopTest();

    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(5);
    Assert.areEqual(
      1,
      recent.size(),
      'logRun() with valid Success inputs should insert exactly one history record.'
    );
    SOQL_Query_History__c entry = recent[0];
    Assert.areEqual(
      'SELECT Id FROM Account',
      entry.SOQL__c,
      'The inserted record should store the exact SOQL text passed to logRun().'
    );
    Assert.areEqual(
      'show me accounts',
      entry.Natural_Language__c,
      'The inserted record should store the natural language prompt passed to logRun().'
    );
    Assert.areEqual(
      'Account,Contact',
      entry.Object_Scope__c,
      'Object scope should be comma-joined in the order supplied.'
    );
    Assert.areEqual(
      3,
      Integer.valueOf(entry.Row_Count__c),
      'Row_Count__c should reflect the rowCount argument.'
    );
    Assert.areEqual(
      QueryHistoryService.STATUS_SUCCESS,
      entry.Status__c,
      'Status__c should be exactly "Success" for a successful run.'
    );
    Assert.isNull(
      entry.Error_Message__c,
      'A successful run should not populate Error_Message__c.'
    );
  }

  @isTest
  static void logRunErrorInsertsRecordWithErrorMessage() {
    Test.startTest();
    QueryHistoryService.logRun(
      'SELECT Id FROM Contact',
      'bad query',
      new List<String>{ 'Contact' },
      0,
      QueryHistoryService.STATUS_ERROR,
      'Query failed: some reason'
    );
    Test.stopTest();

    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(5);
    Assert.areEqual(
      1,
      recent.size(),
      'logRun() with Error status should still insert a history record.'
    );
    Assert.areEqual(
      QueryHistoryService.STATUS_ERROR,
      recent[0].Status__c,
      'Status__c should be exactly "Error" for a failed run.'
    );
    Assert.areEqual(
      'Query failed: some reason',
      recent[0].Error_Message__c,
      'Error_Message__c should store the exception message passed to logRun().'
    );
    Assert.areEqual(
      0,
      Integer.valueOf(recent[0].Row_Count__c),
      'A failed run should log a row count of 0.'
    );
  }

  /**
   * SWALLOW CONTRACT: SOQL__c is a required field on SOQL_Query_History__c. Passing a blank
   * soql means truncate() returns null, so the insert fails DML validation ("required field
   * missing") for a completely realistic reason (no permission trickery needed). logRun()
   * must swallow that failure silently: the call below must return normally (an uncaught
   * exception here would fail this test method), and no history row must have been written.
   *
   * NOTE: this test calls logRun() directly and lets it swallow its own failure — it says
   * nothing about the separate transaction-rollback issue in
   * SoqlWhispererController.runQuery's error path (see the "known limitation" note in
   * SoqlWhispererControllerTest and docs/design-patterns/QueryHistoryService-patterns.md).
   * That is a different failure mode (successful insert, then rolled back by a rethrown
   * exception) from this one (insert itself never succeeds).
   */
  @isTest
  static void logRunSwallowsInsertFailureAndDoesNotThrow() {
    Integer countBefore = QueryHistoryService.getRecent(200).size();

    Test.startTest();
    // Blank soql -> truncate() returns null -> required-field DML failure inside logRun(),
    // caught and swallowed. No try/catch here: a rethrow would fail this test.
    QueryHistoryService.logRun(
      null,
      'irrelevant',
      new List<String>{ 'Account' },
      0,
      QueryHistoryService.STATUS_ERROR,
      'boom'
    );
    Test.stopTest();

    Integer countAfter = QueryHistoryService.getRecent(200).size();
    Assert.areEqual(
      countBefore,
      countAfter,
      'logRun() must swallow a DML failure (missing required SOQL__c) without inserting a ' +
      'row and without throwing to the caller.'
    );
  }

  @isTest
  static void logRunTruncatesOverLengthValuesBeforeInsert() {
    String longSoql =
      'SELECT Id FROM Account WHERE Name = \'' +
      'x'.repeat(5000) +
      '\'';
    String longNl = 'y'.repeat(1500);
    String longError = 'z'.repeat(400);
    List<String> longScope = new List<String>{
      'w'.repeat(600),
      'w'.repeat(600)
    };

    Test.startTest();
    QueryHistoryService.logRun(
      longSoql,
      longNl,
      longScope,
      1,
      QueryHistoryService.STATUS_ERROR,
      longError
    );
    Test.stopTest();

    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(1);
    Assert.areEqual(
      1,
      recent.size(),
      'An over-length input should be truncated and still insert successfully.'
    );
    SOQL_Query_History__c entry = recent[0];
    Assert.areEqual(
      5000,
      entry.SOQL__c.length(),
      'SOQL__c should be truncated to the field length (5000) rather than failing the insert.'
    );
    Assert.areEqual(
      1000,
      entry.Natural_Language__c.length(),
      'Natural_Language__c should be truncated to the field length (1000).'
    );
    Assert.areEqual(
      1000,
      entry.Object_Scope__c.length(),
      'Object_Scope__c should be truncated to the field length (1000) even though the joined ' +
      'scope string was longer.'
    );
    Assert.areEqual(
      255,
      entry.Error_Message__c.length(),
      'Error_Message__c should be truncated to the field length (255).'
    );
  }

  @isTest
  static void logRunNormalizesUnrecognizedStatusToNullOnInsert() {
    Test.startTest();
    QueryHistoryService.logRun(
      'SELECT Id FROM Account',
      null,
      null,
      1,
      'Pending',
      null
    );
    Test.stopTest();

    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(1);
    Assert.areEqual(
      1,
      recent.size(),
      'logRun() should still insert with an unrecognized status.'
    );
    Assert.isNull(
      recent[0].Status__c,
      'A status value that is neither Success nor Error should be stored as null rather than ' +
      'failing the restricted-picklist insert.'
    );
  }

  // --- getRecent: ordering + limit clamping ----------------------------------------------

  @isTest
  static void getRecentOrdersNewestFirst() {
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 1',
      null,
      null,
      1,
      'Success',
      null
    );
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 2',
      null,
      null,
      1,
      'Success',
      null
    );
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 3',
      null,
      null,
      1,
      'Success',
      null
    );

    Test.startTest();
    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(10);
    Test.stopTest();

    Assert.areEqual(
      3,
      recent.size(),
      'All three logged runs should be visible to the running user.'
    );
    Assert.areEqual(
      'SELECT Id FROM Account LIMIT 3',
      recent[0].SOQL__c,
      'getRecent() orders CreatedDate DESC (tie-broken by Name DESC), so the most recently ' +
      'logged run must be first.'
    );
    Assert.areEqual(
      'SELECT Id FROM Account LIMIT 1',
      recent[2].SOQL__c,
      'The first-logged run should be last in a newest-first ordering.'
    );
  }

  @isTest
  static void clampLimitNullDefaultsTo25() {
    Assert.areEqual(
      25,
      QueryHistoryService.clampLimit(null),
      'A null limitSize should default to 25.'
    );
  }

  @isTest
  static void clampLimitZeroOrNegativeClampsToFloorOf1() {
    Assert.areEqual(
      1,
      QueryHistoryService.clampLimit(0),
      'Requesting 0 should clamp to the floor of 1.'
    );
    Assert.areEqual(
      1,
      QueryHistoryService.clampLimit(-100),
      'Requesting a negative limit should clamp to the floor of 1.'
    );
  }

  @isTest
  static void clampLimitAboveMaxClampsToCeilingOf200() {
    Assert.areEqual(
      200,
      QueryHistoryService.clampLimit(500),
      'Requesting 500 should clamp to the ceiling of 200.'
    );
    Assert.areEqual(
      200,
      QueryHistoryService.clampLimit(5000),
      'Requesting 5000 should clamp to the ceiling of 200.'
    );
  }

  @isTest
  static void clampLimitWithinRangeIsUnchanged() {
    Assert.areEqual(
      75,
      QueryHistoryService.clampLimit(75),
      'A limitSize already within [1, 200] should pass through unchanged.'
    );
  }

  /**
   * Proves the server-side clamp actually caps the query, not just the arithmetic helper:
   * with 205 rows present, requesting an unbounded-feeling limit still returns at most 200.
   */
  @isTest
  static void getRecentNeverReturnsMoreThan200RowsRegardlessOfRequestedLimit() {
    List<SOQL_Query_History__c> manyRecords = new List<SOQL_Query_History__c>();
    for (Integer i = 0; i < 205; i++) {
      manyRecords.add(
        new SOQL_Query_History__c(
          SOQL__c = 'SELECT Id FROM Account LIMIT ' + i,
          Status__c = QueryHistoryService.STATUS_SUCCESS,
          Row_Count__c = 0
        )
      );
    }
    insert manyRecords;

    Test.startTest();
    List<SOQL_Query_History__c> recent = QueryHistoryService.getRecent(9999);
    Test.stopTest();

    Assert.areEqual(
      200,
      recent.size(),
      'Even with more than 200 rows present and an oversized requested limit, getRecent() ' +
      'must never return more than the server-side ceiling of 200.'
    );
  }

  // --- clearMine ---------------------------------------------------------------------------

  @isTest
  static void clearMineDeletesAllOwnRecordsAndReturnsCount() {
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 1',
      null,
      null,
      1,
      'Success',
      null
    );
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 2',
      null,
      null,
      1,
      'Success',
      null
    );
    QueryHistoryService.logRun(
      'SELECT Id FROM Account LIMIT 3',
      null,
      null,
      1,
      'Success',
      null
    );

    Test.startTest();
    Integer deletedCount = QueryHistoryService.clearMine();
    Test.stopTest();

    Assert.areEqual(
      3,
      deletedCount,
      'clearMine() should return the number of records it deleted.'
    );
    Assert.isTrue(
      QueryHistoryService.getRecent(200).isEmpty(),
      'After clearMine(), the running user should have no remaining history.'
    );
  }

  @isTest
  static void clearMineReturnsZeroWhenNoHistoryExists() {
    Test.startTest();
    Integer deletedCount = QueryHistoryService.clearMine();
    Test.stopTest();

    Assert.areEqual(
      0,
      deletedCount,
      'clearMine() with no existing history should delete nothing and return 0.'
    );
  }

  // --- private helper unit tests (@TestVisible) --------------------------------------------

  @isTest
  static void normalizeStatusBlankReturnsNull() {
    Assert.isNull(
      QueryHistoryService.normalizeStatus(null),
      'Null status should normalize to null.'
    );
    Assert.isNull(
      QueryHistoryService.normalizeStatus(''),
      'Blank status should normalize to null.'
    );
  }

  @isTest
  static void normalizeStatusIsCaseInsensitiveAndTrims() {
    Assert.areEqual(
      QueryHistoryService.STATUS_SUCCESS,
      QueryHistoryService.normalizeStatus(' success '),
      'normalizeStatus() should recognize "success" case-insensitively and trim whitespace.'
    );
    Assert.areEqual(
      QueryHistoryService.STATUS_ERROR,
      QueryHistoryService.normalizeStatus('ERROR'),
      'normalizeStatus() should recognize "ERROR" case-insensitively.'
    );
  }

  @isTest
  static void normalizeStatusUnknownValueReturnsNull() {
    Assert.isNull(
      QueryHistoryService.normalizeStatus('Pending'),
      'An unrecognized status value should normalize to null rather than an invalid picklist value.'
    );
  }

  @isTest
  static void joinScopeNullOrEmptyReturnsNull() {
    Assert.isNull(
      QueryHistoryService.joinScope(null),
      'A null object scope list should join to null.'
    );
    Assert.isNull(
      QueryHistoryService.joinScope(new List<String>()),
      'An empty object scope list should join to null.'
    );
  }

  @isTest
  static void joinScopeFiltersBlankEntriesAndTrimsThenJoinsWithComma() {
    List<String> scope = new List<String>{ '  Account ', '', null, 'Contact' };
    Assert.areEqual(
      'Account,Contact',
      QueryHistoryService.joinScope(scope),
      'joinScope() should trim entries, drop blank/null entries, and comma-join the rest.'
    );
  }

  @isTest
  static void truncateBlankReturnsNull() {
    Assert.isNull(
      QueryHistoryService.truncate(null, 10),
      'truncate() of null should return null.'
    );
    Assert.isNull(
      QueryHistoryService.truncate('', 10),
      'truncate() of an empty string should return null.'
    );
  }

  @isTest
  static void truncateUnderOrAtLimitReturnsUnchanged() {
    Assert.areEqual(
      'hello',
      QueryHistoryService.truncate('hello', 10),
      'A value under the max length should be returned unchanged.'
    );
    Assert.areEqual(
      'hello',
      QueryHistoryService.truncate('hello', 5),
      'A value exactly at the max length should be returned unchanged (boundary case).'
    );
  }

  @isTest
  static void truncateOverLimitTruncatesToMaxLength() {
    Assert.areEqual(
      'hell',
      QueryHistoryService.truncate('hello', 4),
      'A value over the max length should be truncated to exactly the max length.'
    );
  }

  // --- User isolation (proves OWD Private + with sharing + USER_MODE, D2) ------------------

  @isTest
  static void userIsolationHistoryIsNotVisibleOrDeletableAcrossUsers() {
    User userA = queryTestUser('qhsvcA');
    User userB = queryTestUser('qhsvcB');

    System.runAs(userA) {
      QueryHistoryService.logRun(
        'SELECT Id FROM Account WHERE Name = \'UserA-only\'',
        'user A query',
        new List<String>{ 'Account' },
        1,
        QueryHistoryService.STATUS_SUCCESS,
        null
      );
    }

    System.runAs(userB) {
      List<SOQL_Query_History__c> userBView = QueryHistoryService.getRecent(50);
      Assert.isTrue(
        userBView.isEmpty(),
        'User B must not see User A\'s history: SOQL_Query_History__c is OWD Private with no ' +
          'sharing rules, and getRecent() relies entirely on that sharing model (no manual ' +
          'OwnerId filter).'
      );

      Integer userBDeletedCount = QueryHistoryService.clearMine();
      Assert.areEqual(
        0,
        userBDeletedCount,
        'User B calling clearMine() must delete 0 records: User B owns none, and the OwnerId ' +
          'filter in clearMine() prevents it from ever reaching User A\'s row even if sharing ' +
          'were ever misconfigured.'
      );
    }

    System.runAs(userA) {
      List<SOQL_Query_History__c> userAView = QueryHistoryService.getRecent(50);
      Assert.areEqual(
        1,
        userAView.size(),
        'User A\'s history record must survive User B\'s clearMine() call untouched, proving ' +
        'isolation holds for both reads and deletes.'
      );
    }
  }
}
