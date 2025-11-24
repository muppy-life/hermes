# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Hermes.Repo.insert!(%Hermes.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Hermes.Repo
alias Hermes.Accounts.{Team, User}
alias Hermes.Requests.{Request, RequestChange, RequestComment}

# Clear existing data (optional - comment out if you want to keep existing data)
Repo.delete_all(RequestComment)
Repo.delete_all(RequestChange)
Repo.delete_all(Request)
Repo.delete_all(User)
Repo.delete_all(Team)

# Create teams
dev_team =
  Repo.insert!(%Team{
    name: "Development Team",
    description: "Internal development team"
  })

marketing_team =
  Repo.insert!(%Team{
    name: "Marketing Team",
    description: "Marketing and communications team"
  })

sales_team =
  Repo.insert!(%Team{
    name: "Sales Team",
    description: "Sales and customer relations team"
  })

hr_team =
  Repo.insert!(%Team{
    name: "HR Team",
    description: "Human resources team"
  })

# Create users (Note: In production, you should hash passwords properly)
# For this MVP, we're using a simple placeholder password
dev_user =
  Repo.insert!(%User{
    email: "dev@hermes.com",
    # In production, use proper password hashing
    hashed_password: "dev123",
    role: "dev_team",
    team_id: dev_team.id
  })

product_owner =
  Repo.insert!(%User{
    email: "po@hermes.com",
    hashed_password: "po123",
    role: "product_owner",
    team_id: dev_team.id
  })

marketing_user =
  Repo.insert!(%User{
    email: "marketing@hermes.com",
    hashed_password: "marketing123",
    role: "team_member",
    team_id: marketing_team.id
  })

sales_user =
  Repo.insert!(%User{
    email: "sales@hermes.com",
    hashed_password: "sales123",
    role: "team_member",
    team_id: sales_team.id
  })

hr_user =
  Repo.insert!(%User{
    email: "hr@hermes.com",
    hashed_password: "hr123",
    role: "team_member",
    team_id: hr_team.id
  })

# Helper function to create request with changes and comments
defmodule SeedHelper do
  def create_request_with_history(attrs, creator_id, changes \\ [], comments \\ []) do
    request = Hermes.Repo.insert!(struct(Hermes.Requests.Request, attrs))

    # Create initial change
    Hermes.Repo.insert!(%Hermes.Requests.RequestChange{
      request_id: request.id,
      user_id: creator_id,
      action: "created",
      changes: %{},
      inserted_at: NaiveDateTime.add(request.inserted_at, -3600, :second)
    })

    # Create additional changes
    Enum.each(changes, fn {field, old_val, new_val, user_id, days_ago} ->
      Hermes.Repo.insert!(%Hermes.Requests.RequestChange{
        request_id: request.id,
        user_id: user_id,
        action: "updated",
        field: to_string(field),
        old_value: old_val,
        new_value: new_val,
        inserted_at:
          NaiveDateTime.add(NaiveDateTime.utc_now(), -days_ago * 24 * 3600, :second)
          |> NaiveDateTime.truncate(:second)
      })
    end)

    # Create comments
    Enum.each(comments, fn {content, user_id, days_ago} ->
      Hermes.Repo.insert!(%Hermes.Requests.RequestComment{
        request_id: request.id,
        user_id: user_id,
        content: content,
        inserted_at:
          NaiveDateTime.add(NaiveDateTime.utc_now(), -days_ago * 24 * 3600, :second)
          |> NaiveDateTime.truncate(:second)
      })
    end)

    request
  end
end

# Requests from Marketing Team
request1 =
  SeedHelper.create_request_with_history(
    %{
      title: "New landing page for product launch",
      description: "Landing page for Q2 product launch with analytics integration",
      kind: :new_need,
      target_user_type: :external,
      current_situation:
        "We currently don't have a dedicated landing page for our new product. Marketing campaigns are directing users to the general homepage, which has a low conversion rate.",
      goal_description:
        "Create a compelling landing page that showcases the new product features, includes customer testimonials, and has clear CTAs to drive conversions for the Q2 launch.",
      data_description:
        "Product specifications, customer testimonials, pricing tiers, feature comparison matrix, and marketing copy.",
      goal_target: :interface_view,
      expected_output:
        "A responsive landing page with sections for hero banner, features, testimonials, pricing, and contact form. Should integrate with Google Analytics and our CRM system.",
      priority: 4,
      status: "in_progress",
      requesting_team_id: marketing_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: marketing_user.id
    },
    marketing_user.id,
    [
      {:status, "pending", "in_progress", product_owner.id, 2},
      {:priority, "3", "4", marketing_user.id, 3}
    ],
    [
      {"This is critical for our Q2 campaign launch. Can we prioritize this?", marketing_user.id,
       5},
      {"We've started working on this. ETA is end of next week.", dev_user.id, 2},
      {"Great! Let me know if you need any assets or copy.", marketing_user.id, 2}
    ]
  )

