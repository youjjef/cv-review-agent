// Seed sample Candidate Cards from fixture text (no file upload required).
List<ContentVersion> versions = new List<ContentVersion>{
    new ContentVersion(Title='Sara_Hassan_Salesforce', PathOnClient='Sara_Hassan_Salesforce.txt', VersionData=Blob.valueOf(SampleCvs.SARA), IsMajorVersion=true),
    new ContentVersion(Title='Omar_Farid_Java', PathOnClient='Omar_Farid_Java.txt', VersionData=Blob.valueOf(SampleCvs.OMAR), IsMajorVersion=true),
    new ContentVersion(Title='Lina_Mostafa_Data', PathOnClient='Lina_Mostafa_Data.txt', VersionData=Blob.valueOf(SampleCvs.LINA), IsMajorVersion=true),
    new ContentVersion(Title='Ambiguous_Conflict_CV', PathOnClient='Ambiguous_Conflict_CV.txt', VersionData=Blob.valueOf(SampleCvs.AMBIGUOUS), IsMajorVersion=true)
};
insert versions;
List<Id> ids = new List<Id>();
for (ContentVersion cv : [SELECT Id FROM ContentVersion WHERE Id IN :versions]) {
    ids.add(cv.Id);
}
List<CvIngestionService.IngestResult> results = CvIngestionService.ingestContentVersions(ids);
for (CvIngestionService.IngestResult r : results) {
    System.debug(r.candidateName + ' => ' + r.parseStatus + ' ' + r.candidateId);
}
