/**
 * Native schema introspection. Uses Schema.getGlobalDescribe / describe calls — no REST
 * round-trips, and field-level visibility is naturally the running user's.
 * Produces a compact, model-friendly schema string to ground translation.
 */
public with sharing class SchemaService {
  /**
   * System/setup object name suffixes that are queryable+accessible but are noise for a
   * user-facing picker (share rows, history, feeds, change events, tags). These are never
   * objects a user picks to ground a business query, so we exclude them from the listing.
   * This only NARROWS the list — it never widens access.
   *
   * Stored as BARE words. The matching form depends on whether the object is custom:
   *   - custom sibling  -> '__' + suffix  (MyObject__c => MyObject__Share, MyObject__History)
   *   - standard sibling -> suffix        (Account      => AccountShare,   AccountHistory)
   * See isSystemObject() for how the two forms are applied.
   */
  private static final List<String> SYSTEM_SUFFIXES = new List<String>{
    'Share',
    'History',
    'Feed',
    'ChangeEvent',
    'Tag'
  };

  /**
   * List queryable objects (API name + label) the user can see, excluding system/setup noise.
   *
   * Permission filter (unchanged): keep only objects the running user can query and access
   * (isQueryable() && isAccessible()) — combined with `with sharing`, this is the running
   * user's effective object/FLS visibility.
   *
   * Noise exclusions: custom settings, deprecated/hidden objects, and the system-sibling
   * suffixes above in BOTH their custom ('MyObject__Share') and standard ('AccountShare')
   * forms. These never grant access; they only remove objects no user would legitimately
   * pick to ground a query. Standard objects and __c custom objects are kept.
   *
   * Result is sorted by label for a stable, user-friendly picker order. No hard cap is
   * applied — accessible business objects are never silently truncated.
   */
  public static List<ObjectInfo> listObjects() {
    List<ObjectInfo> out = new List<ObjectInfo>();
    for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
      Schema.DescribeSObjectResult d = t.getDescribe();

      // Permission gate — unchanged. Only objects the user can query and access.
      if (!d.isQueryable() || !d.isAccessible()) {
        continue;
      }
      // Noise gate — narrow only. Skip system/setup objects no user would ground on.
      if (
        d.isCustomSetting() ||
        d.isDeprecatedAndHidden() ||
        isSystemObject(d.getName(), d.isCustom())
      ) {
        continue;
      }

      out.add(new ObjectInfo(d.getName(), d.getLabel()));
    }

    out.sort(new ObjectInfoLabelComparator());
    return out;
  }

  /**
   * True if the API name is a system/setup noise sibling of a real object (case-insensitive).
   *
   * Two forms are matched, because the platform names these siblings differently for
   * custom and standard parents:
   *   - '__' + suffix is ALWAYS noise (MyObject__Share, MyObject__History). Checked
   *     regardless of isCustom(), since the double-underscore form is a reserved pattern.
   *   - the bare suffix is noise only for STANDARD objects (AccountShare, CaseHistory,
   *     OpportunityFeed, AccountChangeEvent). Custom object API names always carry a
   *     '__c'/'__x'/'__mdt'/'__e'/'__b' style ending, so the bare check is not applied to
   *     them — that is what keeps a legitimately-named custom object out of this filter.
   *
   * A match also requires the name to be strictly longer than the suffix, so an object
   * named exactly 'Tag' or 'Feed' is not hidden by a sibling rule that does not apply.
   *
   * @TestVisible: this is pure string/boolean logic with no SOQL/describe dependency of
   * its own (the caller supplies apiName/isCustomObject already resolved from a describe
   * result). Exposing it to the test class lets the '__'+suffix-regardless-of-isCustom
   * branch and the exact-length boundary guard be asserted directly with synthetic inputs,
   * instead of depending on org schema happening to contain a matching fixture object.
   */
  @TestVisible
  private static Boolean isSystemObject(
    String apiName,
    Boolean isCustomObject
  ) {
    if (String.isBlank(apiName)) {
      return false;
    }
    String lower = apiName.toLowerCase();
    for (String suffix : SYSTEM_SUFFIXES) {
      String bare = suffix.toLowerCase();
      String custom = '__' + bare;

      // Custom-parent sibling form — always noise.
      if (lower.length() > custom.length() && lower.endsWith(custom)) {
        return true;
      }
      // Standard-parent sibling form — bare suffix, standard objects only.
      if (
        isCustomObject != true &&
        lower.length() > bare.length() &&
        lower.endsWith(bare)
      ) {
        return true;
      }
    }
    return false;
  }

  /** Sorts ObjectInfo by label (case-insensitive), then by API name for stable ordering. */
  private class ObjectInfoLabelComparator implements Comparator<ObjectInfo> {
    public Integer compare(ObjectInfo a, ObjectInfo b) {
      String la = (a.label == null ? '' : a.label).toLowerCase();
      String lb = (b.label == null ? '' : b.label).toLowerCase();
      Integer byLabel = la.compareTo(lb);
      if (byLabel != 0) {
        return byLabel;
      }
      String aa = (a.apiName == null ? '' : a.apiName);
      String ba = (b.apiName == null ? '' : b.apiName);
      return aa.compareTo(ba);
    }
  }

  /** Describe a single object's accessible fields. */
  public static List<FieldInfo> describeObject(String objectApiName) {
    List<FieldInfo> fields = new List<FieldInfo>();
    Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName);
    if (t == null) {
      throw new SchemaException('Unknown object: ' + objectApiName);
    }
    for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      if (fd.isAccessible()) {
        fields.add(
          new FieldInfo(
            fd.getName(),
            fd.getLabel(),
            String.valueOf(fd.getType())
          )
        );
      }
    }
    return fields;
  }

  /**
   * Build the compact schema context string passed to the translation provider.
   * Only the objects relevant to this request are included (keeps large orgs in-budget).
   */
  public static String buildSchemaContext(List<String> objectApiNames) {
    List<String> blocks = new List<String>();
    for (String objName : objectApiNames) {
      List<String> fieldStrs = new List<String>();
      for (FieldInfo fi : describeObject(objName)) {
        fieldStrs.add(fi.apiName + ' (' + fi.type + ')');
      }
      blocks.add(objName + ': ' + String.join(fieldStrs, ', '));
    }
    return String.join(blocks, '\n');
  }

  public class ObjectInfo {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    public ObjectInfo(String a, String l) {
      apiName = a;
      label = l;
    }
  }
  public class FieldInfo {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String type;
    public FieldInfo(String a, String l, String t) {
      apiName = a;
      label = l;
      type = t;
    }
  }
  public class SchemaException extends Exception {
  }
}
