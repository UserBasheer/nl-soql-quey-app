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
        // Read the admin-configurable provider flag from custom metadata.
        // Prefer the 'Default' record; fall back to any available record.
        // Default to 'Claude' when no record exists or Provider__c is blank.
        Map<String, SOQL_Whisperer_Setting__mdt> settings = SOQL_Whisperer_Setting__mdt.getAll();

        SOQL_Whisperer_Setting__mdt setting = settings.get('Default');
        if (setting == null && !settings.isEmpty()) {
            setting = settings.values()[0];
        }

        if (setting != null && String.isNotBlank(setting.Provider__c)) {
            return setting.Provider__c;
        }
        return 'Claude';
    }
}
