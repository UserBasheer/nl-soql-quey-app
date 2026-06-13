@isTest
private class EinsteinTranslationProviderTest {

    @isTest
    static void translateThrowsNotYetWiredException() {
        TranslationRequest req = new TranslationRequest(
            'all accounts',
            'Account(Id, Name)'
        );

        EinsteinTranslationProvider.TranslationException caught;

        Test.startTest();
        try {
            new EinsteinTranslationProvider().translate(req);
        } catch (EinsteinTranslationProvider.TranslationException e) {
            caught = e;
        }
        Test.stopTest();

        Assert.isNotNull(
            caught,
            'translate() builds the grounded prompt via buildPrompt() and must then throw a ' +
            'EinsteinTranslationProvider.TranslationException because the native Models API ' +
            'call is not yet wired.'
        );
        Assert.isTrue(
            caught.getMessage().contains('not yet wired'),
            'The TranslationException message should indicate the Einstein provider is not yet ' +
            'wired. Actual message: ' + caught.getMessage()
        );
    }
}
