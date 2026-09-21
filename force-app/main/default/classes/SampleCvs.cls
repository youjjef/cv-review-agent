/**
 * Sample CV text fixtures used by the stub ingestion path and tests.
 */
public with sharing class SampleCvs {
    public static final String SARA =
        'Sara Hassan\n' +
        'Email: sara.hassan@email.com\n' +
        'Phone: +20 100 555 0101\n' +
        'Location: Cairo, Egypt\n' +
        'https://www.linkedin.com/in/sarahassan\n\n' +
        'Summary\n' +
        'Salesforce developer with 6 years of experience building Lightning apps and integrations.\n\n' +
        'Skills\n' +
        'Apex, LWC, SOQL, REST Integrations, JavaScript, Salesforce, Git\n\n' +
        'Experience\n' +
        'Senior Salesforce Developer - Clouding AI - 2021 - Present\n' +
        '- Designed Agentforce-ready Apex services and LWC workspaces\n' +
        '- Led CV screening automation PoC\n' +
        'Salesforce Developer - Nile Tech - 2018 - 2021\n' +
        '- Built trigger frameworks and integration layer\n\n' +
        'Education\n' +
        'Cairo University | BSc Computer Science | 2017\n';

    public static final String OMAR =
        'Omar Farid\n' +
        'omar.farid@email.com\n' +
        '+971 50 123 4567\n' +
        'Location: Dubai, UAE\n\n' +
        'Profile\n' +
        'Backend engineer specializing in Java microservices. 8+ years of experience.\n\n' +
        'Skills\n' +
        'Java, Spring Boot, SQL, AWS, REST, Kafka\n\n' +
        'Experience\n' +
        'Staff Java Engineer @ Horizon Labs - 2019 - Present\n' +
        '- Scaled payment APIs to 2M daily transactions\n' +
        'Java Developer @ ByteForge - 2015 - 2019\n' +
        '- Built ETL pipelines and service mesh adapters\n\n' +
        'Education\n' +
        'AUC - BSc Computer Engineering - 2014\n';

    public static final String LINA =
        'Lina Mostafa\n' +
        'Phone: +20 122 000 7788\n' +
        'Location: Alexandria, Egypt\n\n' +
        'About\n' +
        'Data analyst with strong visualization background.\n\n' +
        'Core Competencies\n' +
        'Python, SQL, Tableau, Power BI, Data Analysis, Communication\n\n' +
        'Work Experience\n' +
        'Data Analyst - Insight Co - 2020 - Present\n' +
        '- Built executive dashboards and forecasting models\n' +
        'Junior Analyst - MarketPulse - 2018 - 2020\n\n' +
        'Education\n' +
        'Alexandria University | BSc Statistics | 2018\n';

    public static final String AMBIGUOUS =
        'Alex Candidate\n' +
        'Location: Remote\n\n' +
        'Summary\n' +
        'Versatile technologist. Claims 10 years experience and also 4 years experience in different sections.\n' +
        '10 years of experience in consulting. 4 years of experience in engineering.\n\n' +
        'Experience\n' +
        'Consultant - Acme - 2018 - 2022\n' +
        'Engineer - Acme - 2019 - 2023\n' +
        ' overlapping roles at same company with conflicting timelines\n\n' +
        'Education\n' +
        'Some University - MBA - 2025\n';

    public static final String GENERIC =
        '{{NAME}}\n' +
        'Summary\n' +
        'Candidate uploaded without rich structured sections.\n\n' +
        'Skills\n' +
        'Communication, Problem Solving\n';
}
