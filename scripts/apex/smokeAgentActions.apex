// Smoke test grounded agent operations used by CV_Review_Agent
List<CvAgentActions.ActionRequest> reqs = new List<CvAgentActions.ActionRequest>();

CvAgentActions.ActionRequest listReq = new CvAgentActions.ActionRequest();
listReq.operation = 'listCandidates';
reqs.add(listReq);

CvAgentActions.ActionRequest searchYes = new CvAgentActions.ActionRequest();
searchYes.operation = 'searchCandidateFacts';
searchYes.candidateId = 'a06ak00000beTAtAAM'; // Sara Hassan
searchYes.searchQuery = 'Does Sara know Apex?';
reqs.add(searchYes);

CvAgentActions.ActionRequest searchNo = new CvAgentActions.ActionRequest();
searchNo.operation = 'searchCandidateFacts';
searchNo.candidateId = 'a06ak00000beTAtAAM';
searchNo.searchQuery = 'Does Sara have quantum teleportation clearance?';
reqs.add(searchNo);

CvAgentActions.ActionRequest compare = new CvAgentActions.ActionRequest();
compare.operation = 'compareCandidates';
compare.candidateIdsCsv = 'a06ak00000beTAtAAM,a06ak00000beTAvAAM'; // Sara, Omar
compare.roleTitle = 'Salesforce Developer';
compare.requiredSkillsCsv = 'Apex,LWC,SOQL';
compare.minYears = 3;
reqs.add(compare);

CvAgentActions.ActionRequest bookmark = new CvAgentActions.ActionRequest();
bookmark.operation = 'bookmarkCandidate';
bookmark.candidateId = 'a06ak00000beTAtAAM';
bookmark.roleTitle = 'Salesforce Developer';
bookmark.requiredSkillsCsv = 'Apex,LWC,SOQL';
bookmark.minYears = 3;
bookmark.recruiterNotes = 'Strong Agentforce-ready profile';
reqs.add(bookmark);

List<CvAgentActions.ActionResponse> results = CvAgentActions.execute(reqs);
for (CvAgentActions.ActionResponse r : results) {
    System.debug(LoggingLevel.ERROR, 'OP success=' + r.success + ' msg=' + r.message);
    System.debug(LoggingLevel.ERROR, 'PAYLOAD=' + (r.payloadJson == null ? '' : r.payloadJson.left(500)));
    System.debug(LoggingLevel.ERROR, 'RECORD=' + r.recordId);
}

Integer bookmarks = [SELECT COUNT() FROM Candidate_Bookmark__c WHERE Candidate__c = 'a06ak00000beTAtAAM'];
Integer logs = [SELECT COUNT() FROM Agent_Decision_Log__c WHERE CreatedDate = TODAY];
System.debug(LoggingLevel.ERROR, 'BOOKMARKS_FOR_SARA=' + bookmarks + ' LOGS_TODAY=' + logs);
