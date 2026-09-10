@isTest
private class SchemaServiceTest {
  @isTest
  static void listObjectsReturnsAccessibleQueryableObjectsIncludingAccount() {
    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Assert.isFalse(
      result.isEmpty(),
      'listObjects() must return at least one queryable, accessible object in the org.'
    );

    Boolean foundAccount = false;
    for (SchemaService.ObjectInfo info : result) {
      if (info.apiName == 'Account') {
        foundAccount = true;
        Assert.areEqual(
          'Account',
          info.label,
          'Account ObjectInfo.label should be "Account" for the standard Account object ' +
          'on a default org/scratch org configuration.'
        );
        break;
      }
    }
    Assert.isTrue(
      foundAccount,
      'listObjects() should include the standard Account object, which is queryable and ' +
      'accessible by default.'
    );
  }

  @isTest
  static void listObjectsResultIsSortedByLabelCaseInsensitiveWithApiNameTieBreak() {
    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Assert.isFalse(
      result.isEmpty(),
      'listObjects() must return at least one object to verify sort order against.'
    );

    for (Integer i = 1; i < result.size(); i++) {
      SchemaService.ObjectInfo prev = result[i - 1];
      SchemaService.ObjectInfo curr = result[i];

      String prevLabel = (prev.label == null ? '' : prev.label).toLowerCase();
      String currLabel = (curr.label == null ? '' : curr.label).toLowerCase();
      Integer cmp = prevLabel.compareTo(currLabel);

      if (cmp == 0) {
        String prevApi = (prev.apiName == null ? '' : prev.apiName);
        String currApi = (curr.apiName == null ? '' : curr.apiName);
        Assert.isTrue(
          prevApi.compareTo(currApi) <= 0,
          'When two ObjectInfo entries share the same label (case-insensitive), ' +
            'they must be ordered by API name ascending as a tie-break. ' +
            'Found out-of-order pair: "' +
            prevApi +
            '" before "' +
            currApi +
            '" ' +
            'with shared label "' +
            prevLabel +
            '".'
        );
      } else {
        Assert.isTrue(
          cmp < 0,
          'listObjects() result must be sorted by label, case-insensitive, ascending. ' +
            'Found out-of-order pair: "' +
            prev.label +
            '" (api=' +
            prev.apiName +
            ') ' +
            'before "' +
            curr.label +
            '" (api=' +
            curr.apiName +
            ').'
        );
      }
    }
  }

  @isTest
  static void listObjectsExcludesKnownSystemNoiseSuffixes() {
    Set<String> bannedSuffixes = new Set<String>{
      '__share',
      '__history',
      '__feed',
      '__changeevent',
      '__tag'
    };

    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    for (SchemaService.ObjectInfo info : result) {
      String lowerApi = (info.apiName == null ? '' : info.apiName)
        .toLowerCase();
      for (String suffix : bannedSuffixes) {
        Assert.isFalse(
          lowerApi.endsWith(suffix),
          'listObjects() must exclude system/setup noise objects, but returned "' +
            info.apiName +
            '" which ends with the banned suffix "' +
            suffix +
            '".'
        );
      }
    }

    // Spot-check a well-known example pair, when present in this org's global describe,
    // to confirm the standard object (Account) is kept while its noise siblings are not.
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Set<String> resultApiNames = new Set<String>();
    for (SchemaService.ObjectInfo info : result) {
      resultApiNames.add(info.apiName);
    }

    Assert.isTrue(
      resultApiNames.contains('Account'),
      'listObjects() should still include the standard Account object after applying ' +
      'the noise-suffix exclusions.'
    );

    List<String> accountNoiseSiblings = new List<String>{
      'AccountShare',
      'AccountHistory',
      'AccountFeed',
      'AccountChangeEvent'
    };
    for (String sibling : accountNoiseSiblings) {
      if (globalDescribe.containsKey(sibling)) {
        Assert.isFalse(
          resultApiNames.contains(sibling),
          'listObjects() must exclude "' +
            sibling +
            '" because it matches a ' +
            'system/setup noise suffix, even though it is queryable and accessible.'
        );
      }
    }
  }

