# Changelog

All notable changes to the Hermes project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Deadline Management Feature** (2024-11-24)
  - Added deadline field to requests table
  - Calendar modal for setting deadlines with month navigation
  - Authorization: only assigned team can set/change deadlines
  - Color-coded deadline badges with urgency indicators:
    - Red: Overdue
    - Orange: Today or 1-3 days
    - Yellow: 4-7 days
    - Purple: More than 7 days
  - Deadline display in:
    - Request details header
    - Dashboard recent requests cards
    - Backlog table as sortable column
  - Visual "Set Deadline" / "Change Deadline" button (accent color)

- **CI/CD Pipeline** (2024-11-24)
  - GitHub Actions workflow for automated testing and quality checks
  - Four parallel jobs:
    - Test suite with PostgreSQL 15
    - Asset compilation with Node.js
    - Security auditing (Sobelow, mix_audit)
    - Type checking (Dialyzer with PLT caching)
  - Code quality tool dependencies:
    - Credo 1.7 for static code analysis
    - Dialyxir 1.4 for type checking
    - Sobelow 0.14 for security analysis
    - mix_audit 2.1 for dependency vulnerability checking
  - Configuration files:
    - `.credo.exs` - Credo rules and settings
    - `.sobelow-conf` - Sobelow security configuration
    - `.github/workflows/ci.yml` - Main CI workflow
    - `.github/workflows/README.md` - CI documentation
  - Pre-commit alias in mix.exs for local checks

- **Kanban Board Analytics** (2024-11)
  - Real-time metrics and statistics on kanban boards
  - Team performance tracking
  - Request completion rates
  - Workload distribution visualization

- **Multi-Step Request Form** (2024-11)
  - Structured request submission process
  - Request type classification (problem, new_need, improvement)
  - User type targeting (internal, external)
  - Goal definition and expected output specification
  - Solution diagram upload support

- **Admin Dashboard** (2024-11)
  - User activity tracking (dev team only)
  - Real-time monitoring of system usage

### Changed
- Priority system updated from 5 levels to 4 levels (Low, Normal, Important, Critical)
- Status values expanded to include: new, pending, in_progress, review, completed, blocked
- Request model updated with multi-step form fields
- Dashboard enhanced with recent requests and analytics

### Removed
- Tidewave dependency (unused)

### Fixed
- Various warnings and test issues
- Seeds data quality improvements

## [0.1.0] - Initial Release

### Added
- Basic request management system
- Team-based access control
- Kanban board functionality
- User authentication and authorization
- Dashboard with request overview
- PostgreSQL database with Ecto
- Phoenix LiveView for real-time updates
- Tailwind CSS with DaisyUI components
- Background job processing with Oban
- ML model integration with Bumblebee (mT5)

[Unreleased]: https://github.com/muppy-life/hermes/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/muppy-life/hermes/releases/tag/v0.1.0
