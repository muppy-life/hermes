alias Hermes.Repo
alias Hermes.Accounts.{Team, User}
alias Hermes.Requests.Request

# Get all teams and users
teams = Repo.all(Team)
users = Repo.all(User) |> Repo.preload(:team)

# Request templates with variety
request_templates = [
  # New status requests
  %{kind: :new_need, status: "new", priority: 4, title_prefix: "Urgent new requirement:", target: :interface_view},
  %{kind: :new_need, status: "new", priority: 3, title_prefix: "New feature request:", target: :interface_view},
  %{kind: :new_need, status: "new", priority: 2, title_prefix: "New capability needed:", target: :report_file},
  %{kind: :problem, status: "new", priority: 4, title_prefix: "Critical issue:", target: :alert_message},
  %{kind: :problem, status: "new", priority: 3, title_prefix: "System problem:", target: :interface_view},

  # Pending status requests
  %{kind: :new_need, status: "pending", priority: 3, title_prefix: "Awaiting approval:", target: :interface_view},
  %{kind: :improvement, status: "pending", priority: 2, title_prefix: "Enhancement proposal:", target: :report_file},
  %{kind: :problem, status: "pending", priority: 3, title_prefix: "Issue to investigate:", target: :alert_message},

  # In Progress status requests
  %{kind: :new_need, status: "in_progress", priority: 4, title_prefix: "Building:", target: :interface_view},
  %{kind: :improvement, status: "in_progress", priority: 3, title_prefix: "Implementing:", target: :interface_view},
  %{kind: :problem, status: "in_progress", priority: 3, title_prefix: "Fixing:", target: :alert_message},

  # Review status requests
  %{kind: :new_need, status: "review", priority: 3, title_prefix: "Ready for review:", target: :interface_view},
  %{kind: :improvement, status: "review", priority: 2, title_prefix: "Under review:", target: :report_file},

  # Completed status requests
  %{kind: :new_need, status: "completed", priority: 3, title_prefix: "Delivered:", target: :interface_view},
  %{kind: :improvement, status: "completed", priority: 2, title_prefix: "Completed:", target: :report_file},

  # Blocked status requests
  %{kind: :problem, status: "blocked", priority: 4, title_prefix: "Blocked:", target: :alert_message},
  %{kind: :new_need, status: "blocked", priority: 3, title_prefix: "On hold:", target: :interface_view}
]

topics = [
  "user authentication system",
  "payment processing integration",
  "email notification service",
  "dashboard analytics",
  "mobile app optimization",
  "database performance",
  "API rate limiting",
  "search functionality",
  "user profile management",
  "file upload system",
  "reporting module",
  "data export feature",
  "third-party integration",
  "security audit",
  "performance monitoring",
  "backup system",
  "cache optimization",
  "documentation update",
  "test coverage",
  "deployment pipeline"
]

current_situations = [
  "Current system lacks this capability",
  "Users are experiencing issues with the existing functionality",
  "Manual process is time-consuming and error-prone",
  "System performance is degrading",
  "Security vulnerability identified",
  "Feature requested by multiple stakeholders",
  "Integration with new system required",
  "Compliance requirements need to be met"
]

goal_descriptions = [
  "Implement a robust solution that scales",
  "Fix the root cause and prevent future occurrences",
  "Automate the manual process",
  "Optimize performance to meet SLA requirements",
  "Enhance security measures",
  "Deliver user-friendly interface",
  "Integrate seamlessly with existing systems",
  "Ensure compliance with regulations"
]

expected_outputs = [
  "Fully functional feature with comprehensive tests",
  "Fixed issue with monitoring in place",
  "Automated workflow reducing manual work by 80%",
  "Performance improvement of at least 50%",
  "Security patch deployed to production",
  "New interface accessible to all users",
  "Working integration with third-party service",
  "Compliance documentation and audit trail"
]

# Function to generate requests for a team
defmodule RequestGenerator do
  def generate_for_team(team, all_teams, all_users, templates, topics, situations, goals, outputs) do
    # Get users from this team
    team_users = Enum.filter(all_users, &(&1.team_id == team.id))
    creator = Enum.random(team_users)

    # Get other teams for assignment
    other_teams = Enum.reject(all_teams, &(&1.id == team.id))

    # Generate 15 requests
    Enum.map(0..14, fn idx ->
      template = Enum.at(templates, rem(idx, length(templates)))
      topic = Enum.at(topics, rem(idx, length(topics)))
      situation = Enum.random(situations)
      goal = Enum.random(goals)
      output = Enum.random(outputs)

      # Assign to another team (80% of the time) or keep unassigned
      assigned_team = if :rand.uniform(100) <= 80 do
        Enum.random(other_teams)
      else
        nil
      end

      %Request{
        title: "#{template.title_prefix} #{topic}",
        description: "Request for #{topic} - Status: #{template.status}",
        kind: template.kind,
        target_user_type: if(rem(idx, 2) == 0, do: :internal, else: :external),
        current_situation: situation,
        goal_description: goal,
        data_description: "Relevant data including #{topic} specifications, requirements, and expected outcomes.",
        goal_target: template.target,
        expected_output: output,
        priority: template.priority,
        status: template.status,
        requesting_team_id: team.id,
        assigned_to_team_id: if(assigned_team, do: assigned_team.id, else: nil),
        created_by_id: creator.id
      }
    end)
  end
end

IO.puts("🚀 Generating 15 requests per team...")

all_requests = Enum.flat_map(teams, fn team ->
  RequestGenerator.generate_for_team(
    team,
    teams,
    users,
    request_templates,
    topics,
    current_situations,
    goal_descriptions,
    expected_outputs
  )
end)

# Insert all requests
Enum.each(all_requests, fn request_attrs ->
  Repo.insert!(request_attrs)
end)

IO.puts("✅ Successfully created #{length(all_requests)} requests!")
IO.puts("📊 Breakdown by team:")

Enum.each(teams, fn team ->
  count = Enum.count(all_requests, &(&1.requesting_team_id == team.id))
  IO.puts("  #{team.name}: #{count} requests")
end)

IO.puts("\n📈 Status distribution:")
statuses = ["new", "pending", "in_progress", "review", "completed", "blocked"]
Enum.each(statuses, fn status ->
  count = Enum.count(all_requests, &(&1.status == status))
  IO.puts("  #{status}: #{count} requests")
end)
