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
     */
    private static final List<String> SYSTEM_SUFFIXES = new List<String>{
        '__Share', '__History', '__Feed', '__ChangeEvent', '__Tag'
    };

    /**
     * List queryable objects (API name + label) the user can see, excluding system/setup noise.
     *
     * Permission filter (unchanged): keep only objects the running user can query and access
     * (isQueryable() && isAccessible()) — combined with `with sharing`, this is the running
     * user's effective object/FLS visibility.
     *
     * Noise exclusions (new): custom settings, deprecated/hidden objects, and the system
     * suffixes above. These never grant access; they only remove objects no user would
     * legitimately pick to ground a query. Standard objects and __c custom objects are kept.
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
            if (d.isCustomSetting() || d.isDeprecatedAndHidden() || isSystemObject(d.getName())) {
                continue;
            }

            out.add(new ObjectInfo(d.getName(), d.getLabel()));
        }

        out.sort(new ObjectInfoLabelComparator());
        return out;
    }

    /** True if the API name ends in one of the system/setup suffixes (case-insensitive). */
    private static Boolean isSystemObject(String apiName) {
        if (String.isBlank(apiName)) {
            return false;
        }
        String lower = apiName.toLowerCase();
        for (String suffix : SYSTEM_SUFFIXES) {
            if (lower.endsWith(suffix.toLowerCase())) {
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
                fields.add(new FieldInfo(fd.getName(), fd.getLabel(), String.valueOf(fd.getType())));
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
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        public ObjectInfo(String a, String l) { apiName = a; label = l; }
    }
    public class FieldInfo {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        public FieldInfo(String a, String l, String t) { apiName = a; label = l; type = t; }
    }
    public class SchemaException extends Exception {}
}
