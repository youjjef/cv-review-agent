/**
 * Shared constants for CV Review Agent scoring and confidence values.
 */
public with sharing class CvConstants {
    public static final Decimal WEIGHT_SKILLS = 0.40;
    public static final Decimal WEIGHT_EXPERIENCE = 0.30;
    public static final Decimal WEIGHT_EDUCATION = 0.15;
    public static final Decimal WEIGHT_COMPLETENESS = 0.15;

    public static final String CONFIDENCE_EXTRACTED = 'Extracted';
    public static final String CONFIDENCE_INFERRED = 'Inferred';
    public static final String CONFIDENCE_MISSING = 'Missing';

    public static final String ISSUE_MISSING = 'Missing';
    public static final String ISSUE_UNCERTAIN = 'Uncertain';
    public static final String ISSUE_CONFLICTING = 'Conflicting';

    public static final String PARSE_PENDING = 'Pending';
    public static final String PARSE_SUCCESS = 'Success';
    public static final String PARSE_PARTIAL = 'Partial';
    public static final String PARSE_FAILED = 'Failed';

    public static final String SEVERITY_INFO = 'Info';
    public static final String SEVERITY_WARNING = 'Warning';
    public static final String SEVERITY_CRITICAL = 'Critical';
}