request2 =
  SeedHelper.create_request_with_history(
    %{
      title: "Campaign analytics report automation",
      description: "Automate weekly campaign performance reports",
      kind: :improvement,
      target_user_type: :internal,
      current_situation:
        "Marketing team manually compiles campaign performance data from multiple sources every week, which takes 4-5 hours of work and is prone to errors.",
      goal_description:
        "Automate the generation of weekly campaign performance reports that pull data from Google Analytics, social media platforms, and our email marketing system.",
      data_description:
        "Campaign metrics: impressions, clicks, conversions, ROI, engagement rates from multiple platforms.",
      goal_target: :report_file,
      expected_output:
        "Automated weekly PDF report with charts and key metrics, delivered via email every Monday morning.",
      priority: 2,
      status: "pending",
      requesting_team_id: marketing_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: marketing_user.id
    },
    marketing_user.id,
    [],
    [
      {"This would save us so much time each week!", marketing_user.id, 1}
    ]
  )

# Requests from Sales Team
request3 =
  SeedHelper.create_request_with_history(
    %{
      title: "CRM integration with email system",
      description: "Bi-directional sync between CRM and email marketing platform",
      kind: :new_need,
      target_user_type: :internal,
      current_situation:
        "Sales team has to manually export contacts from the CRM and import them into the email marketing platform. This creates data inconsistencies and missed opportunities.",
      goal_description:
        "Implement automatic synchronization between our CRM and email marketing platform so that contact updates, tags, and campaign responses are reflected in both systems in real-time.",
      data_description:
        "Contact information, deal stages, interaction history, email campaign responses, tags, and custom fields.",
      goal_target: :alert_message,
      expected_output:
        "Real-time sync with notification alerts when sync fails or requires attention. Dashboard showing last sync time and status.",
      priority: 4,
      status: "in_progress",
      requesting_team_id: sales_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: sales_user.id
    },
    sales_user.id,
    [
      {:status, "pending", "in_progress", product_owner.id, 5},
      {:priority, "3", "4", sales_user.id, 7}
    ],
    [
      {"We're losing leads because of manual data entry delays.", sales_user.id, 8},
      {"Understood. We've prioritized this for the current sprint.", product_owner.id, 5},
      {"API integration is complete, working on error handling now.", dev_user.id, 1}
    ]
  )

request4 =
  SeedHelper.create_request_with_history(
    %{
      title: "Sales performance dashboard",
      description: "Real-time dashboard for sales metrics and KPIs",
      kind: :new_need,
      target_user_type: :internal,
      current_situation:
        "Sales managers have to pull reports from multiple systems to understand team performance. There's no single view of key metrics.",
      goal_description:
        "Create a real-time dashboard that shows sales pipeline, conversion rates, individual rep performance, and forecasts in one place.",
      data_description:
        "Deal data, revenue figures, conversion rates, sales activities, pipeline stages, individual and team quotas.",
      goal_target: :interface_view,
      expected_output:
        "Interactive dashboard with filters for time period, team, and individual reps. Should include charts for trends and comparative analysis.",
      priority: 3,
      status: "pending",
      requesting_team_id: sales_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: sales_user.id
    },
    sales_user.id,
    [],
    [
      {"This would really help with our quarterly planning.", sales_user.id, 3}
    ]
  )

