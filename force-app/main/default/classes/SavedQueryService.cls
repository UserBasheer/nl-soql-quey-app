/**
 * Owns ALL persistence for user-saved SOQL Whisperer queries.
 *
 * DML BOUNDARY (Phase 4): this class touches `SOQL_Saved_Query__c` and nothing else.
 * `QueryService` stays 100% DML-free; nothing here executes or validates user SOQL.
 *
 * Stores query TEXT and its originating prompt/object scope only — never result rows.
 * Saved SOQL text can itself contain PHI in WHERE-clause literals, which is why the object is
 * OWD Private: `with sharing` + `AccessLevel.USER_MODE` then give per-user isolation with no
 * custom sharing logic and no hand-rolled owner filters on read/delete.
 */
public with sharing class SavedQueryService {
  private static final Integer LIST_LIMIT = 200;

  // Field lengths, mirrored from the object metadata (Name is the standard 80-char text
  // name field). Values are truncated defensively so an over-length input cannot fail DML.
  private static final Integer LEN_NAME = 80;
  private static final Integer LEN_SOQL = 5000;
  private static final Integer LEN_NATURAL_LANGUAGE = 1000;
  private static final Integer LEN_OBJECT_SCOPE = 1000;

  /**
   * Create or overwrite a saved query for the running user.
   *
   * Overwrite semantics: `Name` is deliberately NOT unique on the object (uniqueness in
   * Salesforce is org-wide, which would collide across users in a per-user tool), so dedupe
   * happens here — matched on Name + OwnerId of the running user.
   */
  public static SOQL_Saved_Query__c saveQuery(
    String name,
    String soql,
    String naturalLanguage,
    List<String> objectScope
  ) {
    if (String.isBlank(name)) {
      throw clientError('Give the saved query a name before saving it.');
    }
    if (String.isBlank(soql)) {
      throw clientError(
        'There is no SOQL to save. Generate or type a query first.'
      );
    }

    String savedName = truncate(name.trim(), LEN_NAME);
    Id runningUserId = UserInfo.getUserId();
    List<SOQL_Saved_Query__c> existing = [
      SELECT Id, Name
      FROM SOQL_Saved_Query__c
      WHERE Name = :savedName AND OwnerId = :runningUserId
      WITH USER_MODE
      LIMIT 1
    ];

    Boolean isNew = existing.isEmpty();
    SOQL_Saved_Query__c record = isNew
      ? new SOQL_Saved_Query__c(Name = savedName)
      : existing[0];
    record.SOQL__c = truncate(soql, LEN_SOQL);
    record.Natural_Language__c = truncate(
      naturalLanguage,
      LEN_NATURAL_LANGUAGE
    );
    record.Object_Scope__c = truncate(joinScope(objectScope), LEN_OBJECT_SCOPE);

    if (isNew) {
      Database.insert(record, AccessLevel.USER_MODE);
    } else {
      Database.update(record, AccessLevel.USER_MODE);
    }
    return record;
  }

  /** The running user's saved queries, name-ordered. */
  public static List<SOQL_Saved_Query__c> listMine() {
    // No OwnerId filter: OWD Private + `with sharing` + USER_MODE already scope this to
    // the running user. Duplicating that in a WHERE clause would mask permission bugs.
    return [
      SELECT
        Id,
        Name,
        SOQL__c,
        Natural_Language__c,
        Object_Scope__c,
        LastModifiedDate
      FROM SOQL_Saved_Query__c
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT :LIST_LIMIT
    ];
  }

  /**
   * Delete one saved query. Isolation is enforced by the sharing model: the user-mode SELECT
   * simply returns nothing for a record the running user cannot see, so another user's record
   * is unreachable without any manual owner check.
   */
  public static void deleteSavedQuery(Id recordId) {
    if (recordId == null) {
      throw clientError('Select a saved query to delete.');
    }
    List<SOQL_Saved_Query__c> target = [
      SELECT Id
      FROM SOQL_Saved_Query__c
      WHERE Id = :recordId
      WITH USER_MODE
      LIMIT 1
    ];
    if (target.isEmpty()) {
      throw clientError(
        'That saved query no longer exists, or you do not have access to it.'
      );
    }
    Database.delete(target, AccessLevel.USER_MODE);
  }

  /**
   * `AuraHandledException` does not surface its constructor message to the client unless
   * `setMessage` is also called — without this the LWC only ever sees "Script-thrown
   * exception", which is useless for a validation message the user is meant to act on.
   */
  private static AuraHandledException clientError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
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
