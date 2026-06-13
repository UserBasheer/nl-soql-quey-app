/**
 * Abstraction over the NL->SOQL translation backend.
 * Implementations: EinsteinTranslationProvider (native), ClaudeTranslationProvider (callout).
 * Keeping this behind an interface means an org without Einstein can fall back to Claude
 * (or any future provider) without touching the rest of the system.
 */
public interface TranslationProvider {
    /**
     * @param request natural language request + the relevant schema subset + (optional) existing query for refinement
     * @return raw SOQL string produced by the model (UNVALIDATED — caller must validate)
     */
    String translate(TranslationRequest request);
}
