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
alias Hermes.Kanbans.{Board, Column, Card}
alias Hermes.Requests.Request

# Clear existing data (optional - comment out if you want to keep existing data)
Repo.delete_all(Card)
Repo.delete_all(Column)
Repo.delete_all(Board)
Repo.delete_all(Request)
Repo.delete_all(User)
Repo.delete_all(Team)

# Create teams
dev_team = Repo.insert!(%Team{
  name: "Development Team",
  description: "Internal development team"
})

marketing_team = Repo.insert!(%Team{
  name: "Marketing Team",
  description: "Marketing and communications team"
})

sales_team = Repo.insert!(%Team{
  name: "Sales Team",
  description: "Sales and customer relations team"
})

hr_team = Repo.insert!(%Team{
  name: "HR Team",
  description: "Human resources team"
})

# Create users (Note: In production, you should hash passwords properly)
# For this MVP, we're using a simple placeholder password
dev_user = Repo.insert!(%User{
  email: "dev@hermes.com",
  hashed_password: "dev123",  # In production, use proper password hashing
  role: "dev_team",
  team_id: dev_team.id
})

product_owner = Repo.insert!(%User{
  email: "po@hermes.com",
  hashed_password: "po123",
  role: "product_owner",
  team_id: dev_team.id
})

marketing_user = Repo.insert!(%User{
  email: "marketing@hermes.com",
  hashed_password: "marketing123",
  role: "team_member",
  team_id: marketing_team.id
})

sales_user = Repo.insert!(%User{
  email: "sales@hermes.com",
  hashed_password: "sales123",
  role: "team_member",
  team_id: sales_team.id
})

hr_user = Repo.insert!(%User{
  email: "hr@hermes.com",
  hashed_password: "hr123",
  role: "team_member",
  team_id: hr_team.id
})

# Create requests
request1 = Repo.insert!(%Request{
  title: "New landing page for product launch",
  description: "We need a new landing page for our upcoming product launch in Q2. It should be mobile-responsive and integrate with our analytics.",
  priority: 5,
  status: "pending",
  requesting_team_id: marketing_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: marketing_user.id
})

request2 = Repo.insert!(%Request{
  title: "CRM integration with email system",
  description: "Sales team needs the CRM to automatically sync with our email marketing platform.",
  priority: 4,
  status: "in_progress",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

request3 = Repo.insert!(%Request{
  title: "Employee portal improvements",
  description: "Add new features to employee portal including time-off requests and document upload.",
  priority: 3,
  status: "pending",
  requesting_team_id: hr_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: hr_user.id
})

request4 = Repo.insert!(%Request{
  title: "Performance dashboard",
  description: "Create a dashboard to track sales metrics and KPIs in real-time.",
  priority: 4,
  status: "pending",
  requesting_team_id: sales_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: sales_user.id
})

request5 = Repo.insert!(%Request{
  title: "Bug fix: Login timeout issue",
  description: "Users are reporting that they get logged out too quickly. Need to extend session timeout.",
  priority: 5,
  status: "completed",
  requesting_team_id: hr_team.id,
  assigned_to_team_id: dev_team.id,
  created_by_id: hr_user.id
})

# Create kanban boards for each team
dev_board = Repo.insert!(%Board{
  name: "Development Sprint Board",
  team_id: dev_team.id
})

marketing_board = Repo.insert!(%Board{
  name: "Marketing Campaigns",
  team_id: marketing_team.id
})

sales_board = Repo.insert!(%Board{
  name: "Sales Pipeline",
  team_id: sales_team.id
})

# Create columns for dev board
backlog = Repo.insert!(%Column{
  name: "Backlog",
  position: 0,
  board_id: dev_board.id
})

todo = Repo.insert!(%Column{
  name: "To Do",
  position: 1,
  board_id: dev_board.id
})

in_progress = Repo.insert!(%Column{
  name: "In Progress",
  position: 2,
  board_id: dev_board.id
})

review = Repo.insert!(%Column{
  name: "Review",
  position: 3,
  board_id: dev_board.id
})

done = Repo.insert!(%Column{
  name: "Done",
  position: 4,
  board_id: dev_board.id
})

# Create cards for the dev board
Repo.insert!(%Card{
  title: "New landing page for product launch",
  description: "Marketing team request - high priority",
  position: 0,
  column_id: backlog.id,
  request_id: request1.id
})

Repo.insert!(%Card{
  title: "CRM integration with email system",
  description: "Sales team request - currently being worked on",
  position: 0,
  column_id: in_progress.id,
  request_id: request2.id
})

Repo.insert!(%Card{
  title: "Employee portal improvements",
  description: "HR team request - add time-off and document features",
  position: 1,
  column_id: backlog.id,
  request_id: request3.id
})

Repo.insert!(%Card{
  title: "Performance dashboard",
  description: "Sales metrics dashboard",
  position: 0,
  column_id: todo.id,
  request_id: request4.id
})

Repo.insert!(%Card{
  title: "Bug fix: Login timeout issue",
  description: "Session timeout fix - completed",
  position: 0,
  column_id: done.id,
  request_id: request5.id
})

IO.puts("✅ Seed data created successfully!")
IO.puts("\nSample users:")
IO.puts("  Dev Team: dev@hermes.com")
IO.puts("  Product Owner: po@hermes.com")
IO.puts("  Marketing: marketing@hermes.com")
IO.puts("  Sales: sales@hermes.com")
IO.puts("  HR: hr@hermes.com")
IO.puts("\nNote: This is MVP seed data. In production, implement proper authentication.")
