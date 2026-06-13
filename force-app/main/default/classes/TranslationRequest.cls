/**
 * Input to a TranslationProvider. Carries everything the model needs to produce SOQL:
 * the user's plain-English text, the schema subset (to ground generation and prevent
 * field hallucination), and optionally an existing query when the user is refining.
 */
public class TranslationRequest {
    public String naturalLanguage;     // user's request, e.g. "active care plans in the last 90 days"
    public String schemaContext;       // compact description of relevant objects/fields
    public String existingQuery;       // non-null when refining rather than generating fresh
    public Boolean isRefinement;       // true => adjust existingQuery, false => generate fresh

    public TranslationRequest(String nl, String schemaContext) {
        this.naturalLanguage = nl;
        this.schemaContext = schemaContext;
        this.isRefinement = false;
    }
}
