/**
 * Executes SOQL READ-ONLY. Two independent safety layers:
 *   1. validate(): structural check — must be a SELECT, must contain no DML keywords.
 *   2. WITH USER_MODE on the query — FLS + sharing enforced as the running user.
 * Either alone would help; together they're belt-and-suspenders for a customer-facing tool.
 */
public with sharing class QueryService {

    private static final Set<String> FORBIDDEN =
        new Set<String>{ 'insert', 'update', 'delete', 'upsert', 'merge', 'undelete' };

    /** Validate without running. Returns list of human-readable errors (empty = valid). */
    public static List<String> validate(String soql) {
        List<String> errors = new List<String>();
        if (String.isBlank(soql)) {
            errors.add('Query is empty.');
            return errors;
        }
        String trimmed = soql.trim();
        if (!trimmed.toLowerCase().startsWith('select')) {
            errors.add('Query must start with SELECT (read-only).');
        }
        String lower = trimmed.toLowerCase();
        for (String kw : FORBIDDEN) {
            if (Pattern.compile('(?i)\\b' + kw + '\\b').matcher(lower).find()) {
                errors.add('Write operation "' + kw + '" is not allowed (read-only tool).');
            }
        }
        return errors;
    }

    /** Validate then execute in user mode. Throws on invalid or unsafe input. */
    @AuraEnabled
    public static List<SObject> runQuery(String soql) {
        List<String> errors = validate(soql);
        if (!errors.isEmpty()) {
            throw new QueryException(String.join(errors, ' '));
        }
        try {
            // Layer 2: USER_MODE enforces FLS + sharing for the running user.
            return Database.queryWithBinds(soql, new Map<String, Object>(), AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new QueryException('Query failed: ' + e.getMessage());
        }
    }

    public class QueryException extends Exception {}
}
