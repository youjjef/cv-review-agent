/**
 * Aura-enabled controller for the CV upload workspace LWC.
 * Supports client-side PDF.js text extraction payloads.
 */
public with sharing class CvUploadController {
    public class LocalFilePayload {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
        @AuraEnabled public String extractedText { get; set; }
    }

    @AuraEnabled
    public static List<CvIngestionService.IngestResult> processUploads(List<Id> contentVersionIds) {
        try {
            return CvIngestionService.ingestContentVersions(contentVersionIds);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<CvIngestionService.IngestResult> processUploadsWithText(
        List<CvIngestionService.UploadPayload> payloads
    ) {
        try {
            return CvIngestionService.ingestUploads(payloads);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates ContentVersion records and ingests Candidate Cards.
     * For PDFs, pass extractedText from client PDF.js (embedded text, not OCR).
     */
    @AuraEnabled
    public static List<CvIngestionService.IngestResult> ingestLocalFiles(List<LocalFilePayload> payloads) {
        try {
            if (payloads == null || payloads.isEmpty()) {
                return new List<CvIngestionService.IngestResult>();
            }
            List<CvIngestionService.IngestResult> results = new List<CvIngestionService.IngestResult>();
            for (LocalFilePayload payload : payloads) {
                results.add(ingestOneLocalFile(payload));
            }
            return results;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static CvIngestionService.IngestResult ingestOneLocalFile(LocalFilePayload payload) {
        if (payload == null || String.isBlank(payload.fileName) || String.isBlank(payload.base64Data)) {
            CvIngestionService.IngestResult failed = new CvIngestionService.IngestResult();
            failed.parseStatus = CvConstants.PARSE_FAILED;
            failed.message = 'File name and content are required.';
            failed.candidateName = payload == null ? null : payload.fileName;
            return failed;
        }

        String path = payload.fileName;
        String title = path.contains('.') ? path.substring(0, path.lastIndexOf('.')) : path;
        String ext = path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';

        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = path;
        cv.VersionData = EncodingUtil.base64Decode(payload.base64Data);
        cv.IsMajorVersion = true;
        insert cv;

        cv = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        // Prefer client-extracted PDF text; for .txt also prefer client text when provided.
        String extracted = payload.extractedText;
        if (String.isBlank(extracted) && ext.toLowerCase() == 'txt') {
            extracted = cv.VersionData.toString();
        }
        return CvIngestionService.ingestOne(cv, extracted);
    }

    @AuraEnabled(cacheable=true)
    public static List<Candidate__c> listRecentCandidates() {
        return [
            SELECT Id, Name, Email__c, Phone__c, Location__c, Years_Experience__c,
                   Parse_Status__c, Uncertainty_Summary__c, Source_File_Name__c, CreatedDate
            FROM Candidate__c
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Candidate__c getCandidateDetail(Id candidateId) {
        return [
            SELECT Id, Name, Email__c, Phone__c, Location__c, Summary__c, Years_Experience__c,
                   Parse_Status__c, Uncertainty_Summary__c, Source_File_Name__c, LinkedIn_URL__c,
                   (SELECT Id, Name, Confidence__c, Evidence__c, Years__c FROM Skills__r),
                   (SELECT Id, Name, Company__c, Title__c, Start_Date_Text__c, End_Date_Text__c,
                           Description__c, Has_Date_Conflict__c, Confidence__c FROM Experiences__r),
                   (SELECT Id, Name, School__c, Degree__c, Field_Of_Study__c, End_Date_Text__c, Confidence__c
                    FROM Educations__r),
                   (SELECT Id, Name, Issue_Type__c, Field_Path__c, Details__c, Severity__c FROM Data_Issues__r)
            FROM Candidate__c
            WHERE Id = :candidateId
            LIMIT 1
        ];
    }
}
