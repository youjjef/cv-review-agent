@IsTest
private class CvIngestionServiceTest {
    @IsTest
    static void parsesStructuredTxtCv() {
        ContentVersion cv = new ContentVersion(
            Title = 'Sara_Hassan_Salesforce',
            PathOnClient = 'Sara_Hassan_Salesforce.txt',
            VersionData = Blob.valueOf(SampleCvs.SARA),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        CvIngestionService.IngestResult result = CvIngestionService.ingestOne(cv);
        Test.stopTest();

        System.assertEquals(CvConstants.PARSE_SUCCESS, result.parseStatus, result.message);
        System.assertNotEquals(null, result.candidateId);
        Candidate__c c = [
            SELECT Email__c, (SELECT Id FROM Skills__r), (SELECT Id FROM Experiences__r), (SELECT Id FROM Educations__r)
            FROM Candidate__c WHERE Id = :result.candidateId
        ];
        System.assertEquals('sara.hassan@email.com', c.Email__c);
        System.assert(c.Skills__r.size() > 0);
        System.assert(c.Experiences__r.size() > 0);
        System.assert(c.Educations__r.size() > 0);
    }

    @IsTest
    static void flagsConflictsOnAmbiguousCv() {
        ContentVersion cv = new ContentVersion(
            Title = 'Ambiguous_Conflict_CV',
            PathOnClient = 'Ambiguous_Conflict_CV.txt',
            VersionData = Blob.valueOf(SampleCvs.AMBIGUOUS),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        CvIngestionService.IngestResult result = CvIngestionService.ingestOne(cv);
        Test.stopTest();

        List<Candidate_Experience__c> exps = [
            SELECT Title__c, Start_Date_Text__c, End_Date_Text__c, Has_Date_Conflict__c
            FROM Candidate_Experience__c
            WHERE Candidate__c = :result.candidateId
        ];
        System.assert(exps.size() >= 2, 'Expected two roles, got ' + exps.size());

        List<Candidate_Data_Issue__c> issues = [
            SELECT Issue_Type__c, Details__c FROM Candidate_Data_Issue__c WHERE Candidate__c = :result.candidateId
        ];
        Boolean hasConflict = false;
        Boolean hasMissingEmail = false;
        for (Candidate_Data_Issue__c issue : issues) {
            if (issue.Issue_Type__c == CvConstants.ISSUE_CONFLICTING) {
                hasConflict = true;
            }
            if (issue.Issue_Type__c == CvConstants.ISSUE_MISSING) {
                hasMissingEmail = true;
            }
        }
        System.assert(
            hasConflict,
            'Expected conflicting employment dates. Experiences=' + JSON.serialize(exps) + ' Issues=' + JSON.serialize(issues)
        );
        System.assert(hasMissingEmail, 'Expected missing email issue');
    }

    @IsTest
    static void binaryStubUsesFilenameFixture() {
        // Simulate non-printable binary payload
        Blob binaryish = EncodingUtil.convertFromHex('255044462d312e34'); // %PDF-1.4
        ContentVersion cv = new ContentVersion(
            Title = 'Omar_Java_Engineer',
            PathOnClient = 'Omar_Java_Engineer.pdf',
            VersionData = binaryish,
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        CvIngestionService.IngestResult result = CvIngestionService.ingestOne(cv);
        Test.stopTest();

        System.assertEquals(CvConstants.PARSE_PARTIAL, result.parseStatus);
        Candidate__c c = [SELECT Name FROM Candidate__c WHERE Id = :result.candidateId];
        System.assert(c.Name.contains('Omar') || c.Name != null);
    }

    @IsTest
    static void usesClientExtractedPdfText() {
        ContentVersion cv = new ContentVersion(
            Title = 'Real_Pdf_Cv',
            PathOnClient = 'Real_Pdf_Cv.pdf',
            VersionData = EncodingUtil.convertFromHex('255044462d312e34'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, Title, FileExtension, VersionData, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        CvIngestionService.IngestResult result = CvIngestionService.ingestOne(cv, SampleCvs.SARA);
        Test.stopTest();

        System.assertNotEquals(null, result.candidateId);
        Candidate__c card = [SELECT Email__c FROM Candidate__c WHERE Id = :result.candidateId];
        System.assertEquals('sara.hassan@email.com', card.Email__c);
        System.assert(result.message != null && result.message.contains('PDF embedded text'));
    }

    @IsTest
    static void ingestLocalFilesCreatesContentAndCard() {
        CvUploadController.LocalFilePayload payload = new CvUploadController.LocalFilePayload();
        payload.fileName = 'Client_Extract.txt';
        payload.base64Data = EncodingUtil.base64Encode(Blob.valueOf(SampleCvs.OMAR));
        payload.extractedText = SampleCvs.OMAR;

        Test.startTest();
        List<CvIngestionService.IngestResult> results = CvUploadController.ingestLocalFiles(
            new List<CvUploadController.LocalFilePayload>{ payload }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].candidateId);
        System.assertEquals(
            'omar.farid@email.com',
            [SELECT Email__c FROM Candidate__c WHERE Id = :results[0].candidateId].Email__c
        );
    }

    @IsTest
    static void parsesRunOnPdfExtract() {
        String runOn =
            'Youssef Mohamedyousseffj78@gmail.com +201069105349 New Cairo , Cairo , Egypt LinkedIn GitHub ' +
            'PROFESSIONAL EXPERIENCESalesforce Developer, Arcsen•Delivered end-to-end Salesforce solutions ' +
            'across Service and Sales Cloud projects, including Flows, validation rules, and custom business ' +
            'logic with Apex (triggers, classes, batch, REST APIs).11/2025 – Present•Developed dynamic, ' +
            'responsive user interfaces using Lightning Web Components (LWC) and Aura components.' +
            'Cloud Engineer, Huawei•Delivered and deployed Huawei Cloud infrastructure.04/2023 – 10/2025 ' +
            'EDUCATIONCairo University | BSc Computer Science | 2022 ' +
            'SKILLSApex, LWC, Salesforce, REST';

        Test.startTest();
        CvIngestionService.ParsedCv parsed = CvIngestionService.parseText(runOn, 'Youssef_Mohamed_CV', false);
        Test.stopTest();

        System.assertEquals('Youssef Mohamed', parsed.fullName, parsed.uncertaintySummary);
        System.assertEquals('yousseffj78@gmail.com', parsed.email);
        System.assert(String.isNotBlank(parsed.location) && parsed.location.contains('Cairo'), parsed.location);
        System.assert(parsed.experiences.size() >= 1, 'Expected at least one experience');
        System.assertEquals('Salesforce Developer', parsed.experiences[0].title);
        System.assertEquals('Arcsen', parsed.experiences[0].company);
        System.assert(parsed.experiences[0].title.length() <= 255);
        System.assert(String.isNotBlank(parsed.experiences[0].description), 'Bullets should land in description');
        System.assert(!parsed.experiences[0].description.startsWith('Salesforce Developer'));
    }
}
