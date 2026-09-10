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
   * earlier by isCustomSetting(), before isSystemObject() is ever reached), so a
   * listObjects()-level assertion against org fixtures cannot exercise this branch.
   *
   * Since isSystemObject() is pure string/boolean logic (@TestVisible, no SOQL/describe
   * dependency of its own), it is called directly here with synthetic inputs instead —
   * this gives live regression protection for the exact production condition
   * (`lower.endsWith('__' + bare)`, matched regardless of isCustomObject) regardless of
   * what custom schema happens to exist in the executing org.
   */
  @isTest
  static void listObjectsExcludesCustomObjectNoiseSuffixesWhenPresentInOrg() {
    // '__' + suffix form must match for a "custom" parent...
    Assert.isTrue(
      SchemaService.isSystemObject('Foo__Share', true),
      'isSystemObject() must treat "Foo__Share" as noise for a custom parent ' +
      '(isCustomObject = true) since it matches the "__"+suffix sibling form.'
    );
    // ...and MUST ALSO match when isCustomObject is false, because the '__'+suffix form
    // is checked unconditionally (per the class doc comment) -- this is the exact branch
    // a future regression could accidentally scope to isCustomObject == true only.
    Assert.isTrue(
      SchemaService.isSystemObject('Foo__Share', false),
      'isSystemObject() must match the "__"+suffix sibling form ("Foo__Share") ' +
        'UNCONDITIONALLY, regardless of isCustomObject -- this form is a reserved ' +
        'platform naming pattern, not something gated on isCustom().'
    );
    // Sanity-check the other suffixes too, so the whole SYSTEM_SUFFIXES list is exercised
    // against this branch, not just "Share".
    List<String> customSiblingSamples = new List<String>{
      'Foo__History',
      'Foo__Feed',
      'Foo__ChangeEvent',
      'Foo__Tag'
    };
    for (String sample : customSiblingSamples) {
      Assert.isTrue(
        SchemaService.isSystemObject(sample, false),
        'isSystemObject() must match the "__"+suffix sibling form ("' +
          sample +
          '") unconditionally, regardless of isCustomObject.'
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
   * to "Share"/"History"/"Feed"/"ChangeEvent"/"Tag", so a listObjects()-level assertion
   * against org fixtures cannot exercise this branch.
   *
   * Since isSystemObject() is pure string/boolean logic (@TestVisible, no SOQL/describe
   * dependency of its own), it is called directly here with synthetic inputs that are
   * exactly equal to each bare suffix, giving live regression protection for the length
   * guard regardless of what standard schema exists in the executing org.
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

    for (String bareSuffix : bareSuffixes) {
      // Exactly equal to the bare suffix, standard parent -- must NOT match, since the
      // name is not strictly longer than the suffix (it IS the suffix, not a sibling).
      Assert.isFalse(
        SchemaService.isSystemObject(bareSuffix, false),
        'isSystemObject() must not treat "' +
          bareSuffix +
          '" as noise purely because it matches a bare noise-suffix word exactly -- ' +
          'the length guard requires the name to be STRICTLY LONGER than the suffix.'
      );
      // One character longer, standard parent -- MUST match, confirming the guard is a
      // strict "longer than" check and not merely case-insensitivity or a typo.
      String oneCharLonger = 'A' + bareSuffix;
      Assert.isTrue(
        SchemaService.isSystemObject(oneCharLonger, false),
        'isSystemObject() must treat "' +
          oneCharLonger +
          '" as a noise sibling -- it is strictly longer than the bare suffix "' +
          bareSuffix +
          '" and ends with it, for a standard parent.'
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
