# Hermes - Team Request Management System

Hermes is a demand management application built with Elixir, Phoenix, and LiveView. It helps software development teams manage requests from other teams, organize work in kanban boards, and track progress effectively.

## Features

### Core Functionality
- **Multi-Step Request Form**: Structured request submission with problem classification, user targeting, and goal definition
- **Request Management**: Comprehensive request tracking with detailed descriptions, priorities, status, and deadlines
- **Deadline Management**: Set and track request deadlines with visual urgency indicators (only assignable by the assigned team)
- **Kanban Boards**: Visualize work progress across different teams with customizable kanban boards
- **Analytics & Metrics**: Real-time team performance metrics, completion rates, and workload distribution
- **Role-Based Access Control**:
  - Dev team members can see all boards and requests
  - Team members can only see their own team's board and related requests
  - Product owners can prioritize and manage requests
- **Dashboard**: Overview of requests, statistics, recent activity, and quick access to boards
- **Priority System**: 4-level priority system (1-4: Low, Normal, Important, Critical)
- **Status Tracking**: Track requests through new, pending, in_progress, review, completed, and blocked states
- **AI-Powered Features**: ML model integration for intelligent request summarization and diagram generation

## Technology Stack

- **Elixir 1.15+**: Functional programming language
- **Phoenix Framework 1.8**: Web framework
- **Phoenix LiveView 1.1**: Real-time UI updates without JavaScript
- **PostgreSQL 14+**: Database
- **Tailwind CSS 4.1**: Styling with DaisyUI components
- **Oban 2.18**: Background job processing
- **Bumblebee 0.6**: ML model integration (mT5 multilingual summarization)
- **Nx 0.9**: Numerical computing for ML features
- **GitHub Actions**: CI/CD pipeline with automated testing and code quality checks

## Prerequisites

- Elixir 1.15 or higher
- Erlang/OTP 26 or higher
- PostgreSQL 14 or higher
- Node.js 18 or higher (for asset compilation)

## Getting Started

### 1. Install Dependencies

```bash
mix deps.get
cd assets && npm install && cd ..
```

### 2. Start PostgreSQL Database

The project includes a helper script to run PostgreSQL in Docker (uses port 5433 to avoid conflicts):

```bash
# Start PostgreSQL
./scripts/db.sh start

# Check status
./scripts/db.sh status

# Stop when done
./scripts/db.sh stop
```

**Alternative**: If you have PostgreSQL installed locally, make sure it's running and update `config/dev.exs` with your connection details.

### 3. Create and Setup Database

```bash
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs
```

### 4. Start the Application

```bash
mix phx.server
```

Or start it inside IEx (Interactive Elixir) for debugging:

