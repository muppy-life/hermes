# Script to add additional testing data for better visualization
# Run with: mix run priv/repo/add_test_data.exs

alias Hermes.Repo
alias Hermes.Accounts.{Team, User}
alias Hermes.Kanbans.{Board, Column, Card}
alias Hermes.Requests.Request

IO.puts("Adding additional test data...")

# Get existing teams and users
dev_team = Repo.get_by!(Team, name: "Development Team")
marketing_team = Repo.get_by!(Team, name: "Marketing Team")
sales_team = Repo.get_by!(Team, name: "Sales Team")
hr_team = Repo.get_by!(Team, name: "HR Team")

dev_user = Repo.get_by!(User, email: "dev@hermes.com")
marketing_user = Repo.get_by!(User, email: "marketing@hermes.com")
sales_user = Repo.get_by!(User, email: "sales@hermes.com")
hr_user = Repo.get_by!(User, email: "hr@hermes.com")

# Add more requests from different teams
IO.puts("Creating additional requests...")

request6 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 3,
  target_user_type: :external,
  current_situation: "Our mobile app needs a complete UI refresh to match our new brand identity. The current design is outdated and doesn't align with our rebranding efforts.",
  goal_description: "Create a modern, cohesive mobile app design that matches our new brand identity with updated color scheme, typography, and improved navigation patterns.",
  data_description: "User interface mockups, brand guidelines, color palettes, typography specifications",
  goal_target: :interface_view,
  expected_output: "Complete mobile app UI redesign with all screens updated to match new brand identity. Should include design system documentation and implementation guidelines.",
  title: "New Need: Mobile app UI redesign",
  description: "Our mobile app needs a complete UI refresh to match our new brand identity. Should include new color scheme, typography, and improved navigation.",
  status: "in_progress",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

request7 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 3,
  target_user_type: :external,
  current_situation: "We currently have no way to collect structured customer feedback on our platform. Customer satisfaction data is scattered across emails and support tickets.",
  goal_description: "Implement a feedback widget that allows customers to rate their experience and provide comments on key pages throughout the platform.",
  data_description: "Customer satisfaction scores (1-5), text comments, page context, user information",
  goal_target: :interface_view,
  expected_output: "An interactive feedback widget integrated on key pages, with a backend dashboard to view and analyze collected feedback data.",
  title: "New Need: Customer feedback widget",
  description: "Add a feedback widget to collect customer satisfaction scores and comments on key pages.",
  status: "pending",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

request8 = Repo.insert!(%Request{
  kind: :problem,
  priority: 4,
  target_user_type: :external,
  current_situation: "Our public API has no rate limiting, making it vulnerable to abuse. Some clients are making excessive requests which impacts performance for all users.",
  goal_description: "Implement intelligent rate limiting for the public API that prevents abuse while allowing legitimate usage. Should include different tiers for different subscription levels.",
  data_description: "API request logs, client authentication tokens, subscription tier information, rate limit configurations",
  goal_target: :interface_view,
  expected_output: "Rate limiting middleware integrated into the API with configurable limits per tier, monitoring dashboard showing API usage patterns, and clear error messages for clients exceeding limits.",
  title: "Problem: API rate limiting implementation",
  description: "Implement rate limiting for our public API to prevent abuse and ensure fair usage across all clients.",
  status: "in_progress",
  requesting_team_id: dev_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: dev_user.id
})

request9 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 3,
  target_user_type: :internal,
  current_situation: "New hires currently receive onboarding information manually via individual emails. This process is time-consuming and inconsistent across different hires.",
  goal_description: "Create an automated email sequence that sends timely onboarding information to new hires at key milestones: first day, first week, and first month.",
  data_description: "Employee data, onboarding milestone dates, email templates, company resources links",
  goal_target: :alert_message,
  expected_output: "Automated email system that triggers onboarding emails based on hire date, with customizable templates for each milestone and tracking of email delivery.",
  title: "New Need: Automated onboarding emails",
  description: "Set up automated email sequence for new hires covering first day, first week, and first month milestones.",
  status: "pending",
  requesting_team_id: hr_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: hr_user.id
})

request10 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 4,
  target_user_type: :internal,
  current_situation: "Sales reports can only be viewed on-screen. The sales team frequently needs to share reports with stakeholders in various formats but has to manually copy data.",
  goal_description: "Add export functionality to generate sales reports as downloadable PDF and Excel files with custom date ranges and applied filters.",
  data_description: "Sales transaction data, customer information, date ranges, filter parameters, report templates",
  goal_target: :report_file,
  expected_output: "Export buttons on sales reports page that generate professionally formatted PDF and Excel files containing filtered data with charts and summaries.",
  title: "New Need: Sales report export functionality",
  description: "Add ability to export sales reports as PDF and Excel files with custom date ranges and filters.",
  status: "pending",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