# Requests from HR Team
request5 =
  SeedHelper.create_request_with_history(
    %{
      title: "Employee portal time-off system",
      description: "Add time-off request and approval workflow to employee portal",
      kind: :improvement,
      target_user_type: :internal,
      current_situation:
        "Employees submit time-off requests via email, which HR then manually tracks in a spreadsheet. This leads to lost requests and approval delays.",
      goal_description:
        "Implement a digital time-off request system where employees can submit requests, managers can approve/deny, and everyone can see their balance and history.",
      data_description:
        "Employee records, time-off balances, request details (dates, type, reason), manager hierarchy, approval status.",
      goal_target: :interface_view,
      expected_output:
        "Portal interface for submitting requests, manager approval dashboard, automated email notifications, and calendar view of team availability.",
      priority: 3,
      status: "completed",
      requesting_team_id: hr_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: hr_user.id
    },
    hr_user.id,
    [
      {:status, "pending", "in_progress", product_owner.id, 15},
      {:status, "in_progress", "completed", dev_user.id, 7},
      {:priority, "2", "3", hr_user.id, 18}
    ],
    [
      {"This is causing a lot of confusion during holiday season.", hr_user.id, 20},
      {"We'll get this done before year-end.", product_owner.id, 15},
      {"Feature is complete and deployed. Please test it out!", dev_user.id, 7},
      {"Works perfectly! Thank you so much.", hr_user.id, 6}
    ]
  )

request6 =
  SeedHelper.create_request_with_history(
    %{
      title: "Document management system for HR files",
      description: "Secure document storage and sharing for employee files",
      kind: :new_need,
      target_user_type: :internal,
      current_situation:
        "HR stores employee documents in a shared network drive with limited security controls. It's difficult to track who has accessed sensitive files.",
      goal_description:
        "Implement a secure document management system with role-based access, version control, and audit logging for all employee-related documents.",
      data_description:
        "Employee contracts, performance reviews, certifications, tax forms, and other confidential HR documents.",
      goal_target: :interface_view,
      expected_output:
        "Web portal for uploading, organizing, and accessing documents with granular permissions. Should log all access and changes for compliance.",
      priority: 4,
      status: "pending",
      requesting_team_id: hr_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: hr_user.id
    },
    hr_user.id,
    [],
    [
      {"This is important for our compliance audit coming up.", hr_user.id, 2}
    ]
  )

# Requests from Dev Team (as requesting team)
request7 =
  SeedHelper.create_request_with_history(
    %{
      title: "Development team onboarding documentation",
      description: "Create comprehensive onboarding guide for new developers",
      kind: :new_need,
      target_user_type: :internal,
      current_situation:
        "New developers joining the team have to piece together information from multiple sources. Onboarding takes 2-3 weeks longer than it should.",
      goal_description:
        "Create a structured onboarding guide covering development environment setup, codebase architecture, deployment processes, and team workflows.",
      data_description:
        "Setup instructions, architecture diagrams, code examples, tool configurations, and best practices documentation.",
      goal_target: :interface_view,
      expected_output:
        "Internal wiki or documentation site with searchable content, video tutorials, and step-by-step guides for common tasks.",
      priority: 2,
      status: "in_progress",
      requesting_team_id: dev_team.id,
      assigned_to_team_id: hr_team.id,
      created_by_id: dev_user.id
    },
    dev_user.id,
    [
      {:status, "pending", "in_progress", hr_user.id, 4}
    ],
    [
      {"We need HR's help with the organizational policies section.", dev_user.id, 10},
      {"We're working on the company policies part now.", hr_user.id, 4}
    ]
  )

request8 =
  SeedHelper.create_request_with_history(
    %{
      title: "Developer productivity tools budget",
      description: "Budget approval for team productivity software licenses",
      kind: :improvement,
      target_user_type: :internal,
      current_situation:
        "Development team is using free tiers of various tools, which limits collaboration and productivity.",
      goal_description:
        "Secure budget approval for premium versions of development tools including code review platforms, monitoring services, and collaboration software.",
      data_description:
        "List of tools, pricing, expected productivity improvements, and ROI justification.",
      goal_target: :alert_message,
      expected_output:
        "Budget approval notification and procurement process for the identified tools.",
      priority: 2,
      status: "pending",
      requesting_team_id: dev_team.id,
      assigned_to_team_id: hr_team.id,
      created_by_id: product_owner.id
    },
    product_owner.id,
    [],
    []
  )

