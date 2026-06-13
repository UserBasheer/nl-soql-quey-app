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
    static void describeObjectReturnsAccessibleFieldsForAccount() {
        Test.startTest();
        List<SchemaService.FieldInfo> fields = SchemaService.describeObject('Account');
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
            'Actual message: ' + caught.getMessage()
        );
    }

    @isTest
    static void buildSchemaContextSingleObjectIncludesFieldNamesAndTypes() {
        Test.startTest();
        String context = SchemaService.buildSchemaContext(new List<String>{ 'Account' });
        Test.stopTest();

        Assert.isTrue(
            context.startsWith('Account: '),
            'buildSchemaContext() for a single object should produce a block starting with ' +
            '"Account: ". Actual context: ' + context
        );
        Assert.isTrue(
            context.contains('Id (ID)'),
            'buildSchemaContext() should include each field formatted as "apiName (type)", ' +
            'e.g. "Id (ID)". Actual context: ' + context
        );
    }

    @isTest
    static void buildSchemaContextMultipleObjectsJoinedByNewline() {
        Test.startTest();
        String context = SchemaService.buildSchemaContext(new List<String>{ 'Account', 'Contact' });
        Test.stopTest();

        List<String> lines = context.split('\n');
        Assert.areEqual(
            2,
            lines.size(),
            'buildSchemaContext() with two object API names should produce two newline-separated ' +
            'blocks, one per object. Actual context: ' + context
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