request11 = Repo.insert!(%Request{
  kind: :improvement,
  priority: 4,
  target_user_type: :external,
  current_situation: "Our website has accessibility issues that prevent users with disabilities from effectively navigating and using our services. We're not compliant with WCAG 2.1 AA standards.",
  goal_description: "Improve website accessibility to meet WCAG 2.1 AA standards, focusing on keyboard navigation, screen reader compatibility, and proper color contrast ratios.",
  data_description: "Accessibility audit results, WCAG guidelines, user testing feedback, color contrast measurements",
  goal_target: :interface_view,
  expected_output: "Fully accessible website meeting WCAG 2.1 AA standards with documented compliance, improved keyboard navigation, enhanced screen reader support, and compliant color schemes.",
  title: "Improvement: Website accessibility improvements",
  description: "Improve website accessibility to meet WCAG 2.1 AA standards. Focus on keyboard navigation, screen reader support, and color contrast.",
  status: "pending",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

request12 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 2,
  target_user_type: :internal,
  current_situation: "Marketing materials inventory is currently tracked manually in spreadsheets. We often run out of promotional items without warning or discover expired brochures.",
  goal_description: "Build a digital inventory tracking system for marketing materials including promotional items, brochures, and event supplies with automated low-stock alerts.",
  data_description: "Inventory items, quantities, locations, expiration dates, reorder thresholds, supplier information",
  goal_target: :interface_view,
  expected_output: "Web-based inventory management interface with real-time stock levels, automated alerts for low inventory, expiration tracking, and reporting capabilities.",
  title: "New Need: Inventory tracking system",
  description: "Need a system to track marketing materials inventory including promotional items, brochures, and event supplies.",
  status: "pending",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

request13 = Repo.insert!(%Request{
  kind: :improvement,
  priority: 4,
  target_user_type: :internal,
  current_situation: "User accounts currently only use password authentication, which is vulnerable to credential theft and unauthorized access. We need stronger security measures.",
  goal_description: "Implement two-factor authentication for all user accounts using authenticator apps as primary method with SMS as backup option.",
  data_description: "User credentials, authenticator app tokens, phone numbers, backup codes, authentication logs",
  goal_target: :interface_view,
  expected_output: "2FA setup interface, authentication flow integrated into login process, backup code generation, and support for multiple authenticator apps and SMS delivery.",
  title: "Improvement: Two-factor authentication",
  description: "Implement 2FA for all user accounts to improve security. Should support authenticator apps and SMS backup.",
  status: "blocked",
  requesting_team_id: dev_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: dev_user.id
})

request14 = Repo.insert!(%Request{
  kind: :problem,
  priority: 4,
  target_user_type: :external,
  current_situation: "The homepage is loading very slowly (5+ seconds), causing poor user experience and high bounce rates. Large images and JavaScript bundles are the main culprits.",
  goal_description: "Optimize homepage performance to achieve sub-2-second load times through image optimization, JavaScript bundle reduction, and lazy loading implementation.",
  data_description: "Performance metrics, image assets, JavaScript bundles, loading time analytics, Core Web Vitals data",
  goal_target: :interface_view,
  expected_output: "Optimized homepage with compressed images, reduced JavaScript bundle size, implemented lazy loading, and documented performance improvements showing load times under 2 seconds.",
  title: "Problem: Performance optimization - homepage",
  description: "Homepage is loading slowly. Need to optimize images, reduce JavaScript bundle size, and implement lazy loading.",
  status: "completed",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

request15 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 2,
  target_user_type: :internal,
  current_situation: "Team availability is scattered across different calendar systems (Google Calendar, Outlook). Scheduling meetings requires manually checking multiple calendars.",
  goal_description: "Integrate with Google Calendar and Outlook to display unified team availability and streamline meeting scheduling across different calendar platforms.",
  data_description: "Calendar events, team member availability, meeting room bookings, calendar API credentials",
  goal_target: :interface_view,
  expected_output: "Integrated calendar view showing team availability from both Google Calendar and Outlook, with ability to schedule meetings that sync across all platforms.",
  title: "New Need: Team calendar integration",
  description: "Integrate with Google Calendar and Outlook to show team availability and schedule meetings.",
  status: "pending",
  requesting_team_id: hr_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: hr_user.id
})

request16 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 4,
  target_user_type: :internal,
  current_situation: "Customer support issues are tracked in email threads and spreadsheets, making it difficult to track issue status, response times, and resolution patterns.",
  goal_description: "Build a comprehensive ticketing system for the customer support team to efficiently track, manage, and resolve customer issues with proper status tracking and reporting.",
  data_description: "Support tickets, customer information, issue categories, priority levels, response times, resolution notes",
  goal_target: :interface_view,
  expected_output: "Full-featured ticketing system with ticket creation, assignment, status tracking, customer communication history, SLA monitoring, and reporting dashboard.",
  title: "New Need: Customer support ticketing system",
  description: "Build internal ticketing system for customer support team to track and resolve customer issues.",
  status: "in_progress",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

request17 = Repo.insert!(%Request{
  kind: :improvement,
  priority: 2,
  target_user_type: :internal,
  current_situation: "The application only supports a light theme, which can cause eye strain for users working in low-light conditions or who prefer dark interfaces.",
  goal_description: "Add dark mode theme option that respects system preferences and allows manual toggle between light and dark themes throughout the application.",
  data_description: "UI color schemes, theme preferences, system settings, user preferences database",
  goal_target: :interface_view,
  expected_output: "Complete dark mode theme implementation with toggle switch in settings, automatic system preference detection, and persistent user preference storage.",
  title: "Improvement: Dark mode support",
  description: "Add dark mode theme option for the application. Should respect system preferences and allow manual toggle.",
  status: "pending",
  requesting_team_id: dev_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: dev_user.id
})

request18 = Repo.insert!(%Request{
  kind: :new_need,
  priority: 4,
  target_user_type: :internal,
  current_situation: "Quarterly performance reviews are conducted using paper forms and Word documents, making it difficult to track completion, maintain historical records, and analyze trends.",
  goal_description: "Create a digital performance review system that guides managers and employees through the quarterly review process with structured forms and historical tracking.",
  data_description: "Employee data, review criteria, performance goals, feedback history, rating scales, review cycle dates",
  goal_target: :interface_view,
  expected_output: "Comprehensive performance review platform with digital forms, automated review cycle scheduling, progress tracking, historical record keeping, and analytics dashboard.",
  title: "New Need: Quarterly performance review system",
  description: "Digital system for conducting and tracking quarterly performance reviews for all employees.",
  status: "pending",
  requesting_team_id: hr_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: hr_user.id
})

IO.puts("✅ Created #{13} additional requests")

# Get the dev board and its columns
dev_board = Repo.get_by!(Board, name: "Development Sprint Board") |> Repo.preload(:columns)
columns = dev_board.columns |> Enum.sort_by(& &1.position)

[backlog, todo, in_progress, review, done] = columns

# Add cards to the kanban board
IO.puts("Creating additional kanban cards...")

Repo.insert!(%Card{
  title: "Mobile app UI redesign",
  description: "High priority - new brand identity",
  position: 1,
  column_id: in_progress.id,
  request_id: request6.id
})

Repo.insert!(%Card{
  title: "Customer feedback widget",
  description: "Sales team request",
  position: 2,
  column_id: backlog.id,
  request_id: request7.id
})

Repo.insert!(%Card{
  title: "API rate limiting",
  description: "Prevent API abuse",
  position: 2,
  column_id: in_progress.id,
  request_id: request8.id
})

Repo.insert!(%Card{
  title: "Automated onboarding emails",
  description: "HR automation request",
  position: 3,
  column_id: backlog.id,
  request_id: request9.id
})

Repo.insert!(%Card{
  title: "Sales report export",
  description: "PDF and Excel export",
  position: 1,
  column_id: todo.id,
  request_id: request10.id
})

Repo.insert!(%Card{
  title: "Accessibility improvements",
  description: "WCAG 2.1 AA compliance",
  position: 4,
  column_id: backlog.id,
  request_id: request11.id
})

Repo.insert!(%Card{
  title: "Inventory tracking",
  description: "Marketing materials tracking",
  position: 5,
  column_id: backlog.id,
  request_id: request12.id
})

Repo.insert!(%Card{
  title: "Two-factor authentication",
  description: "BLOCKED: Waiting on SMS provider",
  position: 0,
  column_id: review.id,
  request_id: request13.id
})

Repo.insert!(%Card{
  title: "Homepage performance",
  description: "Optimization complete",
  position: 1,
  column_id: done.id,
  request_id: request14.id
})

Repo.insert!(%Card{
  title: "Calendar integration",
  description: "Google & Outlook sync",
  position: 6,
  column_id: backlog.id,
  request_id: request15.id
})

Repo.insert!(%Card{
  title: "Support ticketing system",
  description: "High priority customer support tool",
  position: 3,
  column_id: in_progress.id,
  request_id: request16.id
})

Repo.insert!(%Card{
  title: "Dark mode support",
  description: "Theme toggle feature",
  position: 2,
  column_id: todo.id,
  request_id: request17.id
})

Repo.insert!(%Card{
  title: "Performance review system",
  description: "Quarterly review tracking",
  position: 3,
  column_id: todo.id,
  request_id: request18.id
})

IO.puts("✅ Created #{13} additional kanban cards")

# Create additional boards for Marketing and Sales teams
IO.puts("Setting up boards for Marketing and Sales teams...")

marketing_board = Repo.get_by!(Board, name: "Marketing Campaigns")
sales_board = Repo.get_by!(Board, name: "Sales Pipeline")

# Add columns to marketing board
marketing_backlog = Repo.insert!(%Column{
  name: "Ideas",
  position: 0,
  board_id: marketing_board.id
})

marketing_planning = Repo.insert!(%Column{
  name: "Planning",
  position: 1,
  board_id: marketing_board.id
})

marketing_in_progress = Repo.insert!(%Column{
  name: "In Progress",
  position: 2,
  board_id: marketing_board.id
})

marketing_review = Repo.insert!(%Column{
  name: "Review",
  position: 3,
  board_id: marketing_board.id
})

marketing_done = Repo.insert!(%Column{
  name: "Launched",
  position: 4,
  board_id: marketing_board.id
})

# Add marketing cards
Repo.insert!(%Card{
  title: "Q1 Email Campaign",
  description: "Product launch announcement",
  position: 0,
  column_id: marketing_in_progress.id
})

Repo.insert!(%Card{
  title: "Social Media Strategy",
  description: "LinkedIn and Twitter presence",
  position: 1,
  column_id: marketing_in_progress.id
})

Repo.insert!(%Card{
  title: "Customer Case Studies",
  description: "Interview 3 key customers",
  position: 0,
  column_id: marketing_planning.id
})

Repo.insert!(%Card{
  title: "Blog Content Calendar",
  description: "Plan next 3 months",
  position: 0,
  column_id: marketing_backlog.id
})

Repo.insert!(%Card{
  title: "Website Redesign Launch",
  description: "New brand identity rollout",
  position: 0,
  column_id: marketing_done.id
})

# Add columns to sales board
sales_prospecting = Repo.insert!(%Column{
  name: "Prospecting",
  position: 0,
  board_id: sales_board.id
})

sales_qualified = Repo.insert!(%Column{
  name: "Qualified",
  position: 1,
  board_id: sales_board.id
})

sales_proposal = Repo.insert!(%Column{
  name: "Proposal",
  position: 2,
  board_id: sales_board.id
})

sales_negotiation = Repo.insert!(%Column{
  name: "Negotiation",
  position: 3,
  board_id: sales_board.id
})

sales_closed = Repo.insert!(%Column{
  name: "Closed Won",
  position: 4,
  board_id: sales_board.id
})

# Add sales pipeline cards
Repo.insert!(%Card{
  title: "Acme Corp - Enterprise Deal",
  description: "$50K annual contract",
  position: 0,
  column_id: sales_negotiation.id
})

Repo.insert!(%Card{
  title: "TechStart Inc - Starter Plan",
  description: "$5K pilot project",
  position: 0,
  column_id: sales_proposal.id
})

Repo.insert!(%Card{
  title: "Global Industries - Multi-year",
  description: "$150K 3-year agreement",
  position: 0,
  column_id: sales_qualified.id
})

Repo.insert!(%Card{
  title: "Small Business Co",
  description: "$2K monthly subscription",
  position: 0,
  column_id: sales_prospecting.id
})

Repo.insert!(%Card{
  title: "MegaCorp Partnership",
  description: "$200K strategic partnership",
  position: 0,
  column_id: sales_closed.id
})

Repo.insert!(%Card{
  title: "StartupXYZ",
  description: "$8K annual license",
  position: 1,
  column_id: sales_prospecting.id
})

IO.puts("✅ Created columns and cards for Marketing and Sales boards")

IO.puts("")
IO.puts("🎉 Test data setup complete!")
IO.puts("")
IO.puts("Summary:")
IO.puts("  - 18 total requests (5 original + 13 new)")
IO.puts("  - 23 total kanban cards across all boards")
IO.puts("  - 3 fully configured boards (Dev, Marketing, Sales)")
IO.puts("  - Multiple priorities and statuses for testing")
IO.puts("")
IO.puts("Refresh your browser to see the new data!")
