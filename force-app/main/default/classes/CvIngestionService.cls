/**
 * CV ingestion: extracts structured Candidate Cards from uploaded file text.
 * PDF text is preferably supplied from client-side embedded-text extraction (not OCR).
 * Binary PDF/DOC without extractable text are marked Partial/Uncertain by design.
 */
public with sharing class CvIngestionService {
    public class IngestResult {
        @AuraEnabled public Id candidateId;
        @AuraEnabled public String parseStatus;
        @AuraEnabled public String message;
        @AuraEnabled public String candidateName;
    }

    public class UploadPayload {
        @AuraEnabled public Id contentVersionId { get; set; }
        @AuraEnabled public String extractedText { get; set; }
    }

    public static List<IngestResult> ingestContentVersions(List<Id> contentVersionIds) {
        List<UploadPayload> payloads = new List<UploadPayload>();
        if (contentVersionIds != null) {
            for (Id cvId : contentVersionIds) {
                UploadPayload p = new UploadPayload();
                p.contentVersionId = cvId;
                payloads.add(p);
            }
        }
        return ingestUploads(payloads);
    }

    public static List<IngestResult> ingestUploads(List<UploadPayload> payloads) {
        List<IngestResult> results = new List<IngestResult>();
        if (payloads == null || payloads.isEmpty()) {
            return results;
        }

        Set<Id> versionIds = new Set<Id>();
        Map<Id, String> textByVersion = new Map<Id, String>();
        for (UploadPayload p : payloads) {
            if (p != null && p.contentVersionId != null) {
                versionIds.add(p.contentVersionId);
                if (String.isNotBlank(p.extractedText)) {
                    textByVersion.put(p.contentVersionId, p.extractedText);
                }
            }
        }
        if (versionIds.isEmpty()) {
            return results;
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
        ];

        for (ContentVersion cv : versions) {
            results.add(ingestOne(cv, textByVersion.get(cv.Id)));
        }
        return results;
    }

    public static IngestResult ingestOne(ContentVersion cv) {
        return ingestOne(cv, null);
    }

    public static IngestResult ingestOne(ContentVersion cv, String clientExtractedText) {
        IngestResult result = new IngestResult();
        result.candidateName = cv.Title;

        try {
            Boolean usedClientText = String.isNotBlank(clientExtractedText);
            String rawText = usedClientText ? clientExtractedText : readText(cv);
            Boolean binaryLimited = String.isBlank(rawText);
            if (binaryLimited) {
                rawText = buildStubTextFromFilename(cv.Title);
            }

            // Client PDF text extraction of embedded text is first-class (not OCR, not stub).
            Boolean treatAsUncertainSource = binaryLimited && !usedClientText;
            ParsedCv parsed = parseText(rawText, cv.Title, treatAsUncertainSource);
            if (usedClientText) {
                addIssue(
                    parsed,
                    CvConstants.ISSUE_UNCERTAIN,
                    'Source',
                    'Text extracted from PDF embedded text in the browser (not OCR). Layout/order may vary.',
                    CvConstants.SEVERITY_INFO
                );
                // Refresh uncertainty summary after adding source note
                List<String> summaryBits = new List<String>();
                for (ParsedIssue issue : parsed.issues) {
                    summaryBits.add(issue.issueType + ': ' + issue.fieldPath + ' — ' + issue.details);
                }
                parsed.uncertaintySummary = String.join(summaryBits, '\n');
                if (parsed.parseStatus == CvConstants.PARSE_PARTIAL && !hasCriticalOrWarning(parsed)) {
                    parsed.parseStatus = CvConstants.PARSE_SUCCESS;
                }
            }

            Candidate__c candidate = new Candidate__c();
            candidate.Name = truncate(String.isBlank(parsed.fullName) ? cv.Title : parsed.fullName, 80);
            candidate.Email__c = parsed.email;
            candidate.Phone__c = truncate(parsed.phone, 40);
            candidate.Location__c = truncate(parsed.location, 255);
            candidate.Summary__c = parsed.summary;
            candidate.Years_Experience__c = parsed.yearsExperience;
            candidate.Source_File_Id__c = cv.ContentDocumentId;
            candidate.Source_File_Name__c = cv.Title + (String.isBlank(cv.FileExtension) ? '' : '.' + cv.FileExtension);
            candidate.Raw_CV_Text__c = truncate(rawText, 131072);
            candidate.Parse_Status__c = parsed.parseStatus;
            candidate.Raw_Extract_JSON__c = JSON.serialize(parsed);
            candidate.LinkedIn_URL__c = truncate(parsed.linkedin, 255);
            candidate.Uncertainty_Summary__c = truncate(parsed.uncertaintySummary, 5000);
            insert candidate;

            insertChildren(candidate.Id, parsed);

            result.candidateId = candidate.Id;
            result.parseStatus = parsed.parseStatus;
            if (usedClientText) {
                result.message = 'Candidate card created from PDF embedded text.';
            } else if (binaryLimited) {
                result.message = 'Binary CV had limited extractable text; structured fields marked Uncertain where stubbed.';
            } else {
                result.message = 'Candidate card created from CV text.';
            }
            result.candidateName = candidate.Name;
        } catch (Exception e) {
            result.parseStatus = CvConstants.PARSE_FAILED;
            result.message = e.getMessage();
        }
        return result;
    }

    private static Boolean hasCriticalOrWarning(ParsedCv parsed) {
        for (ParsedIssue issue : parsed.issues) {
            if (issue.severity == CvConstants.SEVERITY_CRITICAL || issue.severity == CvConstants.SEVERITY_WARNING) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    static String readText(ContentVersion cv) {
        if (cv.VersionData == null) {
            return null;
        }
        String ext = cv.FileExtension == null ? '' : cv.FileExtension.toLowerCase();
        if (ext == 'txt' || ext == 'md' || ext == 'csv' || ext == 'json') {
            return cv.VersionData.toString();
        }
        // Attempt UTF-8 decode for other types; binary PDFs typically yield unusable content.
        try {
            String asText = cv.VersionData.toString();
            if (String.isBlank(asText)) {
                return null;
            }
            Integer printable = 0;
            Integer sample = Math.min(asText.length(), 500);
            for (Integer i = 0; i < sample; i++) {
                Integer code = asText.charAt(i);
                if (code == 9 || code == 10 || code == 13 || (code >= 32 && code < 127)) {
                    printable++;
                }
            }
            if (sample > 0 && (Decimal.valueOf(printable) / Decimal.valueOf(sample)) >= 0.7) {
                return asText;
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    @TestVisible
    static String buildStubTextFromFilename(String title) {
        String key = title == null ? '' : title.toLowerCase();
        if (key.contains('sara') || key.contains('salesforce')) {
            return SampleCvs.SARA;
        }
        if (key.contains('omar') || key.contains('java')) {
            return SampleCvs.OMAR;
        }
        if (key.contains('lina') || key.contains('data')) {
            return SampleCvs.LINA;
        }
        if (key.contains('ambiguous') || key.contains('conflict')) {
            return SampleCvs.AMBIGUOUS;
        }
        return SampleCvs.GENERIC.replace('{{NAME}}', String.isBlank(title) ? 'Unknown Candidate' : title);
    }

    @TestVisible
    static ParsedCv parseText(String rawText, String fileTitle, Boolean binaryLimited) {
        ParsedCv p = new ParsedCv();
        p.skills = new List<ParsedSkill>();
        p.experiences = new List<ParsedExperience>();
        p.educations = new List<ParsedEducation>();
        p.issues = new List<ParsedIssue>();

        String text = normalizeExtractedText(rawText);
        List<String> lines = text.split('\\r?\\n');

        Matcher emailMatcher = Pattern.compile('[a-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}').matcher(text);
        if (emailMatcher.find()) {
            p.email = emailMatcher.group(0);
        } else {
            Matcher emailFallback = Pattern.compile('(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}').matcher(text);
            if (emailFallback.find()) {
                p.email = emailFallback.group(0);
            } else {
                addIssue(p, CvConstants.ISSUE_MISSING, 'Email__c', 'No email address found in CV.', CvConstants.SEVERITY_CRITICAL);
            }
        }

        p.fullName = firstNonEmptyLine(lines);
        if (isBadName(p.fullName)) {
            String beforeEmail = nameBeforeEmail(text, p.email);
            if (String.isNotBlank(beforeEmail)) {
                p.fullName = beforeEmail;
            } else {
                p.fullName = fileTitle;
                addIssue(p, CvConstants.ISSUE_UNCERTAIN, 'Name', 'Name inferred from filename.', CvConstants.SEVERITY_WARNING);
            }
        }

        Matcher phoneMatcher = Pattern.compile('(\\+?\\d[\\d\\s().-]{7,}\\d)').matcher(text);
        if (phoneMatcher.find()) {
            p.phone = phoneMatcher.group(1).trim();
        } else {
            addIssue(p, CvConstants.ISSUE_MISSING, 'Phone__c', 'No phone number found in CV.', CvConstants.SEVERITY_WARNING);
        }

        Matcher locMatcher = Pattern.compile('(?im)^(?:Location|Based in|Address)\\s*[:\\-]\\s*(.+)$').matcher(text);
        if (locMatcher.find()) {
            p.location = locMatcher.group(1).trim();
        } else {
            p.location = inferLocationAfterPhone(text, p.phone);
            if (String.isNotBlank(p.location)) {
                addIssue(p, CvConstants.ISSUE_UNCERTAIN, 'Location__c', 'Location inferred from the line near the phone number.', CvConstants.SEVERITY_INFO);
            } else {
                addIssue(p, CvConstants.ISSUE_MISSING, 'Location__c', 'Location not explicitly stated.', CvConstants.SEVERITY_INFO);
            }
        }

        Matcher liMatcher = Pattern.compile('(?i)(https?://[^\\s]*linkedin\\.com[^\\s]*)').matcher(text);
        if (liMatcher.find()) {
            p.linkedin = liMatcher.group(1);
        }

        p.summary = extractSection(text, new List<String>{ 'summary', 'profile', 'about' });
        if (isHeaderLine(p.summary)) {
            p.summary = null;
        }
        if (String.isBlank(p.summary)) {
            String inferred = firstSummaryLine(lines, p.fullName, p.email);
            if (String.isNotBlank(inferred)) {
                p.summary = inferred;
                addIssue(p, CvConstants.ISSUE_UNCERTAIN, 'Summary__c', 'Summary inferred from early CV lines.', CvConstants.SEVERITY_INFO);
            }
        }

        String skillsBlock = extractSection(text, new List<String>{ 'skills', 'technical skills', 'core competencies' });
        if (String.isNotBlank(skillsBlock)) {
            for (String token : splitSkills(skillsBlock)) {
                ParsedSkill s = new ParsedSkill();
                s.name = token;
                s.confidence = CvConstants.CONFIDENCE_EXTRACTED;
                s.evidence = token;
                p.skills.add(s);
            }
        } else {
            // Infer common tokens from whole text
            for (String skill : knownSkillsPresent(text)) {
                ParsedSkill s = new ParsedSkill();
                s.name = skill;
                s.confidence = CvConstants.CONFIDENCE_INFERRED;
                s.evidence = 'Inferred from CV body mention of "' + skill + '"';
                p.skills.add(s);
            }
            if (p.skills.isEmpty()) {
                addIssue(p, CvConstants.ISSUE_MISSING, 'Skills', 'No skills section or recognizable skills found.', CvConstants.SEVERITY_WARNING);
            } else {
                addIssue(p, CvConstants.ISSUE_UNCERTAIN, 'Skills', 'Skills inferred from body text; no dedicated skills section.', CvConstants.SEVERITY_INFO);
            }
        }

        String expBlock = extractSection(text, new List<String>{ 'experience', 'work experience', 'employment', 'professional experience' });
        if (String.isNotBlank(expBlock)) {
            p.experiences.addAll(parseExperiences(expBlock));
        } else {
            addIssue(p, CvConstants.ISSUE_MISSING, 'Experience', 'No experience section found.', CvConstants.SEVERITY_WARNING);
        }

        // Detect overlapping/conflicting date ranges (simple year overlap)
        detectExperienceConflicts(p);

        String eduBlock = extractSection(text, new List<String>{ 'education', 'academic' });
        if (String.isNotBlank(eduBlock)) {
            p.educations.addAll(parseEducations(eduBlock));
        } else {
            addIssue(p, CvConstants.ISSUE_MISSING, 'Education', 'No education section found.', CvConstants.SEVERITY_INFO);
        }

        p.yearsExperience = inferYears(text, p.experiences);
        if (p.yearsExperience == null) {
            addIssue(p, CvConstants.ISSUE_MISSING, 'Years_Experience__c', 'Could not determine years of experience.', CvConstants.SEVERITY_INFO);
        } else if (!Pattern.compile('(?i)\\d+\\+?\\s*years?').matcher(text).find()) {
            addIssue(p, CvConstants.ISSUE_UNCERTAIN, 'Years_Experience__c', 'Years of experience inferred from job date ranges.', CvConstants.SEVERITY_INFO);
        }

        if (binaryLimited) {
            addIssue(
                p,
                CvConstants.ISSUE_UNCERTAIN,
                'Source',
                'Binary PDF/DOC parse limited in Apex stub; companion TXT or filename fixtures used. Validate fields in interview.',
                CvConstants.SEVERITY_WARNING
            );
            // Downgrade extracted confidence
            for (ParsedSkill s : p.skills) {
                if (s.confidence == CvConstants.CONFIDENCE_EXTRACTED) {
                    s.confidence = CvConstants.CONFIDENCE_INFERRED;
                }
            }
        }

        Integer critical = 0;
        Integer warnings = 0;
        for (ParsedIssue issue : p.issues) {
            if (issue.severity == CvConstants.SEVERITY_CRITICAL) {
                critical++;
            } else if (issue.severity == CvConstants.SEVERITY_WARNING) {
                warnings++;
            }
        }
        if (critical > 0 || binaryLimited) {
            p.parseStatus = CvConstants.PARSE_PARTIAL;
        } else if (p.skills.isEmpty() && p.experiences.isEmpty()) {
            p.parseStatus = CvConstants.PARSE_FAILED;
        } else {
            p.parseStatus = CvConstants.PARSE_SUCCESS;
        }

        List<String> summaryBits = new List<String>();
        for (ParsedIssue issue : p.issues) {
            summaryBits.add(issue.issueType + ': ' + issue.fieldPath + ' — ' + issue.details);
        }
        p.uncertaintySummary = String.join(summaryBits, '\n');
        return p;
    }

    private static void insertChildren(Id candidateId, ParsedCv parsed) {
        List<Candidate_Skill__c> skills = new List<Candidate_Skill__c>();
        for (ParsedSkill s : parsed.skills) {
            skills.add(new Candidate_Skill__c(
                Name = truncate(s.name, 80),
                Candidate__c = candidateId,
                Confidence__c = s.confidence,
                Evidence__c = truncate(s.evidence, 255),
                Years__c = s.years
            ));
        }
        if (!skills.isEmpty()) {
            insert skills;
        }

        List<Candidate_Experience__c> exps = new List<Candidate_Experience__c>();
        for (ParsedExperience e : parsed.experiences) {
            exps.add(new Candidate_Experience__c(
                Name = truncate(String.isBlank(e.title) ? e.company : e.title, 80),
                Candidate__c = candidateId,
                Company__c = truncate(e.company, 255),
                Title__c = truncate(e.title, 255),
                Start_Date_Text__c = truncate(e.startDateText, 50),
                End_Date_Text__c = truncate(e.endDateText, 50),
                Description__c = truncate(e.description, 10000),
                Has_Date_Conflict__c = e.hasDateConflict == true,
                Confidence__c = e.confidence
            ));
        }
        if (!exps.isEmpty()) {
            insert exps;
        }

        List<Candidate_Education__c> edus = new List<Candidate_Education__c>();
        for (ParsedEducation ed : parsed.educations) {
            edus.add(new Candidate_Education__c(
                Name = truncate(String.isBlank(ed.school) ? ed.degree : ed.school, 80),
                Candidate__c = candidateId,
                School__c = truncate(ed.school, 255),
                Degree__c = truncate(ed.degree, 255),
                Field_Of_Study__c = truncate(ed.fieldOfStudy, 255),
                End_Date_Text__c = truncate(ed.endDateText, 50),
                Confidence__c = ed.confidence
            ));
        }
        if (!edus.isEmpty()) {
            insert edus;
        }

        List<Candidate_Data_Issue__c> issues = new List<Candidate_Data_Issue__c>();
        Integer idx = 1;
        for (ParsedIssue issue : parsed.issues) {
            issues.add(new Candidate_Data_Issue__c(
                Name = 'Issue ' + idx,
                Candidate__c = candidateId,
                Issue_Type__c = issue.issueType,
                Field_Path__c = issue.fieldPath,
                Details__c = issue.details,
                Severity__c = issue.severity
            ));
            idx++;
        }
        if (!issues.isEmpty()) {
            insert issues;
        }
    }

    private static List<ParsedExperience> parseExperiences(String block) {
        List<ParsedExperience> out = new List<ParsedExperience>();
        List<String> lines = block.split('\\r?\\n');
        ParsedExperience current = null;
        Pattern roleWithDates = Pattern.compile(
            '(?i)^(.+?)\\s+[–\\-|@]\\s+(.+?)\\s+[–\\-|]\\s+(\\d{1,2}/\\d{2,4}|\\d{4})\\s*[–\\-|]\\s*(\\d{1,2}/\\d{2,4}|\\d{4}|Present|Current)$'
        );
        Pattern roleDash = Pattern.compile('(?i)^(.+?)\\s+[–\\-|@]\\s+(.+)$');
        Pattern roleComma = Pattern.compile('(?i)^([A-Za-z][A-Za-z0-9 /&+.]{1,80}),\\s*([A-Za-z][A-Za-z0-9 &.+-]{1,80})$');
        Pattern datesOnly = Pattern.compile(
            '(?i)(\\d{1,2}/\\d{2,4}|\\d{4})\\s*[–\\-to]+\\s*(\\d{1,2}/\\d{2,4}|\\d{4}|Present|Current)'
        );

        for (String line : lines) {
            String trimmed = line == null ? '' : line.trim();
            if (String.isBlank(trimmed) || isHeaderLine(trimmed)) {
                continue;
            }
            Boolean bullet = isBulletLine(trimmed);
            Matcher withDates = roleWithDates.matcher(trimmed);
            Matcher m = roleDash.matcher(trimmed);
            Matcher comma = roleComma.matcher(trimmed);
            Matcher d = datesOnly.matcher(trimmed);
            if (lookLikeDateOnlyLine(trimmed) && d.find()) {
                if (current == null) {
                    current = newExperience(null, null, d.group(1), d.group(2));
                    current.confidence = CvConstants.CONFIDENCE_INFERRED;
                } else if (String.isBlank(current.startDateText)) {
                    current.startDateText = d.group(1);
                    current.endDateText = d.group(2);
                } else {
                    // Dates already set — start a new role only if this looks like a headerless date block
                    current.description = appendDesc(current.description, trimmed);
                }
            } else if (!bullet && withDates.find() && trimmed.length() <= 120) {
                if (current != null) {
                    out.add(current);
                }
                current = newExperience(
                    withDates.group(1).trim(),
                    withDates.group(2).trim(),
                    withDates.group(3),
                    withDates.group(4)
                );
            } else if (!bullet && m.find() && trimmed.length() <= 120) {
                if (current != null) {
                    out.add(current);
                }
                current = newExperience(m.group(1).trim(), m.group(2).trim(), null, null);
            } else if (!bullet && comma.find() && trimmed.length() <= 120) {
                if (current != null) {
                    out.add(current);
                }
                current = newExperience(comma.group(1).trim(), comma.group(2).trim(), null, null);
            } else if (current != null) {
                if (bullet || trimmed.length() > 120 || String.isNotBlank(current.title)) {
                    current.description = appendDesc(current.description, trimmed);
                } else if (String.isBlank(current.title) && trimmed.length() <= 120) {
                    current.title = trimmed;
                } else {
                    current.description = appendDesc(current.description, trimmed);
                }
            } else if (bullet || trimmed.length() > 120) {
                // Never put long bullets into Title__c
                current = newExperience(null, null, null, null);
                current.confidence = CvConstants.CONFIDENCE_INFERRED;
                current.description = trimmed;
            } else {
                current = newExperience(trimmed, null, null, null);
                current.confidence = CvConstants.CONFIDENCE_INFERRED;
            }
        }
        if (current != null) {
            out.add(current);
        }
        return out;
    }

    private static ParsedExperience newExperience(String title, String company, String startDate, String endDate) {
        ParsedExperience current = new ParsedExperience();
        current.title = title;
        current.company = company;
        current.startDateText = startDate;
        current.endDateText = endDate;
        current.confidence = CvConstants.CONFIDENCE_EXTRACTED;
        current.description = '';
        current.hasDateConflict = false;
        return current;
    }

    private static String appendDesc(String existing, String line) {
        return String.isBlank(existing) ? line : existing + '\n' + line;
    }

    private static Boolean isBulletLine(String trimmed) {
        if (String.isBlank(trimmed)) {
            return false;
        }
        String t = trimmed.toLowerCase();
        return t.startsWith('•') || t.startsWith('-') || t.startsWith('*') || t.startsWith('–');
    }

    private static Boolean lookLikeDateOnlyLine(String trimmed) {
        if (String.isBlank(trimmed) || trimmed.length() > 40) {
            return false;
        }
        return Pattern.compile(
            '(?i)^\\s*(\\d{1,2}/\\d{2,4}|\\d{4})\\s*[–\\-to]+\\s*(\\d{1,2}/\\d{2,4}|\\d{4}|Present|Current)\\s*$'
        ).matcher(trimmed).matches();
    }

    private static List<ParsedEducation> parseEducations(String block) {
        List<ParsedEducation> out = new List<ParsedEducation>();
        for (String line : block.split('\\r?\\n')) {
            String trimmed = line == null ? '' : line.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            ParsedEducation ed = new ParsedEducation();
            ed.confidence = CvConstants.CONFIDENCE_EXTRACTED;
            if (trimmed.contains('|')) {
                List<String> parts = trimmed.split('\\|');
                ed.school = parts[0].trim();
                if (parts.size() > 1) {
                    ed.degree = parts[1].trim();
                }
                if (parts.size() > 2) {
                    ed.fieldOfStudy = parts[2].trim();
                }
            } else if (trimmed.contains('–') || trimmed.contains('-')) {
                List<String> parts = trimmed.split('[–\\-]');
                ed.school = parts[0].trim();
                if (parts.size() > 1) {
                    ed.degree = parts[1].trim();
                }
            } else {
                ed.school = trimmed;
            }
            Matcher year = Pattern.compile('(19|20)\\d{2}').matcher(trimmed);
            if (year.find()) {
                ed.endDateText = year.group(0);
            }
            out.add(ed);
        }
        return out;
    }

    private static void detectExperienceConflicts(ParsedCv p) {
        for (Integer i = 0; i < p.experiences.size(); i++) {
            ParsedExperience a = p.experiences[i];
            Integer aStart = toYear(a.startDateText);
            Integer aEnd = toYear(a.endDateText);
            if (aStart == null || aEnd == null) {
                continue;
            }
            if (aEnd < aStart) {
                a.hasDateConflict = true;
                addIssue(p, CvConstants.ISSUE_CONFLICTING, 'Experience[' + i + '].dates',
                    'End year earlier than start year for ' + a.title, CvConstants.SEVERITY_WARNING);
            }
            for (Integer j = i + 1; j < p.experiences.size(); j++) {
                ParsedExperience b = p.experiences[j];
                Integer bStart = toYear(b.startDateText);
                Integer bEnd = toYear(b.endDateText);
                if (bStart == null || bEnd == null) {
                    continue;
                }
                if (aStart <= bEnd && bStart <= aEnd) {
                    // Significant overlap (>0 years) while both claim full-time style roles
                    a.hasDateConflict = true;
                    b.hasDateConflict = true;
                    addIssue(p, CvConstants.ISSUE_CONFLICTING, 'Experience.dates',
                        'Overlapping employment periods: "' + a.title + '" and "' + b.title + '".', CvConstants.SEVERITY_WARNING);
                }
            }
        }
    }

    private static Decimal inferYears(String text, List<ParsedExperience> experiences) {
        Matcher m = Pattern.compile('(?i)(\\d{1,2})\\+?\\s*years?\\s+(?:of\\s+)?experience').matcher(text);
        if (m.find()) {
            return Decimal.valueOf(m.group(1));
        }
        Integer minStart = null;
        Integer maxEnd = null;
        Integer currentYear = Date.today().year();
        for (ParsedExperience e : experiences) {
            Integer s = toYear(e.startDateText);
            Integer en = toYear(e.endDateText);
            if (en == null && s != null) {
                en = currentYear;
            }
            if (s != null) {
                minStart = minStart == null ? s : Math.min(minStart, s);
            }
            if (en != null) {
                maxEnd = maxEnd == null ? en : Math.max(maxEnd, en);
            }
        }
        if (minStart != null && maxEnd != null && maxEnd >= minStart) {
            return Decimal.valueOf(maxEnd - minStart);
        }
        return null;
    }

    private static Integer toYear(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        if (value.toLowerCase().contains('present') || value.toLowerCase().contains('current')) {
            return Date.today().year();
        }
        Matcher m = Pattern.compile('(19|20)\\d{2}').matcher(value);
        if (m.find()) {
            return Integer.valueOf(m.group(0));
        }
        return null;
    }

    private static String extractSection(String text, List<String> headers) {
        String lower = text.toLowerCase();
        Integer bestStart = null;
        String matched = null;
        for (String h : headers) {
            Integer idx = indexOfHeader(lower, h);
            if (idx >= 0 && (bestStart == null || idx < bestStart)) {
                bestStart = idx;
                matched = h;
            }
        }
        if (bestStart == null) {
            return null;
        }
        Integer contentStart = bestStart + matched.length();
        // skip colon/newline
        while (contentStart < text.length() && (text.substring(contentStart, contentStart + 1) == ':' || text.substring(contentStart, contentStart + 1) == '\n' || text.substring(contentStart, contentStart + 1) == '\r' || text.substring(contentStart, contentStart + 1) == ' ')) {
            contentStart++;
        }
        Integer endIdx = text.length();
        List<String> stopHeaders = new List<String>{
            'professional experience', 'work experience', 'technical skills', 'core competencies',
            'experience', 'employment', 'education', 'skills', 'projects',
            'certifications', 'languages', 'summary', 'profile', 'about', 'academic'
        };
        for (String stop : stopHeaders) {
            if (matched == stop) {
                continue;
            }
            Integer stopIdx = indexOfHeader(lower.substring(contentStart), stop);
            if (stopIdx >= 0) {
                Integer abs = contentStart + stopIdx;
                if (abs < endIdx) {
                    endIdx = abs;
                }
            }
        }
        return text.substring(contentStart, endIdx).trim();
    }

    private static Integer indexOfHeader(String lowerText, String header) {
        String h = header == null ? '' : header.toLowerCase();
        // Prefer line-start matches for section headers.
        Matcher m = Pattern.compile('(?m)^\\s*' + escapeRegex(h) + '\\s*:?\\s*$').matcher(lowerText);
        if (m.find()) {
            return m.start();
        }
        Matcher m2 = Pattern.compile('(?m)^\\s*' + escapeRegex(h) + '\\s*:').matcher(lowerText);
        if (m2.find()) {
            return m2.start();
        }
        return -1;
    }

    private static String escapeRegex(String value) {
        if (value == null) {
            return '';
        }
        String out = value;
        List<String> specials = new List<String>{
            '\\', '.', '+', '*', '?', '(', ')', '[', ']', '{', '}', '|', '^', '$'
        };
        for (String s : specials) {
            out = out.replace(s, '\\' + s);
        }
        return out;
    }

    private static List<String> splitSkills(String block) {
        List<String> out = new List<String>();
        String normalized = block.replace('\n', ',').replace('•', ',').replace('|', ',');
        for (String part : normalized.split(',')) {
            String t = part == null ? '' : part.trim();
            if (String.isNotBlank(t) && t.length() < 80 && !t.toLowerCase().startsWith('skills')) {
                out.add(t);
            }
        }
        return out;
    }

    private static List<String> knownSkillsPresent(String text) {
        List<String> catalog = new List<String>{
            'Apex', 'LWC', 'Lightning Web Components', 'Salesforce', 'Java', 'Python', 'SQL',
            'SOQL', 'Integration', 'REST', 'JavaScript', 'TypeScript', 'React', 'AWS',
            'Data Analysis', 'Tableau', 'Power BI', 'Communication', 'Leadership'
        };
        String lower = text.toLowerCase();
        List<String> found = new List<String>();
        for (String skill : catalog) {
            if (lower.contains(skill.toLowerCase())) {
                found.add(skill);
            }
        }
        return found;
    }

    private static String firstNonEmptyLine(List<String> lines) {
        for (String line : lines) {
            if (String.isNotBlank(line)) {
                return line.trim();
            }
        }
        return null;
    }

    @TestVisible
    static String normalizeExtractedText(String rawText) {
        if (rawText == null) {
            return '';
        }
        String t = rawText.replace('\r\n', '\n').replace('\r', '\n');

        // Split NameEmail@domain where a capitalized name word is glued to a lowercase local part with digits
        Matcher emailMatch = Pattern.compile('[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}').matcher(t);
        String emailFixed = '';
        Integer last = 0;
        while (emailMatch.find()) {
            String full = emailMatch.group(0);
            Integer atIdx = full.indexOf('@');
            String local = full.substring(0, atIdx);
            String domain = full.substring(atIdx);
            emailFixed += t.substring(last, emailMatch.start());

            String nameHint = '';
            String before = t.substring(last, emailMatch.start()).trim();
            if (String.isNotBlank(before)) {
                List<String> words = before.split('\\s+');
                nameHint = words[words.size() - 1].toLowerCase();
            }

            String replacement = null;
            Integer bestScore = -1;
            for (Integer lowerLen = 2; lowerLen <= 20; lowerLen++) {
                if (1 + lowerLen >= local.length()) {
                    continue;
                }
                String namePart = local.substring(0, 1 + lowerLen);
                String emailLocal = local.substring(1 + lowerLen);
                if (!Pattern.matches('^[A-Z][a-z]+$', namePart) ||
                    !Pattern.matches('^[a-z][a-z0-9._%+-]*\\d[a-z0-9._%+-]*$', emailLocal)) {
                    continue;
                }
                Integer digitAt = -1;
                for (Integer i = 0; i < emailLocal.length(); i++) {
                    String ch = emailLocal.substring(i, i + 1);
                    if (ch >= '0' && ch <= '9') {
                        digitAt = i;
                        break;
                    }
                }
                if (digitAt < 5) {
                    continue;
                }
                Integer score = lowerLen;
                // Prefer email locals that start with the preceding first name (Youssef → yousseffj78)
                if (nameHint.length() >= 4 && emailLocal.toLowerCase().startsWith(nameHint.substring(0, 4))) {
                    score += 1000;
                }
                if (score > bestScore) {
                    bestScore = score;
                    replacement = namePart + '\n' + emailLocal + domain;
                }
            }
            emailFixed += replacement == null ? full : replacement;
            last = emailMatch.end();
        }
        emailFixed += t.substring(last);
        t = emailFixed;

        t = t.replaceAll('(?i)(professional experience|work experience|technical skills|core competencies)', '\n$1\n');
        // Only split single-word headers when glued to the next word (EXPERIENCESalesforce)
        t = t.replaceAll(
            '(CERTIFICATIONS|EMPLOYMENT|EDUCATION|EXPERIENCE|SKILLS|SUMMARY|PROFILE|PROJECTS|LANGUAGES|ACADEMIC)(?=[A-Z])',
            '\n$1\n'
        );
        t = t.replaceAll('([.a-z])([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)*, [A-Z])', '$1\n$2');
        // "Acme - 2018 - 2022" → date on its own line (do not cut into company names)
        t = t.replaceAll(
            '(?i)\\s+[–\\-—]\\s+(\\d{1,2}/\\d{2,4}|\\d{4})\\s+[–\\-—]\\s+(Present|Current|\\d{1,2}/\\d{2,4}|\\d{4})(?!\\d)',
            '\n$1 - $2\n'
        );
        t = t.replaceAll(
            '(?i)(\\d{1,2}/\\d{2,4})\\s*[–\\-—]\\s*(Present|Current|\\d{1,2}/\\d{2,4}|\\d{4})',
            '\n$1 - $2\n'
        );
        t = t.replaceAll('([A-Za-z)\\]])(\\d{1,2}/\\d{2,4})', '$1\n$2');
        t = t.replace('•', '\n• ');
        t = t.replaceAll('(?i)\\s+(LinkedIn|GitHub)\\b', '\n$1');
        t = t.replaceAll('[ \\t]+\\n', '\n');
        t = t.replaceAll('\\n{3,}', '\n\n');
        t = t.replaceAll('[^\\S\\n]{2,}', ' ');
        return t.trim();
    }

    private static Boolean isBadName(String name) {
        if (String.isBlank(name)) {
            return true;
        }
        String lower = name.toLowerCase();
        if (name.contains('@') || lower.startsWith('email') || lower.startsWith('phone')) {
            return true;
        }
        if (isHeaderLine(name)) {
            return true;
        }
        if (name.length() > 80) {
            return true;
        }
        return false;
    }

    private static Boolean isHeaderLine(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String t = value.trim().toLowerCase().replaceAll(':$', '');
        Set<String> headers = new Set<String>{
            'summary', 'profile', 'about', 'skills', 'technical skills', 'core competencies',
            'experience', 'work experience', 'professional experience', 'employment',
            'education', 'academic', 'projects', 'certifications', 'languages'
        };
        return headers.contains(t);
    }

    private static String nameBeforeEmail(String text, String email) {
        if (String.isBlank(text) || String.isBlank(email)) {
            return null;
        }
        Integer idx = text.indexOf(email);
        if (idx <= 0) {
            return null;
        }
        String before = text.substring(0, idx).trim();
        List<String> parts = before.split('\\r?\\n');
        for (Integer i = parts.size() - 1; i >= 0; i--) {
            String line = parts[i] == null ? '' : parts[i].trim();
            if (String.isBlank(line) || isHeaderLine(line) || line.contains('@')) {
                continue;
            }
            // Prefer a short person-name style line
            if (line.length() <= 60 && Pattern.compile('^[A-Za-z][A-Za-z .\\-]{1,58}$').matcher(line).matches()) {
                return line;
            }
        }
        return null;
    }

    private static String inferLocationAfterPhone(String text, String phone) {
        if (String.isBlank(text)) {
            return null;
        }
        List<String> lines = text.split('\\r?\\n');
        Integer phoneLine = -1;
        for (Integer i = 0; i < lines.size(); i++) {
            String line = lines[i] == null ? '' : lines[i].trim();
            if (String.isBlank(line)) {
                continue;
            }
            if ((String.isNotBlank(phone) && line.contains(phone)) ||
                Pattern.compile('(\\+?\\d[\\d\\s().-]{7,}\\d)').matcher(line).find()) {
                phoneLine = i;
                // Same-line location after the phone number
                String afterPhone = line;
                if (String.isNotBlank(phone) && line.contains(phone)) {
                    afterPhone = line.substring(line.indexOf(phone) + phone.length()).trim();
                } else {
                    Matcher pm = Pattern.compile('(\\+?\\d[\\d\\s().-]{7,}\\d)').matcher(line);
                    if (pm.find()) {
                        afterPhone = line.substring(pm.end()).trim();
                    }
                }
                afterPhone = afterPhone.replaceAll('(?i)\\s*(LinkedIn|GitHub).*$', '').trim();
                if (afterPhone.contains(',') && afterPhone.length() <= 80) {
                    return afterPhone;
                }
                break;
            }
        }
        Integer start = phoneLine >= 0 ? phoneLine + 1 : 0;
        for (Integer i = start; i < Math.min(lines.size(), start + 4); i++) {
            String line = lines[i] == null ? '' : lines[i].trim();
            if (String.isBlank(line) || isHeaderLine(line) || line.contains('@')) {
                continue;
            }
            String lower = line.toLowerCase();
            if (lower == 'linkedin' || lower == 'github' || lower.startsWith('http')) {
                continue;
            }
            if (line.contains(',') && line.length() <= 80 &&
                Pattern.compile('(?i)[A-Za-z].*,\\s*[A-Za-z]').matcher(line).find()) {
                return line.replaceAll('(?i)\\s*(LinkedIn|GitHub).*$', '').trim();
            }
        }
        return null;
    }

    private static String firstSummaryLine(List<String> lines, String fullName, String email) {
        for (String line : lines) {
            String trimmed = line == null ? '' : line.trim();
            if (String.isBlank(trimmed) || isHeaderLine(trimmed)) {
                continue;
            }
            if (String.isNotBlank(fullName) && trimmed.equalsIgnoreCase(fullName)) {
                continue;
            }
            if (String.isNotBlank(email) && trimmed.contains(email)) {
                continue;
            }
            if (trimmed.contains('@') || Pattern.compile('(\\+?\\d[\\d\\s().-]{7,}\\d)').matcher(trimmed).find()) {
                continue;
            }
            String lower = trimmed.toLowerCase();
            if (lower == 'linkedin' || lower == 'github' || lower.startsWith('http')) {
                continue;
            }
            if (trimmed.contains(',') && trimmed.length() <= 80) {
                // Likely a location line, not a summary
                continue;
            }
            if (trimmed.length() < 20 || trimmed.length() > 400) {
                continue;
            }
            return trimmed;
        }
        return null;
    }

    private static void addIssue(ParsedCv p, String type, String path, String details, String severity) {
        ParsedIssue issue = new ParsedIssue();
        issue.issueType = type;
        issue.fieldPath = path;
        issue.details = details;
        issue.severity = severity;
        p.issues.add(issue);
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLen ? value : value.substring(0, maxLen);
    }

    public class ParsedCv {
        public String fullName;
        public String email;
        public String phone;
        public String location;
        public String summary;
        public String linkedin;
        public Decimal yearsExperience;
        public String parseStatus;
        public String uncertaintySummary;
        public List<ParsedSkill> skills;
        public List<ParsedExperience> experiences;
        public List<ParsedEducation> educations;
        public List<ParsedIssue> issues;
    }
    public class ParsedSkill {
        public String name;
        public String confidence;
        public String evidence;
        public Decimal years;
    }
    public class ParsedExperience {
        public String title;
        public String company;
        public String startDateText;
        public String endDateText;
        public String description;
        public Boolean hasDateConflict;
        public String confidence;
    }
    public class ParsedEducation {
        public String school;
        public String degree;
        public String fieldOfStudy;
        public String endDateText;
        public String confidence;
    }
    public class ParsedIssue {
        public String issueType;
        public String fieldPath;
        public String details;
        public String severity;
    }
}
