/**
 * Persists Agentforce / Apex decision logs for explainability and auditability.
 */
public with sharing class CvAuditService {
    public static void log(
        String actionType,
        String inputJson,
        String outputJson,
        List<Id> candidateIds,
        String scoreBreakdownJson,
        String roleContext,
        Boolean success
    ) {
        if (!Schema.sObjectType.Agent_Decision_Log__c.isCreateable()) {
            return;
        }
        Agent_Decision_Log__c row = new Agent_Decision_Log__c();
        row.Action_Type__c = actionType;
        row.Input_JSON__c = truncate(inputJson, 32000);
        row.Output_JSON__c = truncate(outputJson, 100000);
        row.Candidate_Ids__c = candidateIds == null ? null : String.join(toStrings(candidateIds), ',');
        row.Score_Breakdown_JSON__c = truncate(scoreBreakdownJson, 20000);
        row.Role_Context__c = roleContext;
        row.Success__c = success == null ? true : success;
        insert row;
    }

    private static List<String> toStrings(List<Id> ids) {
        List<String> out = new List<String>();
        for (Id i : ids) {
            out.add(String.valueOf(i));
        }
        return out;
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLen ? value : value.substring(0, maxLen);
    }
}
