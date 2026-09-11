@isTest
private class SavedQueryServiceTest {
  // --- Test user factory for the isolation test ---------------------------------------
  // Mirrors the pattern in QueryHistoryServiceTest: two users, both assigned
  // SOQL_Whisperer_User, to prove the OWD Private + with-sharing + USER_MODE isolation
  // model (D2 in design-requirements.md) for saved queries.
  @TestSetup
  static void setup() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User userA = buildTestUser(standardProfile.Id, 'sqsvcA');
    User userB = buildTestUser(standardProfile.Id, 'sqsvcB');
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
      Email = uniqueName + '@example.com.sqtest',
      Username = uniqueName +
        System.currentTimeMillis() +
        '@example.com.sqtest',
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

  // --- saveQuery: validation --------------------------------------------------------------

  @isTest
  static void saveQueryBlankNameThrowsAuraHandledException() {
    AuraHandledException caught;
    Test.startTest();
    try {
      SavedQueryService.saveQuery('', 'SELECT Id FROM Account', null, null);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'A blank name must be rejected with an AuraHandledException.'
    );
    Assert.areEqual(
      'Give the saved query a name before saving it.',
      caught.getMessage(),
      'The exception message should explain that a name is required.'
    );
  }

  @isTest
  static void saveQueryNullNameThrowsAuraHandledException() {
    AuraHandledException caught;
    Test.startTest();
    try {
      SavedQueryService.saveQuery(null, 'SELECT Id FROM Account', null, null);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'A null name must be rejected with an AuraHandledException.'
    );
  }

  @isTest
  static void saveQueryBlankSoqlThrowsAuraHandledException() {
    AuraHandledException caught;
    Test.startTest();
    try {
      SavedQueryService.saveQuery('My Query', '', null, null);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'Blank SOQL must be rejected with an AuraHandledException.'
    );
    Assert.areEqual(
      'There is no SOQL to save. Generate or type a query first.',
      caught.getMessage(),
      'The exception message should explain that there is no SOQL to save.'
    );
  }

  // --- saveQuery: create / overwrite -------------------------------------------------------

