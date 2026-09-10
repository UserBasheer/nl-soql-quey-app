/**
 * Owns ALL persistence for SOQL Whisperer run history.
 *
 * DML BOUNDARY (Phase 4): this class touches `SOQL_Query_History__c` and nothing else.
 * `QueryService` stays 100% DML-free — the read-only guarantee against queried org data is
 * structural, not documentary. Logging is invoked from `SoqlWhispererController` AFTER the
 * query has run, never from inside `QueryService`.
 *
 * Stores query TEXT and run METADATA only. Result rows are never persisted anywhere.
 *
 * `with sharing` + `AccessLevel.USER_MODE` + OWD Private on the object means each user only
 * ever reads or deletes their own history — no hand-rolled owner filters needed on reads.
 */
public with sharing class QueryHistoryService {
  public static final String STATUS_SUCCESS = 'Success';
  public static final String STATUS_ERROR = 'Error';

  // Read bounds. History is a high-volume object (one row per run) and is NEVER read
  // unbounded — a caller-supplied limit is clamped server-side, not trusted.
  @TestVisible
  private static final Integer DEFAULT_LIMIT = 25;
  @TestVisible
  private static final Integer MIN_LIMIT = 1;
  @TestVisible
  private static final Integer MAX_LIMIT = 200;

  // Bounded so a single clear can never exceed the 10,000-row DML governor limit.
  @TestVisible
  private static final Integer CLEAR_LIMIT = 10000;

  // Field lengths, mirrored from the object metadata. Values are truncated defensively
  // before insert so an over-length input degrades the log entry instead of failing it.
  private static final Integer LEN_SOQL = 5000;
  private static final Integer LEN_NATURAL_LANGUAGE = 1000;
  private static final Integer LEN_OBJECT_SCOPE = 1000;
  private static final Integer LEN_ERROR_MESSAGE = 255;

  /**
   * Record one query attempt — success or failure.
   *
   * CONTRACT: THIS METHOD MUST NEVER THROW. A history write is a side effect of the user's
   * query, never a precondition for it. If the user lacks Create on the history object (for
   * example the `SOQL_Whisperer_User` permission set was not assigned), or a field is
   * inaccessible, or the insert fails for any other reason, the failure is swallowed here so
   * the caller still returns the user's results.
   */
  public static void logRun(
    String soql,
    String naturalLanguage,
    List<String> objectScope,
    Integer rowCount,
    String status,
    String errorMessage
  ) {
    try {
      SOQL_Query_History__c entry = new SOQL_Query_History__c(
        SOQL__c = truncate(soql, LEN_SOQL),
        Natural_Language__c = truncate(naturalLanguage, LEN_NATURAL_LANGUAGE),
        Object_Scope__c = truncate(joinScope(objectScope), LEN_OBJECT_SCOPE),
        Row_Count__c = rowCount == null ? 0 : rowCount,
        Status__c = normalizeStatus(status),
        Error_Message__c = truncate(errorMessage, LEN_ERROR_MESSAGE)
      );
      Database.insert(entry, AccessLevel.USER_MODE);
    } catch (Exception loggingFailure) {
      // Intentionally swallowed — see the never-throw contract above. Nothing is
      // rethrown and nothing is logged to the debug log (prohibited in production code);
      // a missing history row is the correct, silent degradation for this feature.
    }
  }

  /**
   * Most recent history for the running user, newest first.
   * `limitSize` is clamped to [1, 200]; null means the default page of 25.
   */
  public static List<SOQL_Query_History__c> getRecent(Integer limitSize) {
    Integer clamped = clampLimit(limitSize);
    // No OwnerId filter: OWD Private + `with sharing` + USER_MODE already restrict this
    // to the running user's own records. A manual filter here would duplicate the sharing
    // model and hide real permission bugs.
    return [
      SELECT
        Id,
        Name,
        SOQL__c,
        Natural_Language__c,
        Object_Scope__c,
        Row_Count__c,
        Status__c,
        Error_Message__c,
        CreatedDate
      FROM SOQL_Query_History__c
      WITH USER_MODE
      ORDER BY CreatedDate DESC, Name DESC
      LIMIT :clamped
    ];
  }

  /**
   * Delete the running user's own history. Returns the number of records deleted.
   *
   * Unlike the read path this DOES filter on OwnerId. This is a bulk, irreversible delete,
   * and an admin with View All / Modify All Data would otherwise wipe every user's history
   * from a button labelled "Clear my history". The filter is a blast-radius guard, not a
   * substitute for sharing.
   */
  public static Integer clearMine() {
    Id runningUserId = UserInfo.getUserId();
    List<SOQL_Query_History__c> mine = [
      SELECT Id
      FROM SOQL_Query_History__c
      WHERE OwnerId = :runningUserId
      WITH USER_MODE
      LIMIT :CLEAR_LIMIT
    ];
    if (mine.isEmpty()) {
      return 0;
    }
    Database.delete(mine, AccessLevel.USER_MODE);
    return mine.size();
  }

  @TestVisible
  private static Integer clampLimit(Integer limitSize) {
    if (limitSize == null) {
      return DEFAULT_LIMIT;
    }
    return Math.min(MAX_LIMIT, Math.max(MIN_LIMIT, limitSize));
  }

  /**
   * `Status__c` is a restricted picklist. Anything that is not exactly one of the two
   * allowed values is stored as null rather than being allowed to fail the whole insert.
   */
  @TestVisible
  private static String normalizeStatus(String status) {
    if (String.isBlank(status)) {
      return null;
    }
    if (STATUS_SUCCESS.equalsIgnoreCase(status.trim())) {
      return STATUS_SUCCESS;
    }
    if (STATUS_ERROR.equalsIgnoreCase(status.trim())) {
      return STATUS_ERROR;
    }
    return null;
  }

  @TestVisible
  private static String joinScope(List<String> objectScope) {
    if (objectScope == null || objectScope.isEmpty()) {
      return null;
    }
    List<String> cleaned = new List<String>();
    for (String apiName : objectScope) {
      if (String.isNotBlank(apiName)) {
        cleaned.add(apiName.trim());
      }
    }
    return cleaned.isEmpty() ? null : String.join(cleaned, ',');
  }

  @TestVisible
  private static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value)) {
      return null;
    }
    return value.length() <= maxLength ? value : value.substring(0, maxLength);
  }
}
