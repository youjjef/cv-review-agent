/**
 * In-app chat entry for the CV Review Agent: opens Agentforce ACC when available
 * and routes grounded recruiter utterances through CvAgentActions.
 */
public with sharing class CvAgentChatController {
    public class ChatReply {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String payloadJson;
        @AuraEnabled public String recordId;
        @AuraEnabled public String operation;
        @AuraEnabled public String botId;
    }

    @AuraEnabled(cacheable=true)
    public static String getAgentBotId() {
        List<BotDefinition> bots = [
            SELECT Id
            FROM BotDefinition
            WHERE DeveloperName = 'CV_Review_Agent'
            LIMIT 1
        ];
        return bots.isEmpty() ? null : bots[0].Id;
    }

    @AuraEnabled
    public static ChatReply ask(String utterance, String preferredCandidateId) {
        ChatReply reply = new ChatReply();
        reply.botId = getAgentBotId();
        String text = utterance == null ? '' : utterance.trim();
        if (String.isBlank(text)) {
            reply.success = false;
            reply.message = 'Type a question about candidates, or use a quick action.';
            return reply;
        }

        CvAgentActions.ActionRequest req = routeUtterance(text, preferredCandidateId);
        reply.operation = req.operation;
        List<CvAgentActions.ActionResponse> results = CvAgentActions.execute(
            new List<CvAgentActions.ActionRequest>{ req }
        );
        CvAgentActions.ActionResponse res = results[0];
        reply.success = res.success;
        reply.payloadJson = res.payloadJson;
        reply.recordId = res.recordId;
        Integer topN = extractTopN(text.toLowerCase());
        reply.message = res.success == true
            ? formatRecruiterAnswer(req.operation, res.message, res.payloadJson, topN)
            : res.message;
        return reply;
    }

    @TestVisible
    static String formatRecruiterAnswer(String operation, String baseMessage, String payloadJson) {
        return formatRecruiterAnswer(operation, baseMessage, payloadJson, null);
    }

    @TestVisible
    static String formatRecruiterAnswer(String operation, String baseMessage, String payloadJson, Integer topN) {
        String op = operation == null ? '' : operation.toLowerCase();
        String base = String.isBlank(baseMessage) ? '' : baseMessage.trim();
        if (String.isBlank(payloadJson)) {
            return base;
        }
        try {
            Object raw = JSON.deserializeUntyped(payloadJson);
            if (op == 'getcandidatecard' && raw instanceof Map<String, Object>) {
                return formatCandidateCard((Map<String, Object>) raw, base);
            }
            if (op == 'searchcandidatefacts' && raw instanceof List<Object>) {
                return formatSearchHits((List<Object>) raw, base);
            }
            if (op == 'scoreforrole' && raw instanceof Map<String, Object>) {
                return formatScore((Map<String, Object>) raw, base);
            }
            if (op == 'comparecandidates' && raw instanceof List<Object>) {
                return formatCompare((List<Object>) raw, base, topN);
            }
            if (op == 'listdataissues' && raw instanceof List<Object>) {
                return formatDataIssues((List<Object>) raw, base);
            }
            if (op == 'listcandidates') {
                return base;
            }
            if (op == 'bookmarkcandidate' && raw instanceof Map<String, Object>) {
                return formatBookmark((Map<String, Object>) raw, base);
            }
        } catch (Exception e) {
            return base;
        }
        return base;
    }

    private static String formatCandidateCard(Map<String, Object> card, String base) {
        List<String> lines = new List<String>();
        String name = str(card, 'name');
        lines.add(String.isBlank(base) ? ('Candidate Card for ' + name) : base);
        lines.add('');
        String summary = str(card, 'summary');
        if (String.isNotBlank(summary)) {
            lines.add('Summary: ' + summary);
            lines.add('');
        }
        lines.add('Skills:');
        List<Object> skills = (List<Object>) card.get('skills');
        Integer skillCount = 0;
        if (skills != null) {
            for (Object row : skills) {
                Map<String, Object> s = asMap(row);
                if (s == null) {
                    continue;
                }
                String skillName = str(s, 'Name');
                if (String.isBlank(skillName) || skillName.length() < 2) {
                    continue;
                }
                skillCount++;
                String conf = str(s, 'Confidence__c');
                String evidence = str(s, 'Evidence__c');
                lines.add(
                    '- ' +
                    skillName +
                    (String.isBlank(conf) ? '' : ' (' + conf + ')') +
                    (String.isBlank(evidence) || evidence == skillName ? '' : ' — ' + evidence)
                );
            }
        }
        if (skillCount == 0) {
            lines.add('- None on card');
        }
        lines.add('');
        lines.add('Experience:');
        List<Object> exps = (List<Object>) card.get('experiences');
        Integer expCount = 0;
        if (exps != null) {
            for (Object row : exps) {
                Map<String, Object> e = asMap(row);
                if (e == null) {
                    continue;
                }
                String title = str(e, 'Title__c');
                String company = str(e, 'Company__c');
                if (String.isBlank(title) && String.isBlank(company)) {
                    continue;
                }
                if (title.length() < 2 && company.length() < 2) {
                    continue;
                }
                expCount++;
                lines.add(
                    '- ' +
                    title +
                    ' @ ' +
                    company +
                    ' (' +
                    str(e, 'Start_Date_Text__c') +
                    ' – ' +
                    str(e, 'End_Date_Text__c') +
                    ')'
                );
                String description = str(e, 'Description__c');
                if (String.isNotBlank(description)) {
                    lines.add('  ' + description.replace('\n', '\n  '));
                }
            }
        }
        if (expCount == 0) {
            lines.add('- None on card');
        }
        lines.add('');
        lines.add('Education:');
        List<Object> edus = (List<Object>) card.get('educations');
        Integer eduCount = 0;
        if (edus != null) {
            for (Object row : edus) {
                Map<String, Object> ed = asMap(row);
                if (ed == null) {
                    continue;
                }
                String school = str(ed, 'School__c');
                String degree = str(ed, 'Degree__c');
                if (String.isBlank(school) && String.isBlank(degree)) {
                    continue;
                }
                eduCount++;
                lines.add(
                    '- ' +
                    school +
                    ' | ' +
                    degree +
                    ' | ' +
                    str(ed, 'Field_Of_Study__c') +
                    ' (' +
                    str(ed, 'End_Date_Text__c') +
                    ')'
                );
            }
        }
        if (eduCount == 0) {
            lines.add('- None on card');
        }
        List<Object> issues = (List<Object>) card.get('dataIssues');
        if (issues != null && !issues.isEmpty()) {
            lines.add('');
            lines.add('Data issues:');
            for (Object row : issues) {
                Map<String, Object> issue = asMap(row);
                if (issue == null) {
                    continue;
                }
                lines.add(
                    '- [' +
                    str(issue, 'Issue_Type__c') +
                    '/' +
                    str(issue, 'Severity__c') +
                    '] ' +
                    str(issue, 'Field_Path__c') +
                    ': ' +
                    str(issue, 'Details__c')
                );
            }
        }
        return String.join(lines, '\n');
    }

    private static String formatSearchHits(List<Object> hits, String base) {
        List<String> lines = new List<String>();
        lines.add(String.isBlank(base) ? 'Grounded evidence:' : base);
        for (Object row : hits) {
            Map<String, Object> hit = asMap(row);
            if (hit == null) {
                continue;
            }
            lines.add('');
            lines.add(str(hit, 'name') + ' (' + str(hit, 'candidateId') + ')');
            Object evidenceObj = hit.get('evidence');
            if (evidenceObj instanceof List<Object>) {
                for (Object ev : (List<Object>) evidenceObj) {
                    lines.add('- ' + String.valueOf(ev));
                }
            }
        }
        return String.join(lines, '\n');
    }

    private static String formatScore(Map<String, Object> score, String base) {
        List<String> lines = new List<String>();
        lines.add(String.isBlank(base) ? 'Score result' : base);
        lines.add('');
        lines.add('Candidate: ' + str(score, 'candidateName') + ' (' + str(score, 'candidateId') + ')');
        lines.add('Total: ' + str(score, 'totalScore'));
        lines.add(
            'Breakdown — Skills: ' +
            str(score, 'skillsScore') +
            ', Experience: ' +
            str(score, 'experienceScore') +
            ', Education: ' +
            str(score, 'educationScore') +
            ', Completeness: ' +
            str(score, 'completenessScore')
        );
        lines.add('Strong match: ' + str(score, 'strongMatch'));
        appendStringList(lines, 'Strengths', score.get('strengths'));
        appendStringList(lines, 'Concerns', score.get('concerns'));
        appendStringList(lines, 'Trade-offs', score.get('tradeOffs'));
        appendStringList(lines, 'Interview gaps', score.get('interviewGaps'));
        return String.join(lines, '\n');
    }

    private static String formatCompare(List<Object> ranked, String base, Integer topN) {
        List<String> lines = new List<String>();
        Integer showCount = ranked == null ? 0 : ranked.size();
        if (topN != null && topN > 0 && topN < showCount) {
            showCount = topN;
        }
        if (showCount > 0) {
            Map<String, Object> top = asMap(ranked[0]);
            if (top != null) {
                String header = topN != null && topN > 0
                    ? ('Top ' + showCount + ' for this role — lead: ')
                    : 'Recommendation: ';
                lines.add(
                    header +
                    str(top, 'candidateName') +
                    ' with score ' +
                    str(top, 'totalScore') +
                    (str(top, 'strongMatch') == 'true' ? ' (strong match).' : ' (best available).')
                );
            }
        } else if (String.isNotBlank(base)) {
            lines.add(base);
        } else {
            lines.add('Comparison');
        }
        Integer i = 1;
        for (Integer rowIdx = 0; rowIdx < showCount; rowIdx++) {
            Map<String, Object> score = asMap(ranked[rowIdx]);
            if (score == null) {
                continue;
            }
            lines.add('');
            lines.add(
                i +
                '. ' +
                str(score, 'candidateName') +
                ' — total ' +
                str(score, 'totalScore') +
                (str(score, 'strongMatch') == 'true' ? ' (strong match)' : ' (best available)')
            );
            lines.add(
                '   Breakdown — Skills: ' +
                str(score, 'skillsScore') +
                ', Experience: ' +
                str(score, 'experienceScore') +
                ', Education: ' +
                str(score, 'educationScore') +
                ', Completeness: ' +
                str(score, 'completenessScore')
            );
            String reasoning = str(score, 'reasoning');
            if (String.isNotBlank(reasoning)) {
                lines.add('   Reasoning: ' + reasoning);
            }
            appendStringList(lines, '   Strengths', score.get('strengths'));
            appendStringList(lines, '   Concerns', score.get('concerns'));
            appendStringList(lines, '   Trade-offs', score.get('tradeOffs'));
            appendStringList(lines, '   Interview gaps', score.get('interviewGaps'));
            i++;
        }
        return String.join(lines, '\n');
    }

    private static String formatDataIssues(List<Object> issues, String base) {
        if (issues == null || issues.isEmpty()) {
            return base;
        }
        // Base message already lists issues; if empty details fell through, rebuild.
        if (String.isNotBlank(base) && base.contains('[')) {
            return base;
        }
        List<String> lines = new List<String>{ base, '' };
        for (Object row : issues) {
            Map<String, Object> issue = asMap(row);
            if (issue == null) {
                continue;
            }
            lines.add(
                '- [' +
                str(issue, 'Issue_Type__c') +
                '/' +
                str(issue, 'Severity__c') +
                '] ' +
                str(issue, 'Field_Path__c') +
                ': ' +
                str(issue, 'Details__c')
            );
        }
        return String.join(lines, '\n');
    }

    private static String formatBookmark(Map<String, Object> bm, String base) {
        List<String> lines = new List<String>();
        lines.add(String.isBlank(base) ? 'Bookmark created' : base);
        String overview = str(bm, 'Candidate_Overview__c');
        String reasoning = str(bm, 'Evaluation_Reasoning__c');
        if (String.isNotBlank(overview)) {
            lines.add('');
            lines.add('Overview: ' + overview);
        }
        if (String.isNotBlank(reasoning)) {
            lines.add('');
            lines.add('Reasoning: ' + reasoning);
        }
        return String.join(lines, '\n');
    }

    private static void appendStringList(List<String> lines, String label, Object raw) {
        if (!(raw instanceof List<Object>)) {
            return;
        }
        List<Object> items = (List<Object>) raw;
        if (items.isEmpty()) {
            return;
        }
        lines.add(label + ':');
        for (Object item : items) {
            lines.add('- ' + String.valueOf(item));
        }
    }

    private static Map<String, Object> asMap(Object row) {
        return row instanceof Map<String, Object> ? (Map<String, Object>) row : null;
    }

    private static String str(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) {
            return '';
        }
        return String.valueOf(m.get(key));
    }

    @TestVisible
    static CvAgentActions.ActionRequest routeUtterance(String text, String preferredCandidateId) {
        String lower = text.toLowerCase();
        CvAgentActions.ActionRequest req = new CvAgentActions.ActionRequest();

        if (containsAny(lower, new List<String>{ 'list candidate', 'list candidates', 'who is available', 'show candidates', 'all candidates' })) {
            req.operation = 'listCandidates';
            return req;
        }

        Integer topN = extractTopN(lower);
        Boolean wantsRank = topN != null || containsAny(lower, new List<String>{
            'best candidate', 'best candidates', 'shortlist for', 'who should we hire', 'who should i hire'
        });
        Boolean wantsCompare = containsAny(lower, new List<String>{ 'compare', 'recommend', 'who is better', 'rank' });

        if (wantsCompare || wantsRank) {
            req.operation = 'compareCandidates';
            req.roleTitle = extractRole(text);
            req.requiredSkillsCsv = skillsForRole(req.roleTitle);
            req.minYears = 3;
            List<Id> named = findCandidateIdsMentioned(text);
            // Named head-to-head (e.g. Lina vs Sara) keeps two people.
            // "Top N / best for role" ranks the whole pool (deduped), not fact-search.
            if (named.size() >= 2 && topN == null && !wantsRank) {
                req.candidateIdsCsv = joinIds(named, 2);
            } else {
                req.candidateIdsCsv = resolveRankPoolIds(15);
            }
            return req;
        }

        if (containsAny(lower, new List<String>{ 'bookmark', 'save candidate', 'shortlist' })) {
            req.operation = 'bookmarkCandidate';
            req.candidateId = resolveOneCandidateId(text, preferredCandidateId);
            req.roleTitle = extractRole(text);
            req.requiredSkillsCsv = skillsForRole(req.roleTitle);
            req.minYears = 3;
            req.recruiterNotes = text;
            return req;
        }

        if (containsAny(lower, new List<String>{ 'score', 'fit for', 'how good' })) {
            req.operation = 'scoreForRole';
            req.candidateId = resolveOneCandidateId(text, preferredCandidateId);
            req.roleTitle = extractRole(text);
            req.requiredSkillsCsv = skillsForRole(req.roleTitle);
            req.minYears = 3;
            return req;
        }

        if (containsAny(lower, new List<String>{ 'data issue', 'ambiguity', 'missing', 'conflict', 'uncertain' })) {
            req.operation = 'listDataIssues';
            req.candidateId = resolveOneCandidateId(text, preferredCandidateId);
            return req;
        }

        if (containsAny(lower, new List<String>{
            'show card', 'candidate card', 'full profile', 'get candidate',
            'tell me about', 'who is', 'about ', 'skills', 'experience',
            'education', 'background', 'profile', 'summary'
        })) {
            req.operation = 'getCandidateCard';
            req.candidateId = resolveOneCandidateId(text, preferredCandidateId);
            return req;
        }

        req.operation = 'searchCandidateFacts';
        req.candidateId = resolveOneCandidateId(text, preferredCandidateId);
        req.searchQuery = text;
        return req;
    }

    private static Boolean containsAny(String lower, List<String> needles) {
        for (String n : needles) {
            if (lower.contains(n)) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    static Integer extractTopN(String lower) {
        if (String.isBlank(lower)) {
            return null;
        }
        Matcher m = Pattern.compile('(?:top|best)\\s*(\\d+)').matcher(lower);
        if (m.find()) {
            Integer n = Integer.valueOf(m.group(1));
            if (n < 1) {
                return 1;
            }
            return n > 10 ? 10 : n;
        }
        return null;
    }

    private static String extractRole(String text) {
        String lower = text.toLowerCase();
        if (lower.contains('consultant')) {
            return 'Salesforce Consultant';
        }
        if (lower.contains('salesforce')) {
            return 'Salesforce Developer';
        }
        if (lower.contains('java')) {
            return 'Java Engineer';
        }
        if (lower.contains('data analyst') || lower.contains('data engineer') || lower.contains('data role')) {
            return 'Data Analyst';
        }
        return 'Salesforce Developer';
    }

    private static String skillsForRole(String roleTitle) {
        String role = roleTitle == null ? '' : roleTitle.toLowerCase();
        if (role.contains('java')) {
            return 'Java,Spring,SQL';
        }
        if (role.contains('data')) {
            return 'SQL,Python,Tableau';
        }
        if (role.contains('consultant')) {
            return 'Salesforce,Apex,LWC,SOQL';
        }
        return 'Apex,LWC,SOQL';
    }

    private static String resolveOneCandidateId(String text, String preferredCandidateId) {
        List<Id> mentioned = findCandidateIdsMentioned(text);
        if (!mentioned.isEmpty()) {
            return mentioned[0];
        }
        if (String.isNotBlank(preferredCandidateId)) {
            return preferredCandidateId;
        }
        List<Candidate__c> recent = [
            SELECT Id
            FROM Candidate__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return recent.isEmpty() ? null : recent[0].Id;
    }

    private static String resolveCompareIds(String text, String preferredCandidateId) {
        List<Id> ids = new List<Id>();
        for (Id mentioned : findCandidateIdsMentioned(text)) {
            if (!ids.contains(mentioned)) {
                ids.add(mentioned);
            }
            if (ids.size() == 2) {
                break;
            }
        }
        if (ids.size() < 2 && String.isNotBlank(preferredCandidateId)) {
            Id pref = (Id) preferredCandidateId;
            if (!ids.contains(pref)) {
                ids.add(pref);
            }
        }
        if (ids.size() < 2) {
            for (Id poolId : resolveRankPoolIdList(10)) {
                if (!ids.contains(poolId)) {
                    ids.add(poolId);
                }
                if (ids.size() == 2) {
                    break;
                }
            }
        }
        return joinIds(ids, 2);
    }

    private static String resolveRankPoolIds(Integer maxPeople) {
        return joinIds(resolveRankPoolIdList(maxPeople), maxPeople);
    }

    /**
     * One best Candidate Card per person (first-name key), for ranking a role shortlist.
     */
    private static List<Id> resolveRankPoolIdList(Integer maxPeople) {
        Integer cap = maxPeople == null || maxPeople < 2 ? 10 : maxPeople;
        List<Candidate__c> rows = [
            SELECT Id, Name, Parse_Status__c, CreatedDate
            FROM Candidate__c
            WHERE Name != null
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        Map<String, MentionHit> bestByKey = new Map<String, MentionHit>();
        Integer order = 0;
        for (Candidate__c c : rows) {
            if (String.isBlank(c.Name)) {
                continue;
            }
            String key = personKey(c.Name);
            if (String.isBlank(key)) {
                continue;
            }
            Integer quality = mentionQuality(c, false);
            MentionHit existing = bestByKey.get(key);
            // Lower idx = earlier in CreatedDate DESC list (prefer newer when quality ties).
            if (existing == null || quality > existing.quality) {
                bestByKey.put(key, new MentionHit(order, c.Id, quality));
            }
            order++;
        }
        List<MentionHit> hits = bestByKey.values();
        hits.sort();
        List<Id> out = new List<Id>();
        for (MentionHit h : hits) {
            out.add(h.candidateId);
            if (out.size() >= cap) {
                break;
            }
        }
        return out;
    }

    private static String personKey(String candidateName) {
        String nameLower = candidateName.toLowerCase().trim();
        if (String.isBlank(nameLower)) {
            return null;
        }
        String normalized = nameLower.replace('_', ' ').replace('-', ' ');
        String first = normalized.split('\\s+')[0];
        return first.length() < 3 ? null : first;
    }

    private static String joinIds(List<Id> ids, Integer maxSize) {
        List<String> out = new List<String>();
        if (ids == null) {
            return '';
        }
        for (Id i : ids) {
            out.add(String.valueOf(i));
            if (maxSize != null && out.size() >= maxSize) {
                break;
            }
        }
        return String.join(out, ',');
    }

    /**
     * Returns candidate Ids mentioned in the utterance, ordered by first appearance.
     * One Id per person: duplicate cards that share the same first name (e.g. many
     * "Youssef Mohamed" rows) collapse to a single best card so compare can still
     * pick a second distinct person (e.g. Lina).
     */
    @TestVisible
    static List<Id> findCandidateIdsMentioned(String text) {
        List<Id> ordered = new List<Id>();
        if (String.isBlank(text)) {
            return ordered;
        }
        String lower = text.toLowerCase();
        List<Candidate__c> rows = [
            SELECT Id, Name, Parse_Status__c, CreatedDate
            FROM Candidate__c
            WHERE Name != null
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        // mentionKey (first name or full name) -> best hit
        Map<String, MentionHit> bestByKey = new Map<String, MentionHit>();
        for (Candidate__c c : rows) {
            if (String.isBlank(c.Name)) {
                continue;
            }
            MentionMatch match = matchMention(lower, c.Name);
            if (match == null) {
                continue;
            }
            Integer quality = mentionQuality(c, match.fullNameMatch);
            MentionHit existing = bestByKey.get(match.key);
            if (existing == null || quality > existing.quality ||
                (quality == existing.quality && match.idx < existing.idx)) {
                bestByKey.put(match.key, new MentionHit(match.idx, c.Id, quality));
            }
        }
        List<MentionHit> hits = bestByKey.values();
        hits.sort();
        Set<Id> seenIds = new Set<Id>();
        for (MentionHit h : hits) {
            if (seenIds.contains(h.candidateId)) {
                continue;
            }
            seenIds.add(h.candidateId);
            ordered.add(h.candidateId);
        }
        return ordered;
    }

    private class MentionMatch {
        String key;
        Integer idx;
        Boolean fullNameMatch;
        MentionMatch(String key, Integer idx, Boolean fullNameMatch) {
            this.key = key;
            this.idx = idx;
            this.fullNameMatch = fullNameMatch;
        }
    }

    private static MentionMatch matchMention(String lowerText, String candidateName) {
        String nameLower = candidateName.toLowerCase().trim();
        if (String.isBlank(nameLower)) {
            return null;
        }
        // Normalize file-style titles so first token is usable as a person key.
        String normalized = nameLower.replace('_', ' ').replace('-', ' ');
        String first = normalized.split('\\s+')[0];
        if (first.length() < 3) {
            return null;
        }

        // Prefer full-name hit when the utterance contains it (e.g. "lina mostafa").
        Integer fullIdx = lowerText.indexOf(nameLower);
        if (fullIdx < 0 && normalized != nameLower) {
            fullIdx = lowerText.indexOf(normalized);
        }
        if (fullIdx >= 0) {
            // Key by first name so duplicate "Youssef Mohamed" cards collapse.
            return new MentionMatch(first, fullIdx, true);
        }

        Matcher m = Pattern.compile('(?i)\\b' + Pattern.quote(first) + '\\b').matcher(lowerText);
        if (!m.find()) {
            return null;
        }
        return new MentionMatch(first, m.start(), false);
    }

    private static Integer mentionQuality(Candidate__c c, Boolean fullNameMatch) {
        Integer q = 0;
        if (fullNameMatch == true) {
            q += 100;
        }
        String status = c.Parse_Status__c == null ? '' : c.Parse_Status__c;
        if (status == 'Success') {
            q += 30;
        } else if (status == 'Partial') {
            q += 10;
        }
        // Prefer human-looking names over file-title cards.
        if (c.Name != null && !c.Name.contains('_') && !c.Name.contains('-')) {
            q += 20;
        }
        return q;
    }

    private class MentionHit implements Comparable {
        public Integer idx;
        public Id candidateId;
        public Integer quality;
        MentionHit(Integer idx, Id candidateId, Integer quality) {
            this.idx = idx;
            this.candidateId = candidateId;
            this.quality = quality == null ? 0 : quality;
        }
        public Integer compareTo(Object other) {
            MentionHit o = (MentionHit) other;
            if (this.idx == o.idx) {
                // Prefer higher-quality card when mention position ties.
                if (this.quality == o.quality) {
                    return 0;
                }
                return this.quality > o.quality ? -1 : 1;
            }
            return this.idx < o.idx ? -1 : 1;
        }
    }
}