  @isTest
  static void saveQueryCreatesNewRecordWhenNoneExists() {
    Test.startTest();
    SOQL_Saved_Query__c saved = SavedQueryService.saveQuery(
      'My Accounts',
      'SELECT Id FROM Account',
      'list accounts',
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    Assert.isNotNull(
      saved.Id,
      'saveQuery() should insert and return a persisted record.'
    );
    List<SOQL_Saved_Query__c> mine = SavedQueryService.listMine();
    Assert.areEqual(
      1,
      mine.size(),
      'A single saveQuery() call should result in one saved query.'
    );
    Assert.areEqual(
      'My Accounts',
      mine[0].Name,
      'The saved record should have the supplied name.'
    );
    Assert.areEqual(
      'SELECT Id FROM Account',
      mine[0].SOQL__c,
      'The saved record should have the supplied SOQL.'
    );
    Assert.areEqual(
      'Account',
      mine[0].Object_Scope__c,
      'The saved record should have the joined object scope.'
    );
  }

  @isTest
  static void saveQueryOverwritesExistingRecordWithSameName() {
    SOQL_Saved_Query__c first = SavedQueryService.saveQuery(
      'My Accounts',
      'SELECT Id FROM Account',
      'first version',
      new List<String>{ 'Account' }
    );

    Test.startTest();
    SOQL_Saved_Query__c second = SavedQueryService.saveQuery(
      'My Accounts',
      'SELECT Id, Name FROM Account WHERE Name != null',
      'second version',
      new List<String>{ 'Account', 'Contact' }
    );
    Test.stopTest();

    List<SOQL_Saved_Query__c> mine = SavedQueryService.listMine();
    Assert.areEqual(
      1,
      mine.size(),
      'Saving under the same name a second time must overwrite, not duplicate: the record ' +
      'count must stay at 1.'
    );
    Assert.areEqual(
      first.Id,
      second.Id,
      'The overwrite must update the existing record (same Id), not insert a new one.'
    );
    Assert.areEqual(
      'SELECT Id, Name FROM Account WHERE Name != null',
      mine[0].SOQL__c,
      'The SOQL on the existing record should be updated to the newly saved value.'
    );
    Assert.areEqual(
      'second version',
      mine[0].Natural_Language__c,
      'The natural language prompt on the existing record should be updated.'
    );
    Assert.areEqual(
      'Account,Contact',
      mine[0].Object_Scope__c,
      'The object scope on the existing record should be updated.'
    );
  }

  @isTest
  static void saveQueryDifferentNameCreatesSeparateRecord() {
    SavedQueryService.saveQuery(
      'Query One',
      'SELECT Id FROM Account',
      null,
      null
    );

    Test.startTest();
    SavedQueryService.saveQuery(
      'Query Two',
      'SELECT Id FROM Contact',
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      SavedQueryService.listMine().size(),
      'Saving under a different name must create a separate record rather than overwriting.'
    );
  }

  @isTest
  static void saveQueryTruncatesOverLengthValues() {
    String longName = 'n'.repeat(120);
    String longSoql =
      'SELECT Id FROM Account WHERE Name = \'' +
      's'.repeat(5000) +
      '\'';
    String longNl = 'l'.repeat(1500);
    List<String> longScope = new List<String>{
      'o'.repeat(600),
      'o'.repeat(600)
    };

    Test.startTest();
    SavedQueryService.saveQuery(longName, longSoql, longNl, longScope);
    Test.stopTest();

    List<SOQL_Saved_Query__c> mine = SavedQueryService.listMine();
    Assert.areEqual(
      1,
      mine.size(),
      'An over-length save should still succeed after truncation.'
    );
    Assert.areEqual(
      80,
      mine[0].Name.length(),
      'Name should be truncated to the standard 80-character text field length.'
    );
    Assert.areEqual(
      5000,
      mine[0].SOQL__c.length(),
      'SOQL__c should be truncated to the field length (5000).'
    );
    Assert.areEqual(
      1000,
      mine[0].Natural_Language__c.length(),
      'Natural_Language__c should be truncated to the field length (1000).'
    );
    Assert.areEqual(
      1000,
      mine[0].Object_Scope__c.length(),
      'Object_Scope__c should be truncated to the field length (1000).'
    );
  }

  // --- listMine: ordering -------------------------------------------------------------------

  @isTest
  static void listMineOrdersByNameAscending() {
    SavedQueryService.saveQuery(
      'Charlie',
      'SELECT Id FROM Account',
      null,
      null
    );
    SavedQueryService.saveQuery('Alpha', 'SELECT Id FROM Account', null, null);
    SavedQueryService.saveQuery('Bravo', 'SELECT Id FROM Account', null, null);

    Test.startTest();
    List<SOQL_Saved_Query__c> mine = SavedQueryService.listMine();
    Test.stopTest();

    Assert.areEqual(
      3,
      mine.size(),
      'All three saved queries should be returned.'
    );
    Assert.areEqual(
      'Alpha',
      mine[0].Name,
      'listMine() should order alphabetically ascending by Name.'
    );
    Assert.areEqual(
      'Bravo',
      mine[1].Name,
      'listMine() should order alphabetically ascending by Name.'
    );
    Assert.areEqual(
      'Charlie',
      mine[2].Name,
      'listMine() should order alphabetically ascending by Name.'
    );
  }

  @isTest
  static void listMineReturnsEmptyWhenNoneSaved() {
    Test.startTest();
    List<SOQL_Saved_Query__c> mine = SavedQueryService.listMine();
    Test.stopTest();

    Assert.isTrue(
      mine.isEmpty(),
      'listMine() should return an empty list when nothing is saved.'
    );
  }

  // --- deleteSavedQuery -----------------------------------------------------------------------

  @isTest
  static void deleteSavedQueryRemovesRecord() {
    SOQL_Saved_Query__c saved = SavedQueryService.saveQuery(
      'To Delete',
      'SELECT Id FROM Account',
      null,
      null
    );

    Test.startTest();
    SavedQueryService.deleteSavedQuery(saved.Id);
    Test.stopTest();

    Assert.isTrue(
      SavedQueryService.listMine().isEmpty(),
      'deleteSavedQuery() should remove the record from listMine() results.'
    );
  }

  @isTest
  static void deleteSavedQueryNullIdThrowsAuraHandledException() {
    AuraHandledException caught;
    Test.startTest();
    try {
      SavedQueryService.deleteSavedQuery(null);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'A null recordId must be rejected with an AuraHandledException.'
    );
    Assert.areEqual(
      'Select a saved query to delete.',
      caught.getMessage(),
      'The exception message should prompt the user to select a record.'
    );
  }

  @isTest
  static void deleteSavedQueryAlreadyDeletedIdThrowsAuraHandledException() {
    SOQL_Saved_Query__c saved = SavedQueryService.saveQuery(
      'Gone Soon',
      'SELECT Id FROM Account',
      null,
      null
    );
    Id vanishedId = saved.Id;
    SavedQueryService.deleteSavedQuery(vanishedId);

    AuraHandledException caught;
    Test.startTest();
    try {
      // Second delete of the same, now-nonexistent Id must be rejected cleanly rather than
      // throwing an unhandled DmlException or NPE.
      SavedQueryService.deleteSavedQuery(vanishedId);
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'Deleting a record that no longer exists (or is not visible) must throw a clear ' +
      'AuraHandledException rather than an unhandled DML error.'
    );
    Assert.areEqual(
      'That saved query no longer exists, or you do not have access to it.',
      caught.getMessage(),
      'The exception message should explain the record is gone or inaccessible.'
    );
  }

  // --- private helper unit tests (@TestVisible) ------------------------------------------

  @isTest
  static void joinScopeNullOrEmptyReturnsNull() {
    Assert.isNull(
      SavedQueryService.joinScope(null),
      'A null object scope list should join to null.'
    );
    Assert.isNull(
      SavedQueryService.joinScope(new List<String>()),
      'An empty object scope list should join to null.'
    );
  }

  @isTest
  static void joinScopeFiltersBlankEntriesAndTrimsThenJoinsWithComma() {
    List<String> scope = new List<String>{ '  Account ', '', null, 'Contact' };
    Assert.areEqual(
      'Account,Contact',
      SavedQueryService.joinScope(scope),
      'joinScope() should trim entries, drop blank/null entries, and comma-join the rest.'
    );
  }

  @isTest
  static void truncateBlankReturnsNull() {
    Assert.isNull(
      SavedQueryService.truncate(null, 10),
      'truncate() of null should return null.'
    );
    Assert.isNull(
      SavedQueryService.truncate('', 10),
      'truncate() of an empty string should return null.'
    );
  }

  @isTest
  static void truncateOverLimitTruncatesToMaxLength() {
    Assert.areEqual(
      'hell',
      SavedQueryService.truncate('hello', 4),
      'A value over the max length should be truncated to exactly the max length.'
    );
  }

  // --- User isolation (proves OWD Private + with sharing + USER_MODE, D2) ------------------

  @isTest
  static void userIsolationSavedQueriesAreNotVisibleOrDeletableAcrossUsers() {
    User userA = queryTestUser('sqsvcA');
    User userB = queryTestUser('sqsvcB');
    Id userASavedQueryId;

    System.runAs(userA) {
      SOQL_Saved_Query__c saved = SavedQueryService.saveQuery(
        'UserA Only',
        'SELECT Id FROM Account',
        null,
        null
      );
      userASavedQueryId = saved.Id;
    }

    System.runAs(userB) {
      List<SOQL_Saved_Query__c> userBView = SavedQueryService.listMine();
      Assert.isTrue(
        userBView.isEmpty(),
        'User B must not see User A\'s saved query: SOQL_Saved_Query__c is OWD Private with ' +
        'no sharing rules, and listMine() relies entirely on that sharing model.'
      );

      AuraHandledException caught;
      try {
        SavedQueryService.deleteSavedQuery(userASavedQueryId);
        Assert.fail(
          'User B must not be able to delete User A\'s saved query, but no exception was thrown.'
        );
      } catch (AuraHandledException e) {
        caught = e;
      }
      Assert.isNotNull(
        caught,
        'Attempting to delete another user\'s saved query should fail as if the record does ' +
        'not exist, because the USER_MODE SELECT inside deleteSavedQuery() finds nothing.'
      );
    }

    System.runAs(userA) {
      List<SOQL_Saved_Query__c> userAView = SavedQueryService.listMine();
      Assert.areEqual(
        1,
        userAView.size(),
        'User A\'s saved query must survive User B\'s failed delete attempt untouched.'
      );
    }
  }

  @isTest
  static void userIsolationSameNameByDifferentOwnersCreatesSeparateRecords() {
    User userA = queryTestUser('sqsvcA');
    User userB = queryTestUser('sqsvcB');

    System.runAs(userA) {
      SavedQueryService.saveQuery(
        'Shared Name',
        'SELECT Id FROM Account',
        null,
        null
      );
    }
    System.runAs(userB) {
      SavedQueryService.saveQuery(
        'Shared Name',
        'SELECT Id FROM Contact',
        null,
        null
      );
    }

    System.runAs(userA) {
      List<SOQL_Saved_Query__c> userAView = SavedQueryService.listMine();
      Assert.areEqual(
        1,
        userAView.size(),
        'User A should still see exactly one saved query under "Shared Name".'
      );
      Assert.areEqual(
        'SELECT Id FROM Account',
        userAView[0].SOQL__c,
        'User B saving under the same name must NOT overwrite User A\'s record: the ' +
        'overwrite match is scoped to Name + OwnerId, not Name alone.'
      );
    }
    System.runAs(userB) {
      List<SOQL_Saved_Query__c> userBView = SavedQueryService.listMine();
      Assert.areEqual(
        1,
        userBView.size(),
        'User B should see exactly one saved query of their own.'
      );
      Assert.areEqual(
        'SELECT Id FROM Contact',
        userBView[0].SOQL__c,
        'User B\'s own record under the same name should hold User B\'s SOQL.'
      );
    }
  }
}
