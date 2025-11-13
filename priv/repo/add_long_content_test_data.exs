# Script to add test data with very long content descriptions
# Run with: mix run priv/repo/add_long_content_test_data.exs

alias Hermes.Repo
alias Hermes.Accounts.{Team, User}
alias Hermes.Requests.Request

IO.puts("Adding test data with long content descriptions...")

# Get existing teams and users
dev_team = Repo.get_by!(Team, name: "Development Team")
marketing_team = Repo.get_by!(Team, name: "Marketing Team")
sales_team = Repo.get_by!(Team, name: "Sales Team")

dev_user = Repo.get_by!(User, email: "dev@hermes.com")
marketing_user = Repo.get_by!(User, email: "marketing@hermes.com")
sales_user = Repo.get_by!(User, email: "sales@hermes.com")

# Create request with extremely detailed content
long_request_1 = Repo.insert!(%Request{
  kind: :problem,
  priority: 4,
  target_user_type: :external,
  current_situation: """
  Our current customer data management system is experiencing critical performance degradation that is significantly impacting our business operations across multiple departments. The system, which was originally designed to handle approximately 10,000 customer records, is now struggling with over 500,000 active customer profiles, resulting in severe bottlenecks and user frustration.

  The main issues we're encountering include:

  1. Database Query Performance: Simple customer lookups that should take milliseconds are now taking 15-30 seconds to complete. This is particularly problematic during peak business hours (9 AM - 5 PM EST) when our sales team is actively working with clients. The slow response times are causing our sales representatives to lose momentum during customer calls and presentations.

  2. Data Synchronization Delays: Our system syncs customer data across multiple platforms including our CRM, email marketing platform, and customer support ticketing system. These synchronization jobs, which used to run every 15 minutes, are now taking 2-3 hours to complete, causing data inconsistencies across platforms and leading to customer service issues.

  3. Report Generation Failures: Monthly customer analytics reports, which are critical for our executive team's decision-making process, are timing out before completion. The reports include metrics such as customer lifetime value, churn rate analysis, geographic distribution, product preferences, and engagement patterns. Without these reports, our leadership team cannot make informed strategic decisions.

  4. System Crashes During Peak Hours: We've experienced 12 complete system crashes in the past month, all occurring during high-traffic periods. Each crash results in approximately 30-45 minutes of downtime, during which our entire sales and customer service teams are unable to access customer information. This has resulted in lost sales opportunities and degraded customer experiences.

  5. Mobile Application Performance: Our mobile sales application, which relies on the customer database, has become nearly unusable. Sales representatives in the field report that loading customer profiles on mobile devices can take up to 2 minutes, and the application frequently crashes when attempting to update customer information.

  6. Data Import/Export Bottlenecks: Bulk operations such as importing new customer lists from trade shows or exporting customer segments for marketing campaigns are taking exponentially longer than before. What used to be a 10-minute process now takes several hours, severely limiting our team's agility in responding to market opportunities.

  The root causes appear to be:
  - Inefficient database schema design that wasn't built to scale
  - Lack of proper indexing on frequently queried fields
  - Unoptimized SQL queries throughout the application
  - Insufficient server resources and outdated infrastructure
  - No caching layer for frequently accessed data
  - Monolithic architecture that prevents horizontal scaling

  This situation is not only affecting productivity but also our revenue. We estimate that the performance issues are costing us approximately $50,000 per month in lost sales opportunities, not to mention the negative impact on employee morale and customer satisfaction scores, which have dropped 15% over the past quarter.
  """,
  goal_description: """
  We need to completely redesign and rebuild our customer data management infrastructure to support our current scale and anticipated growth over the next 5 years. Our goal is to create a robust, scalable, and high-performance system that can handle at least 5 million customer records while maintaining sub-second response times for all critical operations.

  Specific objectives include:

  1. Performance Optimization:
  - Reduce average customer lookup time from 15-30 seconds to under 500 milliseconds
  - Enable report generation for any time period to complete within 2 minutes maximum
  - Support concurrent access by 500+ users without performance degradation
  - Implement real-time data synchronization across all integrated platforms (max 30-second delay)
  - Ensure mobile application response times under 1 second for all operations

  2. Scalability and Infrastructure:
  - Design database architecture to efficiently handle 5+ million customer records
  - Implement horizontal scaling capabilities to add capacity as needed
  - Create a microservices architecture to isolate critical functions
  - Establish multi-region deployment for improved global access speeds
  - Build auto-scaling mechanisms based on load patterns

  3. Data Management:
  - Implement comprehensive caching strategy using Redis or similar technology
  - Optimize database schema with proper normalization and indexing
  - Create data archival strategy for historical records
  - Implement data partitioning for improved query performance
  - Establish data versioning and audit trails for compliance

  4. Reliability and Availability:
  - Achieve 99.9% uptime SLA (less than 45 minutes downtime per month)
  - Implement automatic failover and disaster recovery mechanisms
  - Create redundant systems to prevent single points of failure
  - Establish comprehensive monitoring and alerting systems
  - Design graceful degradation strategies for partial system failures

  5. User Experience:
  - Redesign user interface with modern, intuitive navigation
  - Implement advanced search and filtering capabilities
  - Create customizable dashboards for different user roles
  - Enable bulk operations to be processed asynchronously with progress tracking
  - Provide real-time notifications for important events and updates

  6. Integration and API:
  - Develop comprehensive REST API for third-party integrations
  - Implement webhook support for real-time event notifications
  - Create SDK libraries for common programming languages
  - Establish API rate limiting and authentication mechanisms
  - Document all API endpoints with interactive examples

  7. Analytics and Reporting:
  - Build real-time analytics dashboard with customizable widgets
  - Enable ad-hoc report creation with drag-and-drop interface
  - Implement predictive analytics using machine learning models
  - Create automated report scheduling and distribution
  - Support data export in multiple formats (CSV, Excel, PDF, JSON)

  Success metrics:
  - Page load times under 500ms for 95% of requests
  - Zero unplanned downtime for critical operations
  - User satisfaction score above 4.5/5
  - Support for 10x current data volume without performance degradation
  - Complete data synchronization across platforms within 30 seconds
  - Mobile app crash rate below 0.1%
  - API response times under 200ms for 99% of requests
  """,
  data_description: """
  The system will manage and process several categories of complex business data:

  1. Customer Profile Data:
  - Basic Information: Full name, company name, job title, email addresses (primary and secondary), phone numbers (mobile, office, home), physical addresses (billing and shipping), date of birth, customer ID, account creation date
  - Demographics: Age range, gender, income bracket, education level, household size, geographic region, timezone
  - Preferences: Communication preferences (email, SMS, phone), language preference, notification settings, privacy settings, marketing consent flags
  - Custom Fields: Industry-specific data points, custom tags and labels, account notes and comments

  2. Transaction and Purchase History:
  - Order Details: Order ID, purchase date, items purchased, quantities, prices, discounts applied, shipping costs, taxes, total amount
  - Payment Information: Payment method, transaction ID, payment status, refund history, credit balance, payment terms
  - Product Data: SKU numbers, product categories, product variants, bundle details, subscription information
  - Fulfillment: Shipping address, tracking numbers, delivery status, return/exchange history

  3. Engagement and Interaction Data:
  - Website Activity: Page views, session duration, click patterns, search queries, abandoned carts, wishlists
  - Email Marketing: Open rates, click-through rates, unsubscribe events, campaign engagement, A/B test results
  - Support Interactions: Support ticket history, chat transcripts, call recordings, resolution times, satisfaction ratings
  - Social Media: Social profiles, mentions, engagement metrics, sentiment analysis

  4. Behavioral Analytics:
  - Customer Lifecycle: Onboarding progress, activation milestones, engagement scores, churn risk indicators
  - Segmentation: Customer segments, cohort analysis, RFM scores (Recency, Frequency, Monetary), lifetime value calculations
  - Predictive Data: Purchase probability, churn likelihood, cross-sell opportunities, upsell potential
  - Journey Mapping: Touchpoint interactions, conversion paths, attribution data

  5. Integration Data:
  - CRM System: Salesforce account data, opportunity information, lead scores, sales pipeline status
  - Marketing Automation: Campaign membership, lead nurturing stages, marketing qualified leads (MQL), automation workflow states
  - Customer Support: Zendesk ticket data, knowledge base article views, community forum activity
  - E-commerce Platform: Shopify order data, inventory levels, abandoned cart recovery campaigns
  - Payment Processing: Stripe customer IDs, subscription status, payment method details

  6. Compliance and Audit Data:
  - Data Privacy: GDPR consent records, data processing agreements, right to be forgotten requests, data portability exports
  - Security: Access logs, authentication events, permission changes, data encryption keys
  - Regulatory: Industry-specific compliance data, audit trails, data retention policies
  - Quality Metrics: Data completeness scores, validation rules, duplicate detection, data cleansing history

  Data Volume Estimates:
  - 5 million+ customer records
  - 50 million+ transaction records
  - 200 million+ interaction events per year
  - 10 TB+ total data storage
  - 500+ concurrent database connections
  - 10,000+ API calls per minute during peak times

  Data Sources and Formats:
  - CSV imports from trade shows and partner systems
  - JSON API data from third-party services
  - XML feeds from legacy enterprise systems
  - Real-time streaming data from website analytics
  - Batch files from nightly ETL processes
  - Direct database connections to external systems
  """,
  goal_target: :interface_view,
  expected_output: """
  The final deliverable should be a comprehensive, enterprise-grade customer data platform consisting of:

  1. Web-Based Administrative Interface:
  - Modern, responsive dashboard with real-time metrics and KPIs
  - Customer 360-degree view showing complete customer history and interactions
  - Advanced search interface with saved filters, boolean logic, and fuzzy matching
  - Bulk action tools for updating, tagging, exporting, and managing customer segments
  - Role-based access control with granular permissions management
  - Customizable workspace layouts for different user personas (sales, support, marketing)
  - Dark mode and accessibility features (WCAG 2.1 AA compliant)

  2. Mobile Applications:
  - Native iOS and Android apps for field sales representatives
  - Offline mode with automatic synchronization when connection is restored
  - Voice-to-text for quick note-taking during customer meetings
  - Barcode/QR code scanning for quick customer lookup
  - Geo-location features for nearby customer identification
  - Push notifications for important customer events and tasks

  3. Analytics and Reporting Suite:
  - Interactive dashboards with drill-down capabilities
  - Customizable report builder with drag-and-drop interface
  - Scheduled report distribution via email and Slack
  - Real-time data visualization with charts, graphs, and heat maps
  - Predictive analytics powered by machine learning models
  - Cohort analysis and customer segmentation tools
  - Executive summary reports with key insights and recommendations

  4. Integration Platform:
  - RESTful API with comprehensive documentation (OpenAPI/Swagger format)
  - Webhook support for real-time event notifications
  - Pre-built connectors for popular platforms (Salesforce, HubSpot, Zendesk, Shopify)
  - SDK libraries for JavaScript, Python, Ruby, and PHP
  - OAuth 2.0 authentication and API key management
  - Rate limiting and usage analytics for API consumers
  - Sandbox environment for testing integrations

  5. Data Management Tools:
  - Bulk import wizard with field mapping and validation
  - Duplicate detection and merge functionality
  - Data quality scoring and cleansing workflows
  - Automated data enrichment from third-party data providers
  - Data export tools supporting CSV, Excel, JSON, and XML formats
  - Archive and purge utilities for data lifecycle management
  - Data versioning and rollback capabilities

  6. Administration and Security Features:
  - User management with SSO integration (SAML, OAuth)
  - Audit logs for all system activities and data changes
  - Encryption at rest and in transit (AES-256, TLS 1.3)
  - Compliance dashboard showing GDPR, CCPA, and industry regulation adherence
  - Backup and disaster recovery management interface
  - System health monitoring and performance metrics
  - Configuration management for business rules and workflows

  7. Documentation Package:
  - Complete user manuals for all personas (admin, sales, support, marketing)
  - Video tutorials and interactive walkthroughs
  - API documentation with code examples and use cases
  - System architecture diagrams and technical specifications
  - Deployment guides for cloud and on-premise installations
  - Troubleshooting guides and FAQ sections
  - Release notes and changelog

  Technical Specifications:
  - Frontend: React.js or Vue.js with TypeScript
  - Backend: Node.js, Python, or Go microservices
  - Database: PostgreSQL with read replicas, Redis for caching
  - Search: Elasticsearch for full-text search capabilities
  - Message Queue: RabbitMQ or Apache Kafka for asynchronous processing
  - Cloud Infrastructure: AWS or Google Cloud Platform with auto-scaling
  - Monitoring: Prometheus and Grafana for metrics, ELK stack for logging
  - CI/CD: Automated testing and deployment pipelines

  Performance Requirements:
  - Page load time: < 500ms for 95th percentile
  - API response time: < 200ms for 99th percentile
  - Database query time: < 100ms for 95% of queries
  - Uptime: 99.9% availability SLA
  - Concurrent users: Support 1,000+ simultaneous active users
  - Data processing: Handle 100,000+ records per hour for bulk operations

  The system should be delivered with comprehensive testing including unit tests, integration tests, end-to-end tests, performance tests, and security penetration testing. A phased rollout plan should be included to migrate existing data and train users on the new system.
  """,
  title: "Critical: Complete Customer Data Platform Rebuild",
  description: "Rebuild entire customer data management system to handle 5M+ records with sub-second response times. Critical performance issues affecting revenue.",
  status: "in_progress",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

long_request_2 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 3,
  target_user_type: :internal,
  current_situation: """
  Our organization currently lacks a unified, comprehensive employee training and development platform. Training materials and resources are scattered across multiple systems and locations, making it extremely difficult for employees to find relevant learning content, track their progress, and demonstrate skill acquisition.

  Current state of training resources:
  - Some training videos are stored in a shared Google Drive folder with inconsistent naming conventions
  - Compliance training is delivered through an outdated third-party LMS that doesn't integrate with our HR systems
  - Department-specific training materials exist in various SharePoint sites managed by different teams
  - In-person training sessions are tracked in Excel spreadsheets by individual trainers
  - New hire onboarding materials are sent via email as PDF attachments
  - Professional development courses are accessed through multiple external platforms (LinkedIn Learning, Coursera, Udemy)
  - Certifications and credentials are maintained in personal files with no central tracking

  The problems this fragmentation creates:

  For Employees:
  - No single place to discover available training opportunities
  - Difficulty tracking which courses they've completed and which are still required
  - Unable to see a clear learning path for career development
  - No way to showcase completed training and acquired skills to managers
  - Frustration finding specific training materials when needed
  - Confusion about which training is mandatory versus optional
  - No mobile access to learning content for remote workers

  For Managers:
  - Cannot easily see training completion rates for their teams
  - Difficulty identifying skill gaps and training needs
  - Time-consuming process to assign and track team training
  - No visibility into professional development activities
  - Cannot assess ROI on training investments
  - Challenging to ensure compliance training is up to date

  For HR and Learning & Development Team:
  - Manual work tracking training completions across disparate systems
  - Inability to generate comprehensive training analytics and reports
  - Difficult to identify trending skills and popular courses
  - Cannot measure effectiveness of training programs
  - Compliance audit preparation is extremely time-consuming
  - Limited ability to personalize learning recommendations
  - No standardized way to create and deploy new training content

  For the Organization:
  - Risk of non-compliance with industry regulations and certifications
  - Inconsistent employee skill levels across departments
  - Difficulty maintaining institutional knowledge
  - Inefficient use of training budget due to lack of insights
  - Lower employee engagement and retention due to poor development opportunities
  - Inability to quickly upskill workforce for new business initiatives

  Additional context:
  - We have 2,500 employees across 15 office locations globally
  - Approximately 40% of our workforce is remote or hybrid
  - We operate in a regulated industry requiring annual compliance certification
  - Employee turnover rate is 18% annually, partly attributed to limited growth opportunities
  - Current training budget is $2.5M annually but ROI is unclear
  - New product launches require rapid training of 200+ sales and support staff
  - We're planning to expand into new markets requiring specialized regional training
  """,
  goal_description: """
  Develop and implement a comprehensive Learning Management System (LMS) that serves as the central hub for all employee training, professional development, and skill building activities. The system should provide a modern, engaging learning experience while giving administrators powerful tools for content management, reporting, and analytics.

  Core Learning Experience:
  - Intuitive course catalog with advanced filtering by topic, skill level, duration, format, and department
  - Personalized learning dashboard showing recommended courses, in-progress training, and upcoming deadlines
  - Multiple content formats support: videos, interactive modules, documents, quizzes, live webinars, and virtual classrooms
  - Mobile-responsive design with native iOS and Android apps for learning on-the-go
  - Offline mode for downloading course materials to complete without internet connection
  - Social learning features including discussion forums, peer reviews, and study groups
  - Gamification elements such as points, badges, leaderboards, and achievement tracking
  - Integrated calendar for scheduling live training sessions and setting learning goals
  - Bookmarking and note-taking capabilities within course materials
  - Accessibility features including closed captions, screen reader support, and keyboard navigation

  Learning Paths and Career Development:
  - Pre-built learning paths for common roles (e.g., "New Manager", "Sales Professional", "Software Developer")
  - Custom learning path builder for managers to create team-specific development programs
  - Skills taxonomy mapping courses to specific competencies
  - Career progression roadmaps showing required training for promotion to next level
  - Individual development plan (IDP) integration with performance management
  - Mentorship matching based on skills and interests
  - Succession planning tools identifying high-potential employees and development needs

  Content Management and Authoring:
  - User-friendly course creation wizard for SMEs to develop content without technical skills
  - Template library for consistent course design and branding
  - Multi-media support for uploading videos, presentations, documents, and SCORM packages
  - Version control for course materials with ability to roll back changes
  - Content review and approval workflows
  - Course translation and localization management
  - External content integration from LinkedIn Learning, Coursera, and other platforms
  - Automated content recommendations using AI based on job role and skill gaps

  Assessment and Certification:
  - Quiz and assessment builder with multiple question types (multiple choice, true/false, essay, file upload)
  - Randomized question pools to prevent cheating
  - Timed assessments with automatic grading
  - Certification issuance upon course completion with digital badges
  - Certificate templates with automatic population of completion data
  - Recertification tracking and automated reminders
  - Skills assessments to measure proficiency before and after training
  - 360-degree feedback integration for soft skills evaluation

  Compliance and Reporting:
  - Automated assignment of mandatory training based on role, location, or department
  - Deadline tracking with escalating reminders for overdue training
  - Compliance dashboard showing completion rates by requirement and department
  - Audit trail of all training activities and completions
  - Real-time reporting on training effectiveness, engagement, and ROI
  - Custom report builder for ad-hoc analysis
  - Scheduled reports delivered via email or dashboard
  - Integration with HR systems for automated onboarding and offboarding

  Administration and Integration:
  - Single Sign-On (SSO) integration with existing identity provider
  - HRIS integration for automatic user provisioning and org chart synchronization
  - Calendar integration (Google Calendar, Outlook) for training event scheduling
  - Video conferencing integration (Zoom, Teams) for virtual instructor-led training
  - Expense management integration for tracking external training costs
  - Performance management system integration for linking training to goals
  - API for custom integrations and data exchange
  - Bulk user and course import tools

  Expected Outcomes:
  - 95% of employees actively using the platform within 6 months of launch
  - 100% compliance training completion rates within required timeframes
  - 30% reduction in time spent on training administration
  - 25% increase in internal promotions due to better skill development
  - 50% reduction in new hire time-to-productivity through structured onboarding
  - 40% increase in employee engagement scores related to growth and development
  - Clear visibility into $2.5M training budget allocation and ROI
  - Ability to upskill 200+ employees for new initiatives within 30 days
  """,
  data_description: """
  The Learning Management System will manage diverse types of training and development data:

  1. User and Employee Data:
  - Personal Information: Employee ID, full name, email, department, job title, manager, location, hire date
  - Role Information: Job level, career track, areas of expertise, interests, language preferences
  - Learning Profile: Learning style preferences, accessibility needs, time zone, notification preferences
  - Historical Data: Previous roles, promotions, transfers, performance ratings
  - External Certifications: Professional certifications, degrees, licenses with expiration dates

  2. Course and Content Data:
  - Course Metadata: Title, description, objectives, prerequisites, duration, difficulty level, language
  - Content Files: Video files (MP4), presentations (PPT, PDF), documents (Word, PDF), SCORM packages
  - Instructional Design: Module structure, lesson plans, learning objectives, assessment criteria
  - Tagging: Skills covered, topics, keywords, competency mappings, compliance categories
  - Versioning: Publication dates, revision history, changelog, deprecated content flags
  - Usage Statistics: View counts, completion rates, average scores, user ratings and reviews

  3. Learning Progress and Completion Data:
  - Enrollment Records: Course enrollments, start dates, due dates, assignment source (self, manager, auto)
  - Progress Tracking: Last accessed date, percentage complete, time spent per module, bookmarks
  - Assessment Results: Quiz scores, attempt history, question-level analytics, grading rubrics
  - Certifications: Issue date, expiration date, certificate ID, continuing education credits
  - Competency Tracking: Skill proficiency levels, assessment scores, growth over time

  4. Learning Paths and Career Development:
  - Path Definitions: Sequence of courses, branching logic, alternative options, completion criteria
  - Role-Based Paths: Required training for each job role and level
  - Individual Development Plans: Goals, target completion dates, progress milestones, manager notes
  - Skills Inventory: Organization-wide skills taxonomy, proficiency definitions, assessment criteria
  - Succession Plans: Critical roles, potential successors, development readiness, gap analysis

  5. Compliance and Regulatory Data:
  - Requirements: Compliance training mandates by role, location, and regulatory body
  - Completion Status: Employee compliance status, outstanding requirements, grace periods
  - Audit Trails: All training activities, timestamps, IP addresses, completion evidence
  - Certification Records: Industry certifications, renewal dates, continuing education units
  - Regulatory Reports: Formatted exports for regulatory submissions and audits

  6. Instructor and Facilitator Data:
  - Trainer Profiles: Bio, expertise areas, certifications, availability calendar, hourly rates
  - Classroom Sessions: Schedule, location, capacity, registered attendees, waitlist, materials
  - Virtual Events: Meeting links, recording URLs, chat transcripts, poll results, attendance tracking
  - Evaluation Data: Instructor ratings, course feedback, improvement suggestions, response rates

  7. Content Library and Resources:
  - Document Repository: Training manuals, quick reference guides, job aids, templates
  - Video Library: On-demand recordings, webinar archives, demonstrations, simulations
  - External Content: LinkedIn Learning course IDs, Coursera enrollments, third-party platform licenses
  - Social Learning: Discussion forum threads, comments, user-generated content, peer reviews
  - Resource Downloads: Download counts, popular resources, search queries, bookmarked items

  8. Analytics and Reporting Data:
  - Engagement Metrics: Active users, login frequency, session duration, feature usage
  - Learning Analytics: Completion rates by course/department/role, time-to-complete, dropout points
  - Assessment Analytics: Average scores, question difficulty analysis, common wrong answers
  - Skills Analytics: Top in-demand skills, skill gaps by department, trending topics
  - ROI Metrics: Training costs, productivity improvements, retention rates, promotion rates
  - Predictive Analytics: Churn risk indicators, high-potential employee identification, success predictors

  9. Financial Data:
  - Training Budget: Allocated budgets by department, category, quarter
  - Course Costs: Internal development costs, external vendor fees, licensing costs
  - Employee Time: Hours spent in training, opportunity cost calculations
  - External Training: Conference registrations, tuition reimbursements, certification exam fees
  - ROI Calculations: Cost per learner, cost per completion, business impact metrics

  Data Volume Estimates:
  - 2,500 active users (employees)
  - 5,000+ historical user records (alumni, contractors)
  - 800+ unique courses and learning modules
  - 15,000+ individual content items (videos, documents, assessments)
  - 100,000+ enrollment records annually
  - 500,000+ course activity events per month
  - 50,000+ assessment submissions per month
  - 10,000+ discussion forum posts and comments per year
  - 2 TB storage for multimedia content

  Integration Sources:
  - HRIS (Workday, SAP SuccessFactors): Employee data, org structure, job roles
  - Identity Provider (Okta, Azure AD): Authentication, user provisioning
  - Calendar Systems (Google, Outlook): Training event scheduling
  - Video Platforms (YouTube, Vimeo): Hosted video content
  - Content Providers (LinkedIn Learning, Coursera): External course catalogs
  - Survey Tools (SurveyMonkey, Qualtrics): Training evaluations
  - Performance Management: Goal tracking, performance reviews
  - Expense Systems: Training-related expenses and reimbursements
  """,
  goal_target: :interface_view,
  expected_output: """
  A complete, enterprise-ready Learning Management System with the following components:

  1. Learner Portal (Web and Mobile):
  - Responsive web application accessible on desktop, tablet, and mobile browsers
  - Native iOS app supporting iPhone and iPad (iOS 14+)
  - Native Android app supporting phones and tablets (Android 10+)
  - Offline capability to download courses and sync progress when online
  - Personalized home dashboard showing:
    * Required training with urgency indicators and countdown timers
    * Recommended courses based on role, skills, and interests
    * In-progress courses with progress bars and estimated completion times
    * Upcoming live sessions and deadlines
    * Recent achievements, badges, and certifications earned
    * Learning leaderboard showing ranking among peers
  - Comprehensive course catalog with:
    * Advanced filtering and search (by topic, duration, format, skill level, language)
    * Course preview with sample content, syllabus, and learner reviews
    * Related courses and "learners also took" suggestions
    * Wishlist and save-for-later functionality
  - Engaging course player with:
    * Progress tracking and automatic bookmarking
    * Adjustable playback speed for videos
    * Picture-in-picture mode for multitasking
    * In-video quizzes and knowledge checks
    * Downloadable resources and supplementary materials
    * Note-taking with timestamps linked to course content
  - Skills and career development section:
    * Skills profile showing current proficiencies
    * Learning paths with milestone tracking
    * Career roadmap for current role and aspirational roles
    * Individual development plan (IDP) workspace
  - Social learning features:
    * Discussion forums with threading and voting
    * Study group creation and management
    * Direct messaging with instructors and peers
    * User profiles showcasing skills and achievements
  - Notifications center:
    * In-app, email, and push notifications for deadlines and updates
    * Customizable notification preferences
    * Digest emails for weekly learning summaries

  2. Administrator Console:
  - Comprehensive admin dashboard showing:
    * System health and performance metrics
    * Active users and concurrent sessions
    * Popular courses and trending topics
    * Compliance completion rates with drill-down by requirement
    * Upcoming training events and capacity status
  - User management:
    * Bulk user import/export via CSV
    * Individual user profile editing
    * Role and permission assignment (admin, instructor, learner, observer)
    * Organizational hierarchy visualization
    * User activity logs and audit trails
  - Course management:
    * Intuitive course builder with drag-and-drop interface
    * Rich text editor for descriptions and instructions
    * Multi-file upload with automatic transcoding for videos
    * SCORM 1.2, SCORM 2004, and xAPI compliance
    * Course prerequisites and equivalencies
    * Scheduled publishing and retirement of courses
    * Course duplication and template saving
  - Learning path builder:
    * Visual workflow designer for creating learning paths
    * Branching logic based on assessment results or user attributes
    * Prerequisites and recommended sequences
    * Path templates for common role-based journeys
  - Assessment tools:
    * Question bank management with categorization and tagging
    * Multiple question types (MCQ, true/false, matching, fill-in-blank, essay, file upload)
    * Random question selection and order shuffling
    * Partial credit and weighted scoring
    * Passing score thresholds and retry limits
    * Certification templates and digital badge design
  - Compliance management:
    * Automated assignment rules based on role, department, location
    * Deadline calculation and reminder automation
    * Compliance status dashboard by employee and requirement
    * Overdue training reports with escalation workflows
    * Attestation and acknowledgment tracking
    * Audit-ready reports for regulatory submissions
  - Analytics and reporting:
    * Pre-built report library for common metrics
    * Custom report builder with drag-and-drop fields
    * Real-time dashboards with filters and drill-down
    * Scheduled report delivery via email
    * Export to Excel, PDF, and CSV
    * Data visualization with charts, graphs, and heat maps
  - System configuration:
    * Branding customization (logo, colors, fonts)
    * Email template management
    * Integration settings (SSO, HRIS, calendar)
    * Security policies (password requirements, session timeouts)
    * Localization and multi-language support
    * Feature flags for gradual rollout

  3. Instructor Tools:
  - Instructor dashboard showing:
    * Assigned courses and enrollment numbers
    * Upcoming live sessions
    * Pending grading tasks
    * Recent learner questions and discussion activity
  - Virtual classroom integration:
    * Zoom or Microsoft Teams embedded experience
    * Attendance tracking with automatic roster sync
    * Session recording and automatic upload to course library
    * Chat and Q&A moderation tools
    * Screen sharing and breakout room management
  - Grading interface:
    * Queue of submissions requiring manual grading
    * Rubric-based scoring tools
    * Inline commenting and feedback
    * Bulk actions for common feedback
    * Grade release and notification
  - Communication tools:
    * Announcement creation and scheduling
    * Direct messaging with individual learners
    * Broadcast emails to course participants
    * Discussion forum moderation

  4. Manager Portal:
  - Team learning dashboard showing:
    * Team members' training compliance status
    * In-progress courses and completion percentages
    * Skills inventory and proficiency levels
    * Training hours and costs by team member
  - Learning assignment tools:
    * Assign courses to individuals or groups
    * Set custom deadlines
    * Add context and expectations
    * Track completion and receive notifications
  - Team development planning:
    * Identify skill gaps through skills matrix
    * Create team learning paths
    * Set team learning goals and track progress
  - Reports and analytics:
    * Team training activity summary
    * ROI analysis for team training investments
    * Comparison to peer teams and organizational benchmarks

  5. Content Library and Resource Center:
  - Searchable repository of training materials
  - Document version control
  - Tags and metadata for easy discovery
  - Usage analytics for each resource
  - Controlled access based on roles and permissions
  - Integration with corporate knowledge base

  6. Integration APIs and Connectors:
  - RESTful API with OAuth 2.0 authentication
  - Comprehensive API documentation with Swagger/OpenAPI
  - Pre-built connectors for:
    * Workday, SAP SuccessFactors, BambooHR (HRIS integration)
    * Okta, Azure AD, Auth0 (SSO and user provisioning)
    * Salesforce, HubSpot (for customer training scenarios)
    * Zoom, Microsoft Teams (virtual classroom)
    * Google Calendar, Outlook Calendar (scheduling)
  - Webhook support for real-time event notifications
  - Data export API for analytics and data warehousing
  - SCORM Cloud integration for external content hosting

  7. Technical Documentation and Support Materials:
  - System architecture documentation
  - Administrator guide with step-by-step instructions
  - User guide with screenshots and video tutorials
  - API documentation with code samples
  - FAQ and troubleshooting guide
  - Video tutorials for common tasks (15-20 videos)
  - Interactive product tours for first-time users
  - Change management toolkit:
    * Email templates for launch announcements
    * PowerPoint deck for executive presentations
    * Training session materials for super users
    * Infographics and quick reference guides

  Technical Requirements:
  - Frontend: Modern JavaScript framework (React, Vue.js, or Angular)
  - Mobile: React Native or Flutter for cross-platform apps
  - Backend: Scalable microservices architecture (Node.js, Python, or Java)
  - Database: PostgreSQL or MySQL with read replicas for high availability
  - Caching: Redis for session management and frequently accessed data
  - Storage: S3-compatible object storage for media files
  - Video: Adaptive bitrate streaming (HLS or DASH)
  - Search: Elasticsearch for full-text search
  - Analytics: Event tracking with Google Analytics or Mixpanel
  - Hosting: Cloud deployment on AWS, Azure, or Google Cloud
  - Security: SOC 2 Type II compliance, encryption at rest and in transit
  - Accessibility: WCAG 2.1 AA compliance
  - Performance: Page load under 2 seconds, support 1,000 concurrent users
  - Scalability: Horizontally scalable to support 10,000+ users

  Deliverables Timeline:
  - Phase 1 (Months 1-3): Core LMS with course catalog, learner portal, basic reporting
  - Phase 2 (Months 4-6): Mobile apps, learning paths, social features, compliance tools
  - Phase 3 (Months 7-9): Advanced analytics, AI recommendations, virtual classroom integration
  - Phase 4 (Months 10-12): Final testing, user training, migration, and launch support
  """,
  title: "New Need: Enterprise Learning Management System",
  description: "Build comprehensive LMS platform to centralize all employee training, professional development, and compliance tracking for 2,500 employees.",
  status: "pending",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

IO.puts("✅ Created 2 requests with extremely detailed content")
IO.puts("")
IO.puts("These requests contain:")
IO.puts("  - Very long current situation descriptions (multiple paragraphs)")
IO.puts("  - Comprehensive goal descriptions with detailed objectives")
IO.puts("  - Extensive data descriptions with categories and estimates")
IO.puts("  - Detailed expected output specifications")
IO.puts("")
IO.puts("Perfect for testing how the UI handles long content!")
IO.puts("")
IO.puts("Refresh your browser to see the new data!")