# Marketing Team requests to other teams
request9 =
  SeedHelper.create_request_with_history(
    %{
      title: "Sales collateral for new product",
      description: "Create sales presentations and one-pagers for new product",
      kind: :new_need,
      target_user_type: :external,
      current_situation:
        "Sales team doesn't have proper marketing materials for the new product launch. They're creating their own inconsistent materials.",
      goal_description:
        "Develop professional sales collateral including presentation decks, one-pagers, case studies, and battle cards that align with brand guidelines.",
      data_description:
        "Product specifications, competitive analysis, target customer profiles, value propositions, and pricing information.",
      goal_target: :report_file,
      expected_output:
        "Complete sales enablement package with PowerPoint templates, PDF one-pagers, and editable battle cards.",
      priority: 3,
      status: "pending",
      requesting_team_id: marketing_team.id,
      assigned_to_team_id: sales_team.id,
      created_by_id: marketing_user.id
    },
    marketing_user.id,
    [],
    [
      {"We need your input on the pain points customers are asking about.", marketing_user.id, 1}
    ]
  )

# Sales Team requests to other teams
request10 =
  SeedHelper.create_request_with_history(
    %{
      title: "Sales training on new product features",
      description: "Technical training session for sales team on new product",
      kind: :new_need,
      target_user_type: :internal,
      current_situation:
        "Sales team struggles to answer technical questions about the new product features during customer calls.",
      goal_description:
        "Conduct comprehensive training sessions covering technical architecture, feature demonstrations, and common objection handling.",
      data_description:
        "Product architecture, feature specifications, demo environment access, FAQ document, competitive comparison.",
      goal_target: :interface_view,
      expected_output:
        "Training session schedule, demo environment access, recorded training videos, and technical FAQ document.",
      priority: 4,
      status: "pending",
      requesting_team_id: sales_team.id,
      assigned_to_team_id: dev_team.id,
      created_by_id: sales_user.id
    },
    sales_user.id,
    [],
    [
      {"Can we schedule this before the big client demo next week?", sales_user.id, 1}
    ]
  )

request11 =
  SeedHelper.create_request_with_history(
    %{
      title: "Commission structure documentation",
      description: "Clear documentation of sales commission and bonus structure",
      kind: :problem,
      target_user_type: :internal,
      current_situation:
        "Sales team members are confused about how commissions are calculated, leading to disputes and decreased motivation.",
      goal_description:
        "Create clear, detailed documentation explaining commission tiers, bonus structures, and calculation methodologies with examples.",
      data_description:
        "Commission rates, bonus thresholds, calculation formulas, payment schedules, and example scenarios.",
      goal_target: :report_file,
      expected_output:
        "Comprehensive PDF guide with examples, an online calculator tool, and FAQ section.",
      priority: 3,
      status: "in_progress",
      requesting_team_id: sales_team.id,
      assigned_to_team_id: hr_team.id,
      created_by_id: sales_user.id
    },
    sales_user.id,
    [
      {:status, "pending", "in_progress", hr_user.id, 3}
    ],
    [
      {"This is causing a lot of frustration in the team.", sales_user.id, 5},
      {"We're finalizing the policy with finance now.", hr_user.id, 3}
    ]
  )

IO.puts("✅ Seed data created successfully!")
IO.puts("\n📊 Created #{Repo.aggregate(Request, :count)} requests with changes and comments")

IO.puts(
  "👥 Created #{Repo.aggregate(User, :count)} users across #{Repo.aggregate(Team, :count)} teams"
)

IO.puts("\n👤 Sample users:")
IO.puts("  Dev Team: dev@hermes.com")
IO.puts("  Product Owner: po@hermes.com")
IO.puts("  Marketing: marketing@hermes.com")
IO.puts("  Sales: sales@hermes.com")
IO.puts("  HR: hr@hermes.com")
IO.puts("\n💡 Each request includes:")
IO.puts("  - Complete field definitions")
IO.puts("  - Change history tracking")
IO.puts("  - Comments from team members")
IO.puts("  - Requests as both requesting and assigned teams")
IO.puts("\n📊 Kanban boards are organized by team pairs:")
IO.puts("  - One board per team pair (e.g., 'Dev ↔ Marketing')")
IO.puts("  - Shows all requests between those two teams")
IO.puts("  - Filter by perspective: requests you created vs requests assigned to you")
IO.puts("\nNote: This is MVP seed data. In production, implement proper authentication.")
