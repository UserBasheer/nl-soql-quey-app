/**
 * Native schema introspection. Uses Schema.getGlobalDescribe / describe calls — no REST
 * round-trips, and field-level visibility is naturally the running user's.
 * Produces a compact, model-friendly schema string to ground translation.
 */
public with sharing class SchemaService {

    /** List queryable objects (API name + label) the user can see. */
    public static List<ObjectInfo> listObjects() {
        List<ObjectInfo> out = new List<ObjectInfo>();
        for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult d = t.getDescribe();
            if (d.isQueryable() && d.isAccessible()) {
                out.add(new ObjectInfo(d.getName(), d.getLabel()));
            }
        }
        return out;
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