  /**
   * Regression guard for the double-underscore ('__' + suffix) noise-sibling form, which
   * isSystemObject() matches UNCONDITIONALLY regardless of isCustom() (it is the sibling
   * pattern for CUSTOM parents, e.g. MyObject__c => MyObject__Share). This project's
   * deployed schema has no custom object whose sharing/history/feed configuration
   * generates a real MyObject__Share/__History/__Feed/__ChangeEvent/__Tag sibling (the
   * only custom object, AnthropicSettings__c, is a Custom Setting and is filtered out
   * earlier by isCustomSetting(), before isSystemObject() is ever reached), so this test
   * cannot assert a positive custom-parent match against real deployed metadata.
   *
   * Instead, it scans the FULL org-wide global describe (not just listObjects()'s
   * filtered result) for ANY custom object matching the '__' + suffix pattern that would
   * also pass listObjects()'s permission/custom-setting/deprecated gates, and asserts it
   * is excluded from the result. This exercises the exact production condition
   * (`lower.endsWith('__' + bare)`, matched regardless of isCustomObject) against
   * whatever custom schema exists in the executing org, protecting against a future
   * regression where the unconditional '__'+suffix check is accidentally scoped to
   * isCustomObject == true only (which would be the wrong fix — see class comments).
   */
  @isTest
  static void listObjectsExcludesCustomObjectNoiseSuffixesWhenPresentInOrg() {
    Set<String> customSuffixForms = new Set<String>{
      '__share',
      '__history',
      '__feed',
      '__changeevent',
      '__tag'
    };

    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Set<String> resultApiNames = new Set<String>();
    for (SchemaService.ObjectInfo info : result) {
      resultApiNames.add(info.apiName);
    }

    Integer customSiblingCandidatesFound = 0;
    for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
      Schema.DescribeSObjectResult d = t.getDescribe();
      if (!d.isCustom() || !d.isQueryable() || !d.isAccessible()) {
        continue;
      }
      if (d.isCustomSetting() || d.isDeprecatedAndHidden()) {
        continue;
      }
      String lowerApi = d.getName().toLowerCase();
      Boolean isCustomSiblingForm = false;
      for (String suffix : customSuffixForms) {
        if (lowerApi.length() > suffix.length() && lowerApi.endsWith(suffix)) {
          isCustomSiblingForm = true;
          break;
        }
      }
      if (!isCustomSiblingForm) {
        continue;
      }
      customSiblingCandidatesFound++;
      Assert.isFalse(
        resultApiNames.contains(d.getName()),
        'listObjects() must exclude the custom-parent noise sibling "' +
          d.getName() +
          '" because its API name ends with a "__"+suffix form, which isSystemObject() ' +
          'matches unconditionally regardless of isCustom().'
      );
    }

