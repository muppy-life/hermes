alias Hermes.Repo
alias Hermes.Accounts.{Team, User}
alias Hermes.Requests.Request

# Get all teams and users
teams = Repo.all(Team)
users = Repo.all(User) |> Repo.preload(:team)

# Topics for new requests
new_topics = [
  "New user authentication enhancement",
  "Mobile app push notifications",
  "Real-time dashboard updates",
  "Advanced search filters",
  "Bulk data import feature",
  "User profile customization",
  "Team collaboration tools",
  "Automated report generation",
  "API rate limiting improvements",
  "Database backup automation"
]

# Topics for completed requests
completed_topics = [
  "Email notification system",
  "User password reset flow",
  "CSV export functionality",
  "Performance optimization",
  "Security audit implementation",
  "Multi-language support",
  "Dark mode theme",
  "Two-factor authentication",
  "Activity log tracking",
  "Data migration tools"
]

current_situations = [
  "Current system lacks this capability",
  "Users have requested this feature multiple times",
  "This will improve overall system efficiency",
  "Required for compliance with new regulations",
  "Will enhance user experience significantly",
  "Needed for better data management",
  "Critical for system scalability"
]

goal_descriptions = [
  "Implement a robust and scalable solution",
  "Deliver a user-friendly interface",
  "Ensure high performance and reliability",
  "Meet security and compliance standards",
  "Provide seamless integration with existing systems",
  "Enable better collaboration and productivity"
]

expected_outputs = [
  "Fully functional feature with comprehensive tests",
  "Complete documentation and user guide",
  "Deployed to production with monitoring",
  "Performance improvement of at least 40%",
  "Enhanced security measures in place",
  "Positive user feedback and adoption"
]

IO.puts("🚀 Generating new and completed requests for all teams...")

# Generate 5 "new" requests per team
new_requests = Enum.flat_map(teams, fn team ->
  team_users = Enum.filter(users, &(&1.team_id == team.id))
  creator = Enum.random(team_users)
  other_teams = Enum.reject(teams, &(&1.id == team.id))

  Enum.map(0..4, fn idx ->
    topic = Enum.at(new_topics, idx)
    situation = Enum.random(current_situations)
    goal = Enum.random(goal_descriptions)
    output = Enum.random(expected_outputs)

    # 80% assigned to another team
    assigned_team = if :rand.uniform(100) <= 80 do
      Enum.random(other_teams)
    else
      nil
    end

    %Request{
      title: topic,
      description: "New request for #{topic}",
      kind: Enum.random([:new_need, :improvement, :problem]),
      target_user_type: if(rem(idx, 2) == 0, do: :internal, else: :external),
      current_situation: situation,
      goal_description: goal,
      data_description: "Relevant data and specifications for #{topic}",
      goal_target: Enum.random([:interface_view, :report_file, :alert_message]),
      expected_output: output,
      priority: Enum.random(2..4),
      status: "new",
      requesting_team_id: team.id,
      assigned_to_team_id: if(assigned_team, do: assigned_team.id, else: nil),
      created_by_id: creator.id
    }
  end)
end)

# Generate 5 "completed" requests per team
completed_requests = Enum.flat_map(teams, fn team ->
  team_users = Enum.filter(users, &(&1.team_id == team.id))
  creator = Enum.random(team_users)
  other_teams = Enum.reject(teams, &(&1.id == team.id))

  Enum.map(0..4, fn idx ->
    topic = Enum.at(completed_topics, idx)
    situation = Enum.random(current_situations)
    goal = Enum.random(goal_descriptions)
    output = Enum.random(expected_outputs)

    # 80% assigned to another team
    assigned_team = if :rand.uniform(100) <= 80 do
      Enum.random(other_teams)
    else
      nil
    end

    %Request{
      title: topic,
      description: "Completed: #{topic}",
      kind: Enum.random([:new_need, :improvement, :problem]),
      target_user_type: if(rem(idx, 2) == 0, do: :internal, else: :external),
      current_situation: situation,
      goal_description: goal,
      data_description: "Implementation details for #{topic}",
      goal_target: Enum.random([:interface_view, :report_file, :alert_message]),
      expected_output: output,
      priority: Enum.random(2..4),
      status: "completed",
      requesting_team_id: team.id,
      assigned_to_team_id: if(assigned_team, do: assigned_team.id, else: nil),
      created_by_id: creator.id
    }
  end)
end)

# Insert all requests
all_requests = new_requests ++ completed_requests

Enum.each(all_requests, fn request_attrs ->
  Repo.insert!(request_attrs)
end)

IO.puts("✅ Successfully created #{length(all_requests)} requests!")
IO.puts("📊 Breakdown:")
IO.puts("  New requests: #{length(new_requests)}")
IO.puts("  Completed requests: #{length(completed_requests)}")
IO.puts("\n📈 Per team:")

Enum.each(teams, fn team ->
  new_count = Enum.count(new_requests, &(&1.requesting_team_id == team.id))
  completed_count = Enum.count(completed_requests, &(&1.requesting_team_id == team.id))
  IO.puts("  #{team.name}: #{new_count} new, #{completed_count} completed")
end)
