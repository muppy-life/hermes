# Hermes Features Documentation

This document provides detailed information about all features available in the Hermes demand management system.

## Table of Contents
- [Request Management](#request-management)
- [Deadline Management](#deadline-management)
- [Kanban Boards](#kanban-boards)
- [Dashboard & Analytics](#dashboard--analytics)
- [User Roles & Permissions](#user-roles--permissions)
- [CI/CD & Code Quality](#cicd--code-quality)

## Request Management

### Multi-Step Request Form

Hermes uses a structured, multi-step form to capture all necessary information about a request:

#### Step 1: Request Type
- **Problem**: Issues with current applications or services
- **New Need**: Requirements for new functionality
- **Improvement**: Suggestions for enhancing existing features

#### Step 2: Target User
- **Internal User**: Company team members
- **External User**: Clients or external providers

#### Step 3: Current Situation
Describe the current state or problem that needs to be addressed.

#### Step 4: Goal Description
Define what you want to achieve with this request.

#### Step 5: Data Description
Specify what data is involved in the request.

#### Step 6: Goal Target
Select the type of output:
- **Interface/View**: Web pages, screens, UI components
- **Report File**: Documents, spreadsheets, exports
- **Alert/Message**: Notifications, emails, communications

#### Step 7: Expected Output
Describe the expected result or deliverable.

#### Step 8: Solution Diagram (Optional)
Upload or link to diagrams illustrating the proposed solution.

### Request Fields

- **Auto-generated Title**: Created from form data
- **Auto-generated Description**: Compiled from all form responses
- **Priority**: 4 levels (Low, Normal, Important, Critical)
- **Status**: New, Pending, In Progress, Review, Completed, Blocked
- **Deadline**: Optional due date (only settable by assigned team)
- **Requesting Team**: Team submitting the request
- **Assigned Team**: Team responsible for handling the request
- **Created By**: User who submitted the request

### Request Views

#### Dashboard Recent Requests
- Shows the 10 most recent requests
- Displays: ID, kind, title, priority, status, and deadline badges
- Quick access to request details

#### Backlog View
Three tabbed sections organized by status:
- **New**: Unassigned or newly submitted requests
- **Ongoing**: Requests in progress or under review
- **Completed**: Finished requests

Each table includes:
- Request ID
- Kind badge
- Title (clickable)
- Priority badge
- Status badge
- Requesting team
- Assigned team
- Deadline (sortable column)
- Actions (view/edit/delete)

#### Request Details
Comprehensive view showing:
- Full request information
- Kind, status, and priority badges
- Deadline badge (if set)
- Metadata sidebar with:
  - Requesting team
  - Assigned team
  - Created by
  - Created at
  - Deadline date
- Action buttons:
  - Edit Request
  - Delete Request
  - Set/Change Deadline (if authorized)

## Deadline Management

### Authorization
- Only members of the **assigned team** can set or change deadlines
- Requesting team members can view deadlines but cannot modify them
- This ensures accountability and prevents deadline manipulation

### Setting a Deadline

1. Navigate to a request details page
2. Click "Set Deadline" or "Change Deadline" button (accent/teal color)
3. Calendar modal opens with:
   - Current month display
   - Previous/Next month navigation
   - Past dates disabled (grayed out)
   - Today highlighted with border
   - Selected date highlighted in accent color
   - Cancel and Save buttons

### Visual Indicators

Deadline badges use color coding to show urgency:

| Color | Meaning | Days Until |
|-------|---------|------------|
| 🔴 Red | Overdue | Past deadline |
| 🟠 Orange (Dark) | Due today | 0 days |
| 🟠 Orange (Light) | Due very soon | 1-3 days |
| 🟡 Yellow | Due soon | 4-7 days |
| 🟣 Purple | Not urgent | 8+ days |

### Deadline Display Locations

Deadlines appear consistently across the application:
1. **Request Details Header**: Below title, alongside other badges
2. **Dashboard Cards**: In recent requests section
3. **Backlog Tables**: As a dedicated sortable column

### Calendar Features

- Month-based navigation with arrow buttons
- Past dates automatically disabled
- Visual highlighting for:
  - Current date (border highlight)
  - Selected date (accent background)
  - Past dates (opacity reduced)
- Date format: "MMM DD, YYYY" (e.g., "Dec 25, 2025")

## Kanban Boards

### Board Structure
- Each team has its own kanban board
- Customizable columns (default: Backlog, To Do, In Progress, Review, Done)
- Cards can be linked to requests

### Board Analytics

Real-time metrics displayed on each board:
- Total cards
- Cards per column
- Request completion rates
- Team workload distribution
- Progress visualization

### Access Control
- **Dev Team**: Can view all boards
- **Team Members**: Can only view their own team's board
- **Product Owners**: Can manage and prioritize across boards

## Dashboard & Analytics

### Main Dashboard

#### Quick Stats (Top Section)
- Total requests count
- New requests (pending assignment)
- In-progress requests
- Completed requests

#### Recent Requests (Middle Section)
- Last 10 requests with full details
- All badges visible (kind, priority, status, deadline)
- Quick navigation to details

#### Team Stats (Bottom Section)
- Requests by team
- Completion rates
- Current workload

### Admin Dashboard

**Access**: Dev team members only

Features:
- User activity tracking
- Real-time system usage
- Team performance overview
- Request flow analytics

## User Roles & Permissions

### Admin
- Full system access
- User management
- System configuration

### Dev Team
- View all requests and boards
- Access admin dashboard
- Manage any request
- Set deadlines for assigned requests

### Product Owner
- Prioritize requests
- View all requests
- Manage team assignments
- Cannot access admin features

### Team Member
- View own team's requests and board
- Submit new requests
- Edit own requests
- Set deadlines for requests assigned to their team

## CI/CD & Code Quality

### Automated Testing

The GitHub Actions pipeline runs on every push and pull request:

#### Test Job
- Elixir 1.15.7 / OTP 26.1
- PostgreSQL 15 service container
- Dependency caching
- Compile with warnings as errors
- Code formatting check
- Full test suite execution

#### Assets Job
- Node.js 18 setup
- npm dependency caching
- Asset compilation verification

#### Security Job
- `mix deps.audit`: Check for vulnerable dependencies
- `sobelow --config`: Security-focused static analysis
- Continues on error (informational)

#### Dialyzer Job
- Static type analysis
- PLT caching for faster builds
- Continues on error (informational)

### Local Development

#### Pre-commit Check
Run all checks before committing:
```bash
mix precommit
```

This runs:
- `mix compile --warnings-as-errors`
- `mix deps.unlock --unused`
- `mix format`
- `mix test`

#### Individual Checks

```bash
# Code formatting
mix format

# Static analysis
mix credo --strict

# Type checking
mix dialyzer

# Security audit
mix sobelow --config

# Dependency vulnerabilities
mix deps.audit
```

### Configuration Files

- **`.credo.exs`**: Credo rules and check configuration
- **`.sobelow-conf`**: Sobelow security settings
- **`.github/workflows/ci.yml`**: GitHub Actions workflow
- **`.github/workflows/README.md`**: CI/CD documentation

### Code Quality Tools

| Tool | Purpose | Version |
|------|---------|---------|
| Credo | Static code analysis | 1.7 |
| Dialyxir | Type checking | 1.4 |
| Sobelow | Security analysis | 0.14 |
| mix_audit | Dependency auditing | 2.1 |

## Future Enhancements

### Planned Features

1. **Notifications**
   - Email notifications for new requests
   - Deadline approaching reminders
   - Status change notifications

2. **Request Templates**
   - Pre-defined request templates
   - Custom templates per team
   - Template library

3. **Time Tracking**
   - Estimate vs. actual time
   - Time logging per request
   - Burndown charts

4. **File Attachments**
   - Upload supporting documents
   - Image attachments for requests
   - Version control for files

5. **Comments & Discussion**
   - Comment threads on requests
   - @mentions for team members
   - Activity feed

6. **Advanced Filtering**
   - Multi-criteria filters
   - Saved filter presets
   - Search across all fields

7. **Export & Reporting**
   - Export requests to CSV/Excel
   - Custom report generation
   - Scheduled report delivery

## Technical Implementation Notes

### Deadline Feature Implementation

**Database**:
- Field: `deadline :date` (nullable)
- Migration: `20251124150430_add_deadline_to_requests.exs`

**Authorization Logic**:
```elixir
can_set_deadline = request.assigned_to_team_id == current_user.team_id
```

**Component**:
- `deadline_badge/1` in `lib/hermes_web/components/core_components.ex`
- Dynamic color calculation based on `Date.diff/2`

**LiveView Events**:
- `open_deadline_modal`: Opens calendar
- `close_deadline_modal`: Closes without saving
- `update_selected_date`: Changes selected date
- `save_deadline`: Updates request with new deadline

### ML Integration

- **Model**: mT5 multilingual summarization
- **Library**: Bumblebee 0.6 with Nx 0.9
- **Use Case**: Intelligent request summarization and diagram generation
- **Loading**: Background process on application start