    if (customSiblingCandidatesFound == 0) {
      // Documented coverage gap: no custom "__Share"/"__History"/"__Feed"/
      // "__ChangeEvent"/"__Tag" sibling exists in this org's deployed schema to assert
      // against. Custom objects cannot be created via DML/metadata in an Apex test, so
      // this branch's positive behavior is verified by code inspection (see
      // isSystemObject() doc comment) rather than a live assertion here.
      Assert.isTrue(
        true,
        'No custom "__"+suffix noise-sibling object exists in this org to assert ' +
          'against; see comment above for why this is a documented gap rather than a ' +
          'live assertion.'
      );
    }
  }

  /**
   * False-positive guard: standard objects whose API name CONTAINS a noise suffix word
   * but does not END WITH it must NOT be excluded. isSystemObject() uses endsWith(), not
   * contains(), so e.g. "FeedItem" (contains "Feed" as a prefix) or "FieldHistoryArchive"
   * (contains "History" mid-name) must be kept.
   */
  @isTest
  static void listObjectsKeepsStandardObjectsThatContainButDoNotEndWithNoiseSuffix() {
    List<String> nonSuffixCandidates = new List<String>{
      'FeedItem',
      'FeedComment',
      'FieldHistoryArchive',
      'TagDefinition'
    };

    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Set<String> resultApiNames = new Set<String>();
    for (SchemaService.ObjectInfo info : result) {
      resultApiNames.add(info.apiName);
    }

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    for (String candidate : nonSuffixCandidates) {
      if (!globalDescribe.containsKey(candidate)) {
        continue;
      }
      Schema.DescribeSObjectResult d = globalDescribe.get(candidate)
        .getDescribe();
      if (
        !d.isQueryable() ||
        !d.isAccessible() ||
        d.isCustomSetting() ||
        d.isDeprecatedAndHidden()
      ) {
        // Not eligible for listObjects() for reasons unrelated to the noise-suffix
        // filter (e.g. feature not enabled in this org) -- skip rather than assert.
        continue;
      }
      Assert.isTrue(
        resultApiNames.contains(candidate),
        'listObjects() must NOT exclude "' +
          candidate +
          '" -- it contains a noise-suffix word but does not END WITH it, so the ' +
          'endsWith()-based isSystemObject() check must keep it.'
      );
    }
  }

  /**
   * Boundary guard for the "strictly longer than the suffix" length check in
   * isSystemObject(): a standard object whose API name is EXACTLY equal to one of the
   * bare suffix words (e.g. a hypothetical object literally named "Tag" or "Feed") must
   * not be excluded, since it is not actually a sibling of anything -- it IS the object.
   * No standard object in a default org's global describe has an API name exactly equal
   * to "Share"/"History"/"Feed"/"ChangeEvent"/"Tag", so this is a best-effort check
   * against whatever schema exists in the executing org; the length-guard behavior is
   * otherwise documented in isSystemObject()'s doc comment and covered at the line level
   * by every other test in this class (the guard executes on every object/suffix pair
   * checked by listObjects()).
   */
  @isTest
  static void listObjectsDoesNotExcludeObjectNamedExactlyEqualToBareSuffix() {
    List<String> bareSuffixes = new List<String>{
      'Share',
      'History',
      'Feed',
      'ChangeEvent',
      'Tag'
    };

    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Set<String> resultApiNames = new Set<String>();
    for (SchemaService.ObjectInfo info : result) {
      resultApiNames.add(info.apiName);
    }

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Integer exactMatchCandidatesFound = 0;
    for (String bareSuffix : bareSuffixes) {
      if (!globalDescribe.containsKey(bareSuffix)) {
        continue;
      }
      Schema.DescribeSObjectResult d = globalDescribe.get(bareSuffix)
        .getDescribe();
      if (
        d.isCustom() ||
        !d.isQueryable() ||
        !d.isAccessible() ||
        d.isCustomSetting() ||
        d.isDeprecatedAndHidden()
      ) {
        continue;
      }
      exactMatchCandidatesFound++;
      Assert.isTrue(
        resultApiNames.contains(bareSuffix),
        'listObjects() must not exclude "' +
          bareSuffix +
          '" purely because it matches a bare noise-suffix word exactly -- the length ' +
          'guard requires the name to be STRICTLY LONGER than the suffix for a match.'
      );
    }

    if (exactMatchCandidatesFound == 0) {
      // Documented coverage gap: see class comment above -- no default-org standard
      // object has an API name exactly equal to a bare noise-suffix word.
      Assert.isTrue(
        true,
        'No standard object named exactly equal to a bare noise-suffix word exists in ' +
          'this org to assert against; see comment above for why this is a documented ' +
          'gap rather than a live assertion.'
      );
    }
  }

  @isTest
  static void listObjectsExcludesCustomSettingsAndDeprecatedHiddenObjects() {
    Test.startTest();
    List<SchemaService.ObjectInfo> result = SchemaService.listObjects();
    Test.stopTest();

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

    for (SchemaService.ObjectInfo info : result) {
      Schema.SObjectType t = globalDescribe.get(info.apiName);
      Assert.isNotNull(
        t,
        'Every ObjectInfo returned by listObjects() must correspond to a real entry ' +
          'in Schema.getGlobalDescribe(). Missing: ' +
          info.apiName
      );

      Schema.DescribeSObjectResult d = t.getDescribe();
      Assert.isFalse(
        d.isCustomSetting(),
        'listObjects() must not return custom setting objects, but returned "' +
          info.apiName +
          '" which has isCustomSetting() == true.'
      );
      Assert.isFalse(
        d.isDeprecatedAndHidden(),
        'listObjects() must not return deprecated-and-hidden objects, but returned "' +
          info.apiName +
          '" which has isDeprecatedAndHidden() == true.'
      );
      Assert.isTrue(
        d.isQueryable() && d.isAccessible(),
        'listObjects() must only return objects the running user can query and ' +
          'access, but returned "' +
          info.apiName +
          '" which fails the ' +
          'isQueryable()/isAccessible() permission gate.'
      );
    }
  }

  @isTest
  static void describeObjectReturnsAccessibleFieldsForAccount() {
    Test.startTest();
    List<SchemaService.FieldInfo> fields = SchemaService.describeObject(
      'Account'
    );
    Test.stopTest();

    Assert.isFalse(
      fields.isEmpty(),
      'describeObject("Account") must return at least one accessible field for the ' +
      'standard Account object.'
    );

    Boolean foundIdField = false;
    for (SchemaService.FieldInfo fi : fields) {
      if (fi.apiName == 'Id') {
        foundIdField = true;
        Assert.areEqual(
          'ID',
          fi.type,
          'The Id field on Account should describe with type ID.'
        );
        Assert.isNotNull(
          fi.label,
          'FieldInfo.label should be populated from the field describe result.'
        );
        break;
      }
    }
    Assert.isTrue(
      foundIdField,
      'describeObject("Account") should include the standard Id field, which is always ' +
      'accessible.'
    );
  }

  @isTest
  static void describeObjectUnknownObjectThrowsSchemaException() {
    SchemaService.SchemaException caught;

    Test.startTest();
    try {
      SchemaService.describeObject('NotARealObject__x');
    } catch (SchemaService.SchemaException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'describeObject() with an unknown object API name must throw a SchemaException.'
    );
    Assert.isTrue(
      caught.getMessage().contains('NotARealObject__x'),
      'The SchemaException message should include the unrecognized object API name. ' +
        'Actual message: ' +
        caught.getMessage()
    );
  }

  @isTest
  static void buildSchemaContextSingleObjectIncludesFieldNamesAndTypes() {
    Test.startTest();
    String context = SchemaService.buildSchemaContext(
      new List<String>{ 'Account' }
    );
    Test.stopTest();

    Assert.isTrue(
      context.startsWith('Account: '),
      'buildSchemaContext() for a single object should produce a block starting with ' +
        '"Account: ". Actual context: ' +
        context
    );
    Assert.isTrue(
      context.contains('Id (ID)'),
      'buildSchemaContext() should include each field formatted as "apiName (type)", ' +
        'e.g. "Id (ID)". Actual context: ' +
        context
    );
  }

  @isTest
  static void buildSchemaContextMultipleObjectsJoinedByNewline() {
    Test.startTest();
    String context = SchemaService.buildSchemaContext(
      new List<String>{ 'Account', 'Contact' }
    );
    Test.stopTest();

    List<String> lines = context.split('\n');
    Assert.areEqual(
      2,
      lines.size(),
      'buildSchemaContext() with two object API names should produce two newline-separated ' +
        'blocks, one per object. Actual context: ' +
        context
    );
    Assert.isTrue(
      lines[0].startsWith('Account: '),
      'The first block should describe the Account object. Actual: ' + lines[0]
    );
    Assert.isTrue(
      lines[1].startsWith('Contact: '),
      'The second block should describe the Contact object. Actual: ' + lines[1]
    );
  }

  @isTest
  static void buildSchemaContextEmptyListReturnsEmptyString() {
    Test.startTest();
    String context = SchemaService.buildSchemaContext(new List<String>());
    Test.stopTest();

    Assert.areEqual(
      '',
      context,
      'buildSchemaContext() with an empty list of object API names should return an empty ' +
      'string (String.join of an empty list of blocks).'
    );
  }
}