```bash
iex -S mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Sample Data

The seed file creates sample teams and users for testing:

### Teams
- Development Team
- Marketing Team
- Sales Team
- HR Team

### Sample Users
| Email | Role | Team |
|-------|------|------|
| dev@hermes.com | dev_team | Development Team |
| po@hermes.com | product_owner | Development Team |
| marketing@hermes.com | team_member | Marketing Team |
| sales@hermes.com | team_member | Sales Team |
| hr@hermes.com | team_member | HR Team |

**Note**: This MVP uses placeholder passwords for demonstration. In production, implement proper authentication with password hashing using libraries like `bcrypt_elixir` or `argon2_elixir`.

## Application Structure

```
lib/
├── hermes/
│   ├── accounts/          # User and team management
│   │   ├── user.ex
│   │   └── team.ex
│   ├── requests/          # Request management
│   │   └── request.ex
│   ├── kanbans/           # Kanban board management
│   │   ├── board.ex
│   │   ├── column.ex
│   │   └── card.ex
│   ├── accounts.ex        # Accounts context
│   ├── requests.ex        # Requests context
│   └── kanbans.ex         # Kanbans context
├── hermes_web/
│   ├── live/
│   │   ├── dashboard_live.ex        # Dashboard view
│   │   ├── request_live/            # Request management
│   │   │   ├── index.ex
│   │   │   ├── index.html.heex
│   │   │   └── form_component.ex
│   │   └── kanban_live/             # Kanban boards
│   │       ├── index.ex
│   │       ├── index.html.heex
│   │       ├── board.ex
│   │       └── board.html.heex
│   └── router.ex
```

## Database Schema

### Teams
- `name`: Team name
- `description`: Team description

### Users
- `email`: User email (unique)
- `hashed_password`: Encrypted password
- `role`: User role (admin, dev_team, product_owner, team_member)
- `team_id`: Reference to team

### Requests
- `title`: Request title (auto-generated from form data)
- `description`: Detailed description (auto-generated from form data)
- `priority`: Priority level (1-4: Low, Normal, Important, Critical)
- `status`: Current status (new, pending, in_progress, review, completed, blocked)
- `deadline`: Optional deadline date (only settable by assigned team)
- **Multi-step form fields:**
  - `kind`: Request type (problem, new_need, improvement)
  - `target_user_type`: User type (internal, external)
  - `current_situation`: Description of current situation
  - `goal_description`: Description of desired goal
  - `data_description`: Data involved in the request
  - `goal_target`: Output type (interface_view, report_file, alert_message)
  - `expected_output`: Description of expected result
  - `solution_diagram`: Optional diagram URL
- `requesting_team_id`: Team making the request
- `assigned_to_team_id`: Team assigned to handle the request
- `created_by_id`: User who created the request

### Kanban Boards
- `name`: Board name
- `team_id`: Team owning the board

### Kanban Columns
- `name`: Column name (e.g., "Backlog", "To Do", "In Progress", "Review", "Done")
- `position`: Column order
- `board_id`: Reference to board

### Kanban Cards
- `title`: Card title
- `description`: Card description
- `position`: Card position within column
- `column_id`: Reference to column
- `request_id`: Optional reference to a request

## Routes

- `/` - Dashboard with recent requests and quick stats
- `/requests` - Backlog view (all requests organized by status)
- `/requests/new` - Create new request (multi-step form)
- `/requests/:id` - View request details (with deadline management)
- `/requests/:id/edit` - Edit request
- `/boards` - View all kanban boards
- `/boards/:id` - View specific kanban board with analytics
- `/admin` - Admin dashboard (dev team only) with user activity tracking

## Future Enhancements

This is an MVP. Consider these enhancements for production:

1. **Authentication & Authorization**
   - Implement proper user authentication (e.g., using `phx.gen.auth`)
   - Add password hashing (bcrypt/argon2)
   - Implement session management
   - Add forgot password functionality

2. **Kanban Improvements**
   - Drag-and-drop functionality for cards (using JavaScript hooks)
   - Card assignment to specific users
   - Comments on cards
   - File attachments

3. **Request Features**
   - ✅ Request deadlines with visual indicators (completed)
   - Request approval workflow
   - Email notifications for deadline approaching/overdue
   - Request templates
   - Time tracking
   - Request history/audit log
   - Deadline reminder notifications

4. **Reporting & Analytics**
   - ✅ Team performance metrics (completed)
   - ✅ Request completion rates (completed)
   - ✅ Kanban board analytics (completed)
   - Time-to-completion analytics
   - Custom reports
   - Export functionality

5. **UI/UX**
   - Dark mode
   - Customizable dashboards
   - Advanced filtering and search
   - Bulk operations

6. **Integration**
   - Email notifications
   - Slack/Teams integration
   - Calendar integration
   - API for external systems

## Development

### Database Script Commands

The `scripts/db.sh` script provides convenient PostgreSQL management:

```bash
./scripts/db.sh start    # Start PostgreSQL container
./scripts/db.sh stop     # Stop PostgreSQL container
./scripts/db.sh restart  # Restart PostgreSQL container
./scripts/db.sh status   # Check container status
./scripts/db.sh logs     # View container logs
./scripts/db.sh psql     # Connect to PostgreSQL using psql
./scripts/db.sh rm       # Remove container (keeps data)
./scripts/db.sh clean    # Remove container AND data (WARNING!)
```

**Database Connection Details:**
- Host: localhost
- Port: 5433 (custom port)
- User: postgres
- Password: postgres
- Database: hermes_dev

### Running Tests

```bash
mix test
```

### Code Quality & CI/CD

The project includes a comprehensive CI/CD pipeline with automated code quality checks:

```bash
# Run all pre-commit checks (recommended before committing)
mix precommit

# Individual quality checks
mix format              # Format code
mix credo --strict      # Static code analysis
mix dialyzer           # Type checking
mix sobelow --config   # Security analysis
mix deps.audit         # Check for vulnerable dependencies
```

The GitHub Actions CI pipeline automatically runs on every push and pull request with parallel jobs for:
- Testing (with PostgreSQL)
- Asset compilation
- Security auditing (Sobelow, mix_audit)
- Type checking (Dialyzer)

See `.github/workflows/README.md` for detailed CI/CD documentation.

### Database Operations

```bash
# Reset database
mix ecto.reset

# Create new migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback
```

## Production Deployment

For production deployment, please check the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

Key considerations:
- Set up proper authentication
- Use environment variables for secrets
- Configure SSL/TLS
- Set up database backups
- Configure logging and monitoring
- Use a proper secret key base

## License

This project is licensed under the MIT License.

## Learn More

- Official Phoenix website: https://www.phoenixframework.org/
- Phoenix Guides: https://hexdocs.pm/phoenix/overview.html
- Phoenix Docs: https://hexdocs.pm/phoenix
- Phoenix LiveView: https://hexdocs.pm/phoenix_live_view
- Elixir Forum: https://elixirforum.com/c/phoenix-forum
