/**
 * Primary invocable entry for Agentforce. Set `operation` to one of:
 * listCandidates | getCandidateCard | listDataIssues | searchCandidateFacts |
 * scoreForRole | compareCandidates | bookmarkCandidate
 *
 * Grounding rule: return only facts stored on Candidate Cards; if unknown, say so.
 */
public with sharing class CvAgentActions {
    public class ActionRequest {
        @InvocableVariable(required=true label='Operation' description='listCandidates, getCandidateCard, listDataIssues, searchCandidateFacts, scoreForRole, compareCandidates, bookmarkCandidate')
        public String operation;

        @InvocableVariable(label='Candidate Id')
        public String candidateId;

        @InvocableVariable(label='Candidate Ids CSV' description='Comma-separated Candidate Ids')
        public String candidateIdsCsv;

        @InvocableVariable(label='Role Title')
        public String roleTitle;

        @InvocableVariable(label='Required Skills CSV')
        public String requiredSkillsCsv;

        @InvocableVariable(label='Minimum Years')
        public Integer minYears;

        @InvocableVariable(label='Education Keywords CSV')
        public String educationKeywordsCsv;

        @InvocableVariable(label='Search Query' description='Question to answer using CV-backed fields only')
        public String searchQuery;

        @InvocableVariable(label='Recruiter Notes')
        public String recruiterNotes;

        @InvocableVariable(label='Evaluation Score')
        public Decimal evaluationScore;

        @InvocableVariable(label='Evaluation Reasoning')
        public String evaluationReasoning;
    }

    public class ActionResponse {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Payload JSON')
        public String payloadJson;
        @InvocableVariable(label='Record Id')
        public String recordId;
    }

    @InvocableMethod(
        label='CV Review Agent Action'
        description='Grounded CV operations for recruiters. Operations: listCandidates, getCandidateCard, listDataIssues, searchCandidateFacts, scoreForRole, compareCandidates, bookmarkCandidate. Never invent CV facts; cite Candidate Card fields only.'
    )
    public static List<ActionResponse> execute(List<ActionRequest> requests) {
        List<ActionResponse> responses = new List<ActionResponse>();
        for (ActionRequest req : requests) {
            responses.add(dispatch(req));
        }
        return responses;
    }

    @TestVisible
    static ActionResponse dispatch(ActionRequest req) {
        ActionResponse res = new ActionResponse();
        String op = req == null || req.operation == null ? '' : req.operation.trim().toLowerCase();
        try {
            if (op == 'listcandidates') {
                return listCandidates(req);
            }
            if (op == 'getcandidatecard') {
                return getCandidateCard(req);
            }
            if (op == 'listdataissues') {
                return listDataIssues(req);
            }
            if (op == 'searchcandidatefacts') {
                return searchCandidateFacts(req);
            }
            if (op == 'scoreforrole') {
                return scoreForRole(req);
            }
            if (op == 'comparecandidates') {
                return compareCandidates(req);
            }
            if (op == 'bookmarkcandidate') {
                return bookmarkCandidate(req);
            }
            res.success = false;
            res.message = 'Unknown operation "' + req.operation + '". Use listCandidates, getCandidateCard, listDataIssues, searchCandidateFacts, scoreForRole, compareCandidates, or bookmarkCandidate.';
            CvAuditService.log('unknown', JSON.serialize(req), res.message, new List<Id>(), null, req.roleTitle, false);
            return res;
        } catch (Exception e) {
            res.success = false;
            res.message = 'Action failed: ' + e.getMessage();
            CvAuditService.log(op, JSON.serialize(req), res.message, parseIds(req), null, req.roleTitle, false);
            return res;
        }
    }

    private static ActionResponse listCandidates(ActionRequest req) {
        List<Candidate__c> rows = [
            SELECT Id, Name, Email__c, Location__c, Years_Experience__c, Parse_Status__c,
                   Uncertainty_Summary__c, Source_File_Name__c, CreatedDate
            FROM Candidate__c
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        List<Map<String, Object>> payload = new List<Map<String, Object>>();
        List<String> lines = new List<String>();
        for (Candidate__c c : rows) {
            payload.add(new Map<String, Object>{
                'id' => c.Id,
                'name' => c.Name,
                'email' => c.Email__c,
                'location' => c.Location__c,
                'yearsExperience' => c.Years_Experience__c,
                'parseStatus' => c.Parse_Status__c,
                'sourceFile' => c.Source_File_Name__c
            });
            lines.add(c.Name + ' (' + c.Id + ') — parse=' + c.Parse_Status__c + ', years=' + c.Years_Experience__c);
        }
        ActionResponse res = ok('Found ' + rows.size() + ' candidate card(s).\n' + String.join(lines, '\n'), JSON.serialize(payload), null);
        CvAuditService.log('listCandidates', JSON.serialize(req), res.payloadJson, new List<Id>(), null, req.roleTitle, true);
        return res;
    }

    private static ActionResponse getCandidateCard(ActionRequest req) {
        Id candidateId = requireCandidateId(req);
        Candidate__c c = loadCard(candidateId);
        Map<String, Object> payload = cardToMap(c);
        List<String> skillNames = new List<String>();
        for (Candidate_Skill__c s : c.Skills__r) {
            if (String.isNotBlank(s.Name) && s.Name.length() >= 2) {
                skillNames.add(s.Name);
            }
        }
        List<String> roleLines = new List<String>();
        for (Candidate_Experience__c e : c.Experiences__r) {
            if (String.isBlank(e.Title__c) && String.isBlank(e.Company__c)) {
                continue;
            }
            roleLines.add(nullSafe(e.Title__c) + ' @ ' + nullSafe(e.Company__c));
        }
        String message =
            'Candidate Card for ' + c.Name + ' (' + c.Id + ')\n' +
            'Email: ' + nullSafe(c.Email__c) + '\n' +
            'Phone: ' + nullSafe(c.Phone__c) + '\n' +
            'Location: ' + nullSafe(c.Location__c) + '\n' +
            'Years: ' + nullSafe(String.valueOf(c.Years_Experience__c)) + '\n' +
            'Parse Status: ' + nullSafe(c.Parse_Status__c) + '\n' +
            'Skills (' + skillNames.size() + '): ' +
            (skillNames.isEmpty() ? 'none' : String.join(skillNames, ', ')) + '\n' +
            'Roles (' + roleLines.size() + '): ' +
            (roleLines.isEmpty() ? 'none' : String.join(roleLines, '; ')) + '\n' +
            'Educations: ' + c.Educations__r.size() + ', Issues: ' + c.Data_Issues__r.size() + '\n' +
            'Uncertainty: ' + nullSafe(c.Uncertainty_Summary__c);
        ActionResponse res = ok(message, JSON.serialize(payload), c.Id);
        CvAuditService.log('getCandidateCard', JSON.serialize(req), res.payloadJson, new List<Id>{ c.Id }, null, req.roleTitle, true);
        return res;
    }

    private static ActionResponse listDataIssues(ActionRequest req) {
        Id candidateId = requireCandidateId(req);
        List<Candidate_Data_Issue__c> issues = [
            SELECT Issue_Type__c, Field_Path__c, Details__c, Severity__c
            FROM Candidate_Data_Issue__c
            WHERE Candidate__c = :candidateId
            ORDER BY Severity__c DESC
        ];
        List<String> lines = new List<String>();
        for (Candidate_Data_Issue__c issue : issues) {
            lines.add('[' + issue.Issue_Type__c + '/' + issue.Severity__c + '] ' + issue.Field_Path__c + ': ' + issue.Details__c);
        }
        String message = issues.isEmpty()
            ? 'No data issues recorded for candidate ' + candidateId + '.'
            : 'Data issues for ' + candidateId + ':\n' + String.join(lines, '\n');
        ActionResponse res = ok(message, JSON.serialize(issues), candidateId);
        CvAuditService.log('listDataIssues', JSON.serialize(req), res.payloadJson, new List<Id>{ candidateId }, null, req.roleTitle, true);
        return res;
    }

    private static ActionResponse searchCandidateFacts(ActionRequest req) {
        if (String.isBlank(req.searchQuery)) {
            return fail('searchQuery is required. Ask only from stored Candidate Card fields.');
        }
        String q = req.searchQuery.toLowerCase();
        List<Id> ids = parseIds(req);
        if (ids.isEmpty() && String.isNotBlank(req.candidateId)) {
            ids.add(Id.valueOf(req.candidateId));
        }
        List<Candidate__c> cards;
        if (ids.isEmpty()) {
            cards = [
                SELECT Id, Name, Email__c, Phone__c, Location__c, Summary__c, Years_Experience__c,
                       Uncertainty_Summary__c, Raw_CV_Text__c,
                       (SELECT Name, Confidence__c, Evidence__c FROM Skills__r),
                       (SELECT Title__c, Company__c, Description__c, Start_Date_Text__c, End_Date_Text__c FROM Experiences__r),
                       (SELECT School__c, Degree__c, Field_Of_Study__c FROM Educations__r)
                FROM Candidate__c
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } else {
            cards = [
                SELECT Id, Name, Email__c, Phone__c, Location__c, Summary__c, Years_Experience__c,
                       Uncertainty_Summary__c, Raw_CV_Text__c,
                       (SELECT Name, Confidence__c, Evidence__c FROM Skills__r),
                       (SELECT Title__c, Company__c, Description__c, Start_Date_Text__c, End_Date_Text__c FROM Experiences__r),
                       (SELECT School__c, Degree__c, Field_Of_Study__c FROM Educations__r)
                FROM Candidate__c
                WHERE Id IN :ids
            ];
        }

        List<Map<String, Object>> hits = new List<Map<String, Object>>();
        List<String> lines = new List<String>();
        for (Candidate__c c : cards) {
            List<String> evidence = new List<String>();
            collectEvidence(evidence, 'email', c.Email__c, q);
            collectEvidence(evidence, 'phone', c.Phone__c, q);
            collectEvidence(evidence, 'location', c.Location__c, q);
            collectEvidence(evidence, 'summary', c.Summary__c, q);
            collectEvidence(evidence, 'yearsExperience', String.valueOf(c.Years_Experience__c), q);
            for (Candidate_Skill__c s : c.Skills__r) {
                if (matches(q, s.Name) || matches(q, 'skill')) {
                    evidence.add('skill:' + s.Name + ' (' + s.Confidence__c + ') evidence=' + s.Evidence__c);
                }
            }
            for (Candidate_Experience__c e : c.Experiences__r) {
                String expText = e.Title__c + ' ' + e.Company__c + ' ' + e.Description__c;
                if (matches(q, expText) || matches(q, 'experience') || matches(q, 'work')) {
                    evidence.add('experience:' + e.Title__c + ' @ ' + e.Company__c + ' (' + e.Start_Date_Text__c + '-' + e.End_Date_Text__c + ')');
                }
            }
            for (Candidate_Education__c ed : c.Educations__r) {
                String eduText = ed.School__c + ' ' + ed.Degree__c + ' ' + ed.Field_Of_Study__c;
                if (matches(q, eduText) || matches(q, 'education') || matches(q, 'degree')) {
                    evidence.add('education:' + ed.Degree__c + ' | ' + ed.School__c);
                }
            }
            // Keyword scan of raw text only as evidence pointer, not free invention
            if (evidence.isEmpty() && String.isNotBlank(c.Raw_CV_Text__c) && rawContainsAny(c.Raw_CV_Text__c, q)) {
                evidence.add('rawCvText: query terms appear in stored raw CV text; no structured field matched. Quote only what is present.');
            }
            if (!evidence.isEmpty()) {
                hits.add(new Map<String, Object>{ 'candidateId' => c.Id, 'name' => c.Name, 'evidence' => evidence });
                lines.add(c.Name + ' (' + c.Id + '): ' + String.join(evidence, ' | '));
            }
        }

        String message;
        if (hits.isEmpty()) {
            message = 'Not found in stored Candidate Card data for query "' + req.searchQuery +
                '". Do not invent an answer. Suggest clarifying with the candidate in an interview.';
        } else {
            message = 'Grounded evidence for "' + req.searchQuery + '":\n' + String.join(lines, '\n');
        }
        ActionResponse res = ok(message, JSON.serialize(hits), null);
        CvAuditService.log('searchCandidateFacts', JSON.serialize(req), res.payloadJson, ids, null, req.roleTitle, true);
        return res;
    }

    private static ActionResponse scoreForRole(ActionRequest req) {
        Id candidateId = requireCandidateId(req);
        CvScoringService.ScoreRequest scoreReq = toScoreRequest(req, candidateId);
        CvScoringService.ScoreResult score = CvScoringService.score(scoreReq);
        String message = buildScoreMessage(score);
        ActionResponse res = ok(message, JSON.serialize(score), candidateId);
        CvAuditService.log('scoreForRole', JSON.serialize(req), res.payloadJson, new List<Id>{ candidateId }, score.breakdownJson, req.roleTitle, true);
        return res;
    }

    private static ActionResponse compareCandidates(ActionRequest req) {
        List<Id> ids = parseIds(req);
        if (ids.size() < 2) {
            return fail('compareCandidates requires at least two Ids in candidateIdsCsv.');
        }
        CvScoringService.ScoreRequest base = toScoreRequest(req, ids[0]);
        List<CvScoringService.ScoreResult> ranked = CvScoringService.compare(ids, base);
        List<String> lines = new List<String>();
        for (Integer i = 0; i < ranked.size(); i++) {
            CvScoringService.ScoreResult s = ranked[i];
            lines.add((i + 1) + '. ' + s.candidateName + ' (' + s.candidateId + ') score=' + s.totalScore +
                (s.strongMatch ? ' STRONG' : ' best-available') + ' — ' + s.reasoning);
            if (!s.tradeOffs.isEmpty()) {
                lines.add('   Trade-offs: ' + String.join(s.tradeOffs, '; '));
            }
            if (!s.interviewGaps.isEmpty()) {
                lines.add('   Interview gaps: ' + String.join(s.interviewGaps, '; '));
            }
        }
        CvScoringService.ScoreResult top = ranked[0];
        String recommendation = 'Recommendation: ' + top.candidateName + ' with score ' + top.totalScore +
            '. Explainability is included per candidate. If no strong match, treat as best available and validate interview gaps.';
        ActionResponse res = ok(recommendation + '\n' + String.join(lines, '\n'), JSON.serialize(ranked), top.candidateId);
        CvAuditService.log('compareCandidates', JSON.serialize(req), res.payloadJson, ids, top.breakdownJson, req.roleTitle, true);
        return res;
    }

    private static ActionResponse bookmarkCandidate(ActionRequest req) {
        Id candidateId = requireCandidateId(req);
        Candidate__c c = loadCard(candidateId);

        Decimal scoreVal = req.evaluationScore;
        String reasoning = req.evaluationReasoning;
        String breakdown = null;
        if (scoreVal == null || String.isBlank(reasoning)) {
            CvScoringService.ScoreRequest scoreReq = toScoreRequest(req, candidateId);
            if (String.isBlank(scoreReq.roleTitle)) {
                scoreReq.roleTitle = 'General role';
            }
            CvScoringService.ScoreResult score = CvScoringService.score(scoreReq);
            if (scoreVal == null) {
                scoreVal = score.totalScore;
            }
            if (String.isBlank(reasoning)) {
                reasoning = score.reasoning + ' Strengths: ' + String.join(score.strengths, '; ') +
                    ' Concerns: ' + String.join(score.concerns, '; ');
            }
            breakdown = score.breakdownJson;
        }

        String overview =
            c.Name + ' | ' + nullSafe(c.Email__c) + ' | ' + nullSafe(c.Location__c) +
            ' | years=' + nullSafe(String.valueOf(c.Years_Experience__c)) +
            ' | skills=' + skillNames(c);

        Candidate_Bookmark__c bm = new Candidate_Bookmark__c();
        bm.Candidate__c = candidateId;
        bm.Candidate_Overview__c = overview;
        bm.Evaluation_Score__c = scoreVal;
        bm.Evaluation_Reasoning__c = reasoning;
        bm.Role_Context__c = req.roleTitle;
        bm.Recruiter_Notes__c = req.recruiterNotes;
        bm.Score_Breakdown_JSON__c = breakdown;
        insert bm;

        ActionResponse res = ok(
            'Bookmarked ' + c.Name + ' as ' + bm.Id + ' for role "' + nullSafe(req.roleTitle) +
            '" with score ' + scoreVal + '. Notes: ' + nullSafe(req.recruiterNotes),
            JSON.serialize(bm),
            bm.Id
        );
        CvAuditService.log('bookmarkCandidate', JSON.serialize(req), res.payloadJson, new List<Id>{ candidateId }, breakdown, req.roleTitle, true);
        return res;
    }

    private static CvScoringService.ScoreRequest toScoreRequest(ActionRequest req, Id candidateId) {
        CvScoringService.ScoreRequest scoreReq = new CvScoringService.ScoreRequest();
        scoreReq.candidateId = candidateId;
        scoreReq.roleTitle = req.roleTitle;
        scoreReq.requiredSkills = splitCsv(req.requiredSkillsCsv);
        scoreReq.minYears = req.minYears;
        scoreReq.preferredEducationKeywords = splitCsv(req.educationKeywordsCsv);
        return scoreReq;
    }

    private static String buildScoreMessage(CvScoringService.ScoreResult score) {
        return score.reasoning +
            '\nStrengths: ' + String.join(score.strengths, '; ') +
            '\nConcerns: ' + String.join(score.concerns, '; ') +
            '\nTrade-offs: ' + String.join(score.tradeOffs, '; ') +
            '\nInterview gaps: ' + String.join(score.interviewGaps, '; ') +
            '\nStrong match: ' + score.strongMatch +
            '\nBreakdown JSON available in payload.';
    }

    private static Candidate__c loadCard(Id candidateId) {
        return [
            SELECT Id, Name, Email__c, Phone__c, Location__c, Summary__c, Years_Experience__c,
                   Parse_Status__c, Uncertainty_Summary__c, Source_File_Name__c, LinkedIn_URL__c, Raw_CV_Text__c,
                   (SELECT Name, Confidence__c, Evidence__c, Years__c FROM Skills__r),
                   (SELECT Name, Company__c, Title__c, Start_Date_Text__c, End_Date_Text__c, Description__c,
                           Has_Date_Conflict__c, Confidence__c FROM Experiences__r),
                   (SELECT Name, School__c, Degree__c, Field_Of_Study__c, End_Date_Text__c, Confidence__c FROM Educations__r),
                   (SELECT Issue_Type__c, Field_Path__c, Details__c, Severity__c FROM Data_Issues__r)
            FROM Candidate__c
            WHERE Id = :candidateId
            LIMIT 1
        ];
    }

    private static Map<String, Object> cardToMap(Candidate__c c) {
        return new Map<String, Object>{
            'id' => c.Id,
            'name' => c.Name,
            'email' => c.Email__c,
            'phone' => c.Phone__c,
            'location' => c.Location__c,
            'summary' => c.Summary__c,
            'yearsExperience' => c.Years_Experience__c,
            'parseStatus' => c.Parse_Status__c,
            'uncertaintySummary' => c.Uncertainty_Summary__c,
            'skills' => c.Skills__r,
            'experiences' => c.Experiences__r,
            'educations' => c.Educations__r,
            'dataIssues' => c.Data_Issues__r
        };
    }

    private static Id requireCandidateId(ActionRequest req) {
        if (String.isBlank(req.candidateId)) {
            throw new CvAgentException('candidateId is required for this operation.');
        }
        return Id.valueOf(req.candidateId);
    }

    public class CvAgentException extends Exception {
    }

    private static List<Id> parseIds(ActionRequest req) {
        List<Id> ids = new List<Id>();
        if (req == null) {
            return ids;
        }
        if (String.isNotBlank(req.candidateIdsCsv)) {
            for (String part : req.candidateIdsCsv.split(',')) {
                String t = part.trim();
                if (String.isNotBlank(t)) {
                    ids.add(Id.valueOf(t));
                }
            }
        }
        return ids;
    }

    private static List<String> splitCsv(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) {
            return out;
        }
        for (String part : csv.split(',')) {
            if (String.isNotBlank(part)) {
                out.add(part.trim());
            }
        }
        return out;
    }

    private static void collectEvidence(List<String> evidence, String field, String value, String q) {
        if (String.isBlank(value)) {
            return;
        }
        if (matches(q, field) || matches(q, value)) {
            evidence.add(field + '=' + value);
        }
    }

    private static Boolean matches(String q, String value) {
        if (String.isBlank(q) || String.isBlank(value)) {
            return false;
        }
        String lv = value.toLowerCase();
        for (String token : q.split('[\\s,?;]+')) {
            if (token.length() >= 3 && lv.contains(token)) {
                return true;
            }
        }
        return lv.contains(q);
    }

    private static Boolean rawContainsAny(String raw, String q) {
        String lr = raw.toLowerCase();
        for (String token : q.split('[\\s,?;]+')) {
            if (token.length() >= 4 && lr.contains(token)) {
                return true;
            }
        }
        return false;
    }

    private static String skillNames(Candidate__c c) {
        List<String> names = new List<String>();
        for (Candidate_Skill__c s : c.Skills__r) {
            names.add(s.Name);
        }
        return String.join(names, ', ');
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? '(not in CV)' : value;
    }

    private static ActionResponse ok(String message, String payload, String recordId) {
        ActionResponse res = new ActionResponse();
        res.success = true;
        res.message = message;
        res.payloadJson = payload;
        res.recordId = recordId;
        return res;
    }

    private static ActionResponse fail(String message) {
        ActionResponse res = new ActionResponse();
        res.success = false;
        res.message = message;
        return res;
    }
}
