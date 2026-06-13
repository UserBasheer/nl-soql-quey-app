@isTest
private class TranslationProviderFactoryTest {

    @TestSetup
    static void setup() {
        // No SObject data required. TranslationProviderFactory reads
        // SOQL_Whisperer_Setting__mdt, which is deployed metadata (the shipped
        // 'Default' record with Provider__c = 'Claude'). CMDT records cannot be
        // inserted via DML/Test.loadData in Apex tests, so this suite relies on
        // the metadata as deployed alongside this test class.
    }

    @isTest
    static void getProviderWithNoOverrideReturnsClaudeUsingShippedDefaultMetadata() {
        // Ensure no override is in play so getProvider() falls through to
        // resolveConfiguredProvider().
        TranslationProviderFactory.overrideProvider = null;

        Test.startTest();
        TranslationProvider provider = TranslationProviderFactory.getProvider();
        Test.stopTest();

        System.assert(
            provider instanceof ClaudeTranslationProvider,
            'With the shipped SOQL_Whisperer_Setting__mdt "Default" record (Provider__c = Claude) ' +
            'and no override, getProvider() must return a ClaudeTranslationProvider.'
        );
    }

    @isTest
    static void getProviderOverrideEinsteinReturnsEinsteinProvider() {
        TranslationProviderFactory.overrideProvider = 'Einstein';

        Test.startTest();
        TranslationProvider provider = TranslationProviderFactory.getProvider();
        Test.stopTest();

        System.assert(
            provider instanceof EinsteinTranslationProvider,
            '@TestVisible overrideProvider = "Einstein" must force getProvider() to return ' +
            'an EinsteinTranslationProvider regardless of the configured CMDT value.'
        );

        // Reset so this test does not leak static state into other tests.
        TranslationProviderFactory.overrideProvider = null;
    }

    @isTest
    static void getProviderOverrideClaudeReturnsClaudeProvider() {
        TranslationProviderFactory.overrideProvider = 'Claude';

        Test.startTest();
        TranslationProvider provider = TranslationProviderFactory.getProvider();
        Test.stopTest();

        System.assert(
            provider instanceof ClaudeTranslationProvider,
            '@TestVisible overrideProvider = "Claude" must force getProvider() to return ' +
            'a ClaudeTranslationProvider.'
        );

        TranslationProviderFactory.overrideProvider = null;
    }

    @isTest
    static void getProviderOverrideUnrecognizedValueFallsBackToClaude() {
        // The loose string compare in getProvider() only special-cases 'Einstein';
        // any other value (including garbage) must fall through to Claude.
        TranslationProviderFactory.overrideProvider = 'SomeUnknownProvider';

        Test.startTest();
        TranslationProvider provider = TranslationProviderFactory.getProvider();
        Test.stopTest();

        System.assert(
            provider instanceof ClaudeTranslationProvider,
            'An unrecognized override value must fall back to ClaudeTranslationProvider ' +
            '(getProvider() only special-cases the literal "Einstein").'
        );

        TranslationProviderFactory.overrideProvider = null;
    }

    @isTest
    static void resolveConfiguredProviderViaShippedDefaultMetadataReturnsClaude() {
        // resolveConfiguredProvider() is private, so it is exercised indirectly through
        // getProvider() with overrideProvider cleared. The shipped CMDT 'Default' record
        // has Provider__c = 'Claude', so this confirms the configured-value path returns
        // 'Claude' (and, independently, the blank/no-record default would also be
        // 'Claude' - see coverage gap note below).
        TranslationProviderFactory.overrideProvider = null;

        Test.startTest();
        TranslationProvider provider = TranslationProviderFactory.getProvider();
        Test.stopTest();

        System.assert(
            provider instanceof ClaudeTranslationProvider,
            'resolveConfiguredProvider() should read Provider__c = "Claude" from the shipped ' +
            'SOQL_Whisperer_Setting__mdt "Default" record and getProvider() should return ' +
            'ClaudeTranslationProvider as a result.'
        );
    }

    // COVERAGE GAP (documented, not implemented):
    // The blank-Provider__c / no-CMDT-record fallback branch inside
    // resolveConfiguredProvider() (TranslationProviderFactory.cls lines 28-35) cannot be
    // exercised in isolation from this test class. CMDT records are deployed metadata and
    // are not insertable via DML or Test.loadData in Apex tests, and
    // TranslationProviderFactory does not currently expose a @TestVisible seam to stub
    // SOQL_Whisperer_Setting__mdt.getAll(). Both the "no record" and "shipped Default"
    // paths happen to converge on 'Claude' today, so behavior is still covered end-to-end
    // via getProviderWithNoOverrideReturnsClaudeUsingShippedDefaultMetadata() above, but the
    // fallback branch itself is not independently asserted. If isolated coverage of that
    // branch becomes a requirement, the developer agent would need to add a small
    // dependency-injection seam (e.g. a @TestVisible static Map<String,
    // SOQL_Whisperer_Setting__mdt> override) - that is out of scope for this test pass.
}
