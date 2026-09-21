@IsTest
private class CvAgentActionsTest {
    private static Id seedCandidate() {
        ContentVersion cv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        return CvIngestionService.ingestOne(cv).candidateId;
    }

    @IsTest
    static void scoresComparesAndBookmarks() {
        Id saraId = seedCandidate();
        ContentVersion cv2 = new ContentVersion(
            Title = 'Omar_Java',
            PathOnClient = 'Omar.txt',
            VersionData = Blob.valueOf(SampleCvs.OMAR),
            IsMajorVersion = true
        );
        insert cv2;
        cv2 = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id];
        Id omarId = CvIngestionService.ingestOne(cv2).candidateId;

        CvAgentActions.ActionRequest listReq = new CvAgentActions.ActionRequest();
        listReq.operation = 'listCandidates';

        CvAgentActions.ActionRequest cardReq = new CvAgentActions.ActionRequest();
        cardReq.operation = 'getCandidateCard';
        cardReq.candidateId = saraId;

        CvAgentActions.ActionRequest searchReq = new CvAgentActions.ActionRequest();
        searchReq.operation = 'searchCandidateFacts';
        searchReq.candidateId = saraId;
        searchReq.searchQuery = 'Does Sara know Apex?';

        CvAgentActions.ActionRequest unknownReq = new CvAgentActions.ActionRequest();
        unknownReq.operation = 'searchCandidateFacts';
        unknownReq.candidateId = saraId;
        unknownReq.searchQuery = 'quantum teleportation clearance';

        CvAgentActions.ActionRequest scoreReq = new CvAgentActions.ActionRequest();
        scoreReq.operation = 'scoreForRole';
        scoreReq.candidateId = saraId;
        scoreReq.roleTitle = 'Salesforce Developer';
        scoreReq.requiredSkillsCsv = 'Apex,LWC,SOQL';
        scoreReq.minYears = 3;

        CvAgentActions.ActionRequest compareReq = new CvAgentActions.ActionRequest();
        compareReq.operation = 'compareCandidates';
        compareReq.candidateIdsCsv = saraId + ',' + omarId;
        compareReq.roleTitle = 'Salesforce Developer';
        compareReq.requiredSkillsCsv = 'Apex,LWC';
        compareReq.minYears = 3;

        CvAgentActions.ActionRequest bookmarkReq = new CvAgentActions.ActionRequest();
        bookmarkReq.operation = 'bookmarkCandidate';
        bookmarkReq.candidateId = saraId;
        bookmarkReq.roleTitle = 'Salesforce Developer';
        bookmarkReq.requiredSkillsCsv = 'Apex,LWC';
        bookmarkReq.minYears = 3;
        bookmarkReq.recruiterNotes = 'Strong Agentforce-ready profile.';

        Test.startTest();
        List<CvAgentActions.ActionResponse> responses = CvAgentActions.execute(
            new List<CvAgentActions.ActionRequest>{
                listReq, cardReq, searchReq, unknownReq, scoreReq, compareReq, bookmarkReq
            }
        );
        Test.stopTest();

        System.assertEquals(7, responses.size());
        for (CvAgentActions.ActionResponse res : responses) {
            System.assertEquals(true, res.success, res.message);
        }
        System.assert(responses[2].message.contains('Apex') || responses[2].message.contains('skill'));
        System.assert(responses[3].message.contains('Not found'));
        System.assert([SELECT COUNT() FROM Candidate_Bookmark__c WHERE Candidate__c = :saraId] > 0);
        System.assert([SELECT COUNT() FROM Agent_Decision_Log__c] > 0);
    }

    @IsTest
    static void uploadControllerListsCandidates() {
        Id idVal = seedCandidate();
        Test.startTest();
        List<Candidate__c> rows = CvUploadController.listRecentCandidates();
        Candidate__c detail = CvUploadController.getCandidateDetail(idVal);
        Test.stopTest();
        System.assert(!rows.isEmpty());
        System.assertEquals(idVal, detail.Id);
    }
}
