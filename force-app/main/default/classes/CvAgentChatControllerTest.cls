@IsTest
private class CvAgentChatControllerTest {
    @IsTest
    static void routesCoreUtterances() {
        ContentVersion saraCv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara_Hassan_Salesforce.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert saraCv;
        saraCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :saraCv.Id
        ];
        CvIngestionService.ingestOne(saraCv, SampleCvs.SARA);

        ContentVersion omarCv = new ContentVersion(
            Title = 'Omar_Java_Engineer',
            PathOnClient = 'Omar_Java_Engineer.txt',
            VersionData = Blob.valueOf(SampleCvs.OMAR),
            IsMajorVersion = true
        );
        insert omarCv;
        omarCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :omarCv.Id
        ];
        CvIngestionService.ingestOne(omarCv, SampleCvs.OMAR);

        Test.startTest();
        System.assertEquals(false, CvAgentChatController.ask('', null).success);
        System.assertEquals('listCandidates', CvAgentChatController.ask('List candidates', null).operation);
        System.assertEquals(
            'searchCandidateFacts',
            CvAgentChatController.ask('Does Sara know Apex?', null).operation
        );
        System.assertEquals(
            'compareCandidates',
            CvAgentChatController.ask('Compare Sara and Omar for Salesforce Developer', null).operation
        );
        System.assertEquals(
            'bookmarkCandidate',
            CvAgentChatController.ask('Bookmark Sara for Salesforce Developer', null).operation
        );
        System.assertEquals(
            'scoreForRole',
            CvAgentChatController.ask('Score Sara for Salesforce Developer', null).operation
        );
        System.assertEquals(
            'listDataIssues',
            CvAgentChatController.ask('Show data issues for Sara', null).operation
        );
        System.assertEquals(
            'getCandidateCard',
            CvAgentChatController.ask('Show card for Sara', null).operation
        );
        CvAgentChatController.ChatReply javaRole = CvAgentChatController.ask(
            'Compare for Java role',
            null
        );
        System.assertEquals('compareCandidates', javaRole.operation);
        CvAgentChatController.ChatReply dataRole = CvAgentChatController.ask(
            'Score for data role',
            null
        );
        System.assertEquals('scoreForRole', dataRole.operation);
        String botId = CvAgentChatController.getAgentBotId();
        Test.stopTest();

        System.assertNotEquals(null, botId);
    }

    @IsTest
    static void routingHelpersCoverNameLookup() {
        ContentVersion cv = new ContentVersion(
            Title = 'Lina_Data',
            PathOnClient = 'Lina_Data.txt',
            VersionData = Blob.valueOf(SampleCvs.LINA),
            IsMajorVersion = true
        );
        insert cv;
        cv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        CvIngestionService.ingestOne(cv, SampleCvs.LINA);

        ContentVersion saraCv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara_Hassan_Salesforce.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert saraCv;
        saraCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :saraCv.Id
        ];
        CvIngestionService.ingestOne(saraCv, SampleCvs.SARA);

        Test.startTest();
        CvAgentActions.ActionRequest aboutLina = CvAgentChatController.routeUtterance(
            'Tell me about Lina skills',
            null
        );
        CvAgentActions.ActionRequest compareLinaSara = CvAgentChatController.routeUtterance(
            'Compare Lina to Sara',
            null
        );
        Test.stopTest();

        System.assertEquals('getCandidateCard', aboutLina.operation);
        System.assertNotEquals(null, aboutLina.candidateId);
        System.assertEquals('compareCandidates', compareLinaSara.operation);
        List<String> compareIds = compareLinaSara.candidateIdsCsv.split(',');
        System.assertEquals(2, compareIds.size(), compareLinaSara.candidateIdsCsv);
        Id linaId = [SELECT Id FROM Candidate__c WHERE Name = 'Lina Mostafa' LIMIT 1].Id;
        Id saraId = [SELECT Id FROM Candidate__c WHERE Name = 'Sara Hassan' LIMIT 1].Id;
        System.assert(
            compareIds.contains(String.valueOf(linaId)) && compareIds.contains(String.valueOf(saraId)),
            'Expected Lina and Sara, got: ' + compareLinaSara.candidateIdsCsv
        );
    }

    @IsTest
    static void formatsFullAnswersFromPayload() {
        ContentVersion saraCv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara_Hassan_Salesforce.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert saraCv;
        saraCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :saraCv.Id
        ];
        CvIngestionService.ingestOne(saraCv, SampleCvs.SARA);

        ContentVersion omarCv = new ContentVersion(
            Title = 'Omar_Java_Engineer',
            PathOnClient = 'Omar_Java_Engineer.txt',
            VersionData = Blob.valueOf(SampleCvs.OMAR),
            IsMajorVersion = true
        );
        insert omarCv;
        omarCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :omarCv.Id
        ];
        CvIngestionService.ingestOne(omarCv, SampleCvs.OMAR);

        Test.startTest();
        CvAgentChatController.ChatReply card = CvAgentChatController.ask('Show card for Sara', null);
        CvAgentChatController.ChatReply score = CvAgentChatController.ask(
            'Score Sara for Salesforce Developer',
            null
        );
        CvAgentChatController.ChatReply compare = CvAgentChatController.ask(
            'Compare Sara and Omar for Salesforce Developer',
            null
        );
        String scoreFormatted = CvAgentChatController.formatRecruiterAnswer(
            'scoreForRole',
            'Short line',
            '{"candidateName":"Sara Hassan","candidateId":"x","totalScore":80,"skillsScore":40,"experienceScore":20,"educationScore":10,"completenessScore":10,"strongMatch":true,"strengths":["Apex"],"concerns":["LWC"],"tradeOffs":["trade"],"interviewGaps":["gap"]}'
        );
        String blankPayload = CvAgentChatController.formatRecruiterAnswer('listCandidates', 'Only message', null);
        Test.stopTest();

        System.assertEquals(true, card.success);
        System.assert(card.message.contains('Skills:'), card.message);
        System.assert(card.message.contains('Experience:'), card.message);
        System.assertEquals(true, score.success);
        System.assert(score.message.contains('Strengths'), score.message);
        System.assertEquals(true, compare.success);
        System.assert(compare.message.contains('Strengths'), compare.message);
        System.assert(scoreFormatted.contains('Interview gaps'), scoreFormatted);
        System.assertEquals('Only message', blankPayload);
    }

    @IsTest
    static void compareDedupesDuplicateFirstNames() {
        // Two Youssef cards + Lina — compare must pick one Youssef and Lina, not two Youssefs.
        ContentVersion y1 = new ContentVersion(
            Title = 'Youssef_A',
            PathOnClient = 'Youssef_A.txt',
            VersionData = Blob.valueOf(
                'Youssef Mohamed\nEmail: y1@example.com\nSkills: Apex, LWC\nExperience: Salesforce Developer at Ace 2020-Present'
            ),
            IsMajorVersion = true
        );
        insert y1;
        y1 = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :y1.Id];
        CvIngestionService.ingestOne(y1, y1.VersionData.toString());

        ContentVersion y2 = new ContentVersion(
            Title = 'Youssef_B',
            PathOnClient = 'Youssef_B.txt',
            VersionData = Blob.valueOf(
                'Youssef Mohamed\nEmail: y2@example.com\nSkills: Java\nExperience: Engineer at Other 2019-Present'
            ),
            IsMajorVersion = true
        );
        insert y2;
        y2 = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :y2.Id];
        CvIngestionService.ingestOne(y2, y2.VersionData.toString());

        ContentVersion linaCv = new ContentVersion(
            Title = 'Lina_Data',
            PathOnClient = 'Lina_Data.txt',
            VersionData = Blob.valueOf(SampleCvs.LINA),
            IsMajorVersion = true
        );
        insert linaCv;
        linaCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :linaCv.Id
        ];
        CvIngestionService.ingestOne(linaCv, SampleCvs.LINA);

        Test.startTest();
        CvAgentChatController.ChatReply reply = CvAgentChatController.ask(
            'compare youssef to lina mostafa',
            null
        );
        Test.stopTest();

        System.assertEquals(true, reply.success, reply.message);
        System.assertEquals('compareCandidates', reply.operation);
        System.assert(reply.message.contains('Lina'), reply.message);
        System.assert(reply.message.contains('Youssef'), reply.message);
        Integer youssefHits = reply.message.countMatches('Youssef Mohamed — total');
        System.assertEquals(1, youssefHits, reply.message);
    }

    @IsTest
    static void ranksTopNForRole() {
        ContentVersion saraCv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara_Hassan_Salesforce.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert saraCv;
        saraCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :saraCv.Id
        ];
        CvIngestionService.ingestOne(saraCv, SampleCvs.SARA);

        ContentVersion omarCv = new ContentVersion(
            Title = 'Omar_Java_Engineer',
            PathOnClient = 'Omar_Java_Engineer.txt',
            VersionData = Blob.valueOf(SampleCvs.OMAR),
            IsMajorVersion = true
        );
        insert omarCv;
        omarCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :omarCv.Id
        ];
        CvIngestionService.ingestOne(omarCv, SampleCvs.OMAR);

        ContentVersion linaCv = new ContentVersion(
            Title = 'Lina_Data',
            PathOnClient = 'Lina_Data.txt',
            VersionData = Blob.valueOf(SampleCvs.LINA),
            IsMajorVersion = true
        );
        insert linaCv;
        linaCv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :linaCv.Id
        ];
        CvIngestionService.ingestOne(linaCv, SampleCvs.LINA);

        Test.startTest();
        System.assertEquals(3, CvAgentChatController.extractTopN('top 3 candidates for salesforce consultant role'));
        CvAgentActions.ActionRequest routed = CvAgentChatController.routeUtterance(
            'top 3 candidates for salesforce consultant role',
            null
        );
        CvAgentChatController.ChatReply reply = CvAgentChatController.ask(
            'top 3 candidates for salesforce consultant role',
            null
        );
        Test.stopTest();

        System.assertEquals('compareCandidates', routed.operation);
        System.assertEquals('Salesforce Consultant', routed.roleTitle);
        System.assert(routed.candidateIdsCsv.split(',').size() >= 2, routed.candidateIdsCsv);
        System.assertEquals(true, reply.success, reply.message);
        System.assert(reply.message.contains('Top 3'), reply.message);
        System.assert(reply.message.contains('Strengths'), reply.message);
        System.assert(!reply.message.contains('Grounded evidence'), reply.message);
    }
}
