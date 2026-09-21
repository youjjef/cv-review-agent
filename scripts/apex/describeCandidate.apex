List<String> fields = new List<String>();
for (Schema.SObjectField f : Schema.SObjectType.Candidate__c.fields.getMap().values()) {
    fields.add(f.getDescribe().getName());
}
System.debug('FIELDS=' + String.join(fields, ','));
System.debug('EMAIL_ACCESSIBLE=' + Schema.sObjectType.Candidate__c.fields.Email__c.isAccessible());
System.debug('LOG_CREATEABLE=' + Schema.sObjectType.Agent_Decision_Log__c.isCreateable());
