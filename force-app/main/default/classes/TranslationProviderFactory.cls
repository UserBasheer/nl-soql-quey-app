/**
 * Selects which TranslationProvider to use. Reads a custom setting / metadata flag so an
 * admin can pick Einstein vs Claude per org at install time, without code changes.
 * Defaults to Claude when no Einstein entitlement is configured.
 */
public with sharing class TranslationProviderFactory {

    @TestVisible private static String overrideProvider;

    public static TranslationProvider getProvider() {
        String choice = (overrideProvider != null)
            ? overrideProvider
            : resolveConfiguredProvider();

        if (choice == 'Einstein') {
            return new EinsteinTranslationProvider();
        }
        return new ClaudeTranslationProvider();
    }

    private static String resolveConfiguredProvider() {
        // Phase 1: read from a custom metadata type, e.g. SOQL_Whisperer_Setting__mdt.Provider__c.
        // Stubbed to 'Claude' as the safe default for orgs without Einstein.
        return 'Claude';
    }
}
