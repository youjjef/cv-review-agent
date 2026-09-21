/**
 * Role-fit scoring with explicit weighted rubric and explainability payload.
 * Weights: Skills 40%, Experience 30%, Education 15%, Completeness 15%.
 */
public with sharing class CvScoringService {
    public class ScoreRequest {
        public Id candidateId;
        public String roleTitle;
        public List<String> requiredSkills;
        public Integer minYears;
        public List<String> preferredEducationKeywords;
    }

    public class ScoreResult {
        public Id candidateId;
        public String candidateName;
        public Decimal totalScore;
        public Decimal skillsScore;
        public Decimal experienceScore;
        public Decimal educationScore;
        public Decimal completenessScore;
        public List<String> strengths;
        public List<String> concerns;
        public List<String> tradeOffs;
        public List<String> interviewGaps;
        public String reasoning;
        public String breakdownJson;
        public Boolean strongMatch;
    }

    public static ScoreResult score(ScoreRequest req) {
        Candidate__c c = [
            SELECT Id, Name, Email__c, Phone__c, Location__c, Summary__c, Years_Experience__c,
                   Parse_Status__c, Uncertainty_Summary__c,
                   (SELECT Name, Confidence__c, Evidence__c FROM Skills__r),
                   (SELECT Name, Company__c, Title__c, Start_Date_Text__c, End_Date_Text__c,
                           Description__c, Has_Date_Conflict__c, Confidence__c
                    FROM Experiences__r),
                   (SELECT Name, School__c, Degree__c, Field_Of_Study__c, End_Date_Text__c, Confidence__c
                    FROM Educations__r),
                   (SELECT Issue_Type__c, Field_Path__c, Details__c, Severity__c FROM Data_Issues__r)
            FROM Candidate__c
            WHERE Id = :req.candidateId
            LIMIT 1
        ];

        List<String> required = normalizeList(req.requiredSkills);
        List<String> eduKeywords = normalizeList(req.preferredEducationKeywords);
        Integer minYears = req.minYears == null ? 0 : req.minYears;

        Set<String> candidateSkills = new Set<String>();
        Integer inferredSkillCount = 0;
        for (Candidate_Skill__c s : c.Skills__r) {
            if (String.isNotBlank(s.Name)) {
                candidateSkills.add(s.Name.toLowerCase());
            }
            if (s.Confidence__c == CvConstants.CONFIDENCE_INFERRED) {
                inferredSkillCount++;
            }
        }

        Integer matched = 0;
        List<String> missingSkills = new List<String>();
        List<String> matchedSkills = new List<String>();
        for (String need : required) {
            Boolean found = false;
            for (String have : candidateSkills) {
                if (have.contains(need) || need.contains(have)) {
                    found = true;
                    break;
                }
            }
            if (found) {
                matched++;
                matchedSkills.add(need);
            } else {
                missingSkills.add(need);
            }
        }
        Decimal skillsScore = required.isEmpty()
            ? (candidateSkills.isEmpty() ? 40 : 70)
            : (Decimal.valueOf(matched) / Decimal.valueOf(required.size())) * 100;

        Decimal years = c.Years_Experience__c == null ? 0 : c.Years_Experience__c;
        Decimal experienceScore;
        if (minYears <= 0) {
            experienceScore = years >= 5 ? 90 : (years >= 2 ? 75 : 55);
        } else if (years >= minYears) {
            experienceScore = Math.min(100, (70 + ((years - minYears) * 5)).doubleValue());
        } else {
            experienceScore = Math.max(20, (70 - ((minYears - years) * 15)).doubleValue());
        }
        // Role title relevance
        String role = req.roleTitle == null ? '' : req.roleTitle.toLowerCase();
        Boolean roleMentioned = false;
        for (Candidate_Experience__c e : c.Experiences__r) {
            String expText = ((e.Title__c == null ? '' : e.Title__c) + ' ' + (e.Description__c == null ? '' : e.Description__c)).toLowerCase();
            if (String.isNotBlank(role) && expText.contains(role)) {
                roleMentioned = true;
            }
            if (e.Has_Date_Conflict__c == true) {
                experienceScore = Math.max(10, experienceScore.doubleValue() - 10);
            }
        }
        if (String.isNotBlank(role) && roleMentioned) {
            experienceScore = Math.min(100, experienceScore.doubleValue() + 8);
        }

        Decimal educationScore = c.Educations__r.isEmpty() ? 40 : 70;
        if (!eduKeywords.isEmpty()) {
            Integer eduHits = 0;
            for (Candidate_Education__c ed : c.Educations__r) {
                String eduText = ((ed.School__c == null ? '' : ed.School__c) + ' ' +
                    (ed.Degree__c == null ? '' : ed.Degree__c) + ' ' +
                    (ed.Field_Of_Study__c == null ? '' : ed.Field_Of_Study__c)).toLowerCase();
                for (String k : eduKeywords) {
                    if (eduText.contains(k)) {
                        eduHits++;
                    }
                }
            }
            educationScore = eduHits == 0 ? 35 : Math.min(100, 60 + (eduHits * 15));
        }

        Integer issuePenalty = 0;
        Integer criticalIssues = 0;
        for (Candidate_Data_Issue__c issue : c.Data_Issues__r) {
            if (issue.Severity__c == CvConstants.SEVERITY_CRITICAL) {
                criticalIssues++;
                issuePenalty += 12;
            } else if (issue.Severity__c == CvConstants.SEVERITY_WARNING) {
                issuePenalty += 6;
            } else {
                issuePenalty += 2;
            }
        }
        Decimal completenessScore = Math.max(15, 100 - issuePenalty);
        if (String.isBlank(c.Email__c)) {
            completenessScore = Math.max(10, completenessScore.doubleValue() - 15);
        }
        if (inferredSkillCount > 0) {
            completenessScore = Math.max(10, completenessScore.doubleValue() - (inferredSkillCount * 2));
        }

        Decimal total =
            (skillsScore * CvConstants.WEIGHT_SKILLS) +
            (experienceScore * CvConstants.WEIGHT_EXPERIENCE) +
            (educationScore * CvConstants.WEIGHT_EDUCATION) +
            (completenessScore * CvConstants.WEIGHT_COMPLETENESS);
        total = total.setScale(2);

        ScoreResult result = new ScoreResult();
        result.candidateId = c.Id;
        result.candidateName = c.Name;
        result.totalScore = total;
        result.skillsScore = skillsScore.setScale(2);
        result.experienceScore = experienceScore.setScale(2);
        result.educationScore = educationScore.setScale(2);
        result.completenessScore = completenessScore.setScale(2);
        result.strengths = new List<String>();
        result.concerns = new List<String>();
        result.tradeOffs = new List<String>();
        result.interviewGaps = new List<String>();
        result.strongMatch = total >= 75 && missingSkills.size() <= 1 && criticalIssues == 0;

        if (!matchedSkills.isEmpty()) {
            result.strengths.add('Matched required skills: ' + String.join(matchedSkills, ', '));
        }
        if (years >= minYears && minYears > 0) {
            result.strengths.add('Meets minimum experience (' + years + ' years vs ' + minYears + ' required).');
        }
        if (roleMentioned) {
            result.strengths.add('Prior experience title/description references the target role.');
        }
        if (!c.Educations__r.isEmpty()) {
            result.strengths.add('Education history is present on the Candidate Card.');
        }

        if (!missingSkills.isEmpty()) {
            result.concerns.add('Missing required skills (not evidenced in CV): ' + String.join(missingSkills, ', '));
            result.interviewGaps.add('Validate proficiency in: ' + String.join(missingSkills, ', '));
        }
        if (years < minYears) {
            result.concerns.add('Years of experience (' + years + ') below target (' + minYears + ').');
            result.interviewGaps.add('Probe depth of ownership to offset years gap.');
        }
        if (criticalIssues > 0) {
            result.concerns.add(criticalIssues + ' critical data issue(s) on the Candidate Card.');
        }
        for (Candidate_Data_Issue__c issue : c.Data_Issues__r) {
            if (issue.Issue_Type__c == CvConstants.ISSUE_CONFLICTING) {
                result.concerns.add('Conflicting CV data: ' + issue.Details__c);
                result.interviewGaps.add('Clarify conflicting detail: ' + issue.Field_Path__c);
            }
        }
        if (String.isBlank(c.Email__c)) {
            result.interviewGaps.add('Confirm contact email (missing from CV).');
        }

        if (!result.strongMatch) {
            result.tradeOffs.add('No strong match under rubric (>=75, <=1 missing skill, no critical issues). Best-available assessment provided.');
        }
        if (skillsScore >= 80 && experienceScore < 60) {
            result.tradeOffs.add('Strong skill overlap but thinner experience depth for the role.');
        }
        if (experienceScore >= 80 && skillsScore < 60) {
            result.tradeOffs.add('Solid tenure/experience signals but weaker evidenced skill coverage.');
        }
        if (completenessScore < 60) {
            result.tradeOffs.add('Lower confidence due to missing/uncertain/conflicting CV fields.');
        }

        Map<String, Object> breakdown = new Map<String, Object>{
            'weights' => new Map<String, Object>{
                'skills' => CvConstants.WEIGHT_SKILLS,
                'experience' => CvConstants.WEIGHT_EXPERIENCE,
                'education' => CvConstants.WEIGHT_EDUCATION,
                'completeness' => CvConstants.WEIGHT_COMPLETENESS
            },
            'componentScores' => new Map<String, Object>{
                'skills' => result.skillsScore,
                'experience' => result.experienceScore,
                'education' => result.educationScore,
                'completeness' => result.completenessScore
            },
            'matchedSkills' => matchedSkills,
            'missingSkills' => missingSkills,
            'yearsExperience' => years,
            'minYears' => minYears,
            'roleTitle' => req.roleTitle,
            'strongMatch' => result.strongMatch
        };
        result.breakdownJson = JSON.serialize(breakdown);
        result.reasoning =
            'Scored ' + result.totalScore + '/100 for role "' + req.roleTitle + '". ' +
            'Skills ' + result.skillsScore + ' (40%), Experience ' + result.experienceScore +
            ' (30%), Education ' + result.educationScore + ' (15%), Completeness ' +
            result.completenessScore + ' (15%). Grounded only in Candidate Card fields.';
        return result;
    }

    public static List<ScoreResult> compare(List<Id> candidateIds, ScoreRequest baseReq) {
        List<ScoreResult> results = new List<ScoreResult>();
        for (Id candidateId : candidateIds) {
            ScoreRequest r = new ScoreRequest();
            r.candidateId = candidateId;
            r.roleTitle = baseReq.roleTitle;
            r.requiredSkills = baseReq.requiredSkills;
            r.minYears = baseReq.minYears;
            r.preferredEducationKeywords = baseReq.preferredEducationKeywords;
            results.add(score(r));
        }
        results.sort(new ScoreComparator());
        return results;
    }

    private static List<String> normalizeList(List<String> values) {
        List<String> out = new List<String>();
        if (values == null) {
            return out;
        }
        for (String v : values) {
            if (String.isNotBlank(v)) {
                out.add(v.trim().toLowerCase());
            }
        }
        return out;
    }

    private class ScoreComparator implements Comparator<ScoreResult> {
        public Integer compare(ScoreResult a, ScoreResult b) {
            if (a.totalScore == b.totalScore) {
                return 0;
            }
            return a.totalScore > b.totalScore ? -1 : 1;
        }
    }
}
