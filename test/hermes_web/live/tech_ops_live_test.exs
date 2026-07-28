defmodule HermesWeb.TechOpsLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.TechOps

  defp create_user(role, email, team_id) do
    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
        role: role,
        team_id: team_id
      })

    user
  end

  setup %{conn: conn} do
    {:ok, team} = Accounts.create_team(%{name: "Platform Squad", description: "d"})
    dev = create_user("dev_team", "dev@example.com", team.id)
    %{conn: conn, team: team, dev: dev}
  end

  describe "access control" do
    test "a non-tech-team user is redirected to the dashboard", %{conn: conn, team: team} do
      member = create_user("team_member", "member@example.com", team.id)
      conn = init_test_session(conn, %{user_id: member.id})

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/tech-ops")

      assert flash["error"] =~ "tech team"
    end

    test "an unauthenticated visitor is redirected to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/tech-ops")
    end

    test "a dev_team user can load the view", %{conn: conn, dev: dev} do
      conn = init_test_session(conn, %{user_id: dev.id})
      {:ok, _lv, html} = live(conn, ~p"/tech-ops")
      assert html =~ "Tech Ops"
    end

    test "an admin can load the view", %{conn: conn, team: team} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@example.com",
          hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
          role: "admin",
          is_admin: true,
          team_id: team.id
        })

      conn = init_test_session(conn, %{user_id: admin.id})
      {:ok, _lv, html} = live(conn, ~p"/tech-ops")
      assert html =~ "Tech Ops"
    end
  end

  describe "recording tasks" do
    setup %{conn: conn, dev: dev} do
      %{conn: init_test_session(conn, %{user_id: dev.id})}
    end

    test "creates a task through the form", %{conn: conn, dev: dev, team: team} do
      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv |> element("button", "Record task") |> render_click()

      # Both lookups are new values, so switch each field to free-text entry.
      lv |> element("button[phx-value-field='reporter']") |> render_click()
      lv |> element("button[phx-value-field='issue_origin']") |> render_click()

      html =
        lv
        |> form("#tech-ops-task-form",
          task: %{
            recorded_on: "2026-07-24",
            reported_problem: "DB connection pool exhausted",
            reporter_name: "on-call engineer",
            issue_origin_name: "monitoring",
            status: "in_progress",
            cause: "traffic spike",
            responsible_id: dev.id,
            team_id: team.id
          }
        )
        |> render_submit()

      assert html =~ "DB connection pool exhausted"
      assert html =~ "on-call engineer"
      assert html =~ "In progress"
      assert html =~ "traffic spike"
      assert html =~ team.name

      assert [task] = TechOps.list_tech_ops_tasks()
      assert task.reported_problem == "DB connection pool exhausted"
      assert task.reporter.name == "on-call engineer"
      assert task.issue_origin.name == "monitoring"
      assert task.status == :in_progress
      assert task.cause == "traffic spike"
      assert task.team_id == team.id
    end

    test "reuses an existing lookup value on case-variant input", %{conn: conn} do
      {:ok, _} = TechOps.resolve_or_create_issue_origin("Slack")

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")
      lv |> element("button", "Record task") |> render_click()

      # Free-text entry is what allows the case-variant spelling to be submitted.
      lv |> element("button[phx-value-field='issue_origin']") |> render_click()

      lv
      |> form("#tech-ops-task-form",
        task: %{
          recorded_on: "2026-07-24",
          reported_problem: "x",
          issue_origin_name: "  slack "
        }
      )
      |> render_submit()

      # No duplicate lookup row was created.
      assert length(TechOps.list_issue_origins()) == 1
      assert [task] = TechOps.list_tech_ops_tasks()
      assert task.issue_origin.name == "Slack"
    end

    test "defaults the responsible to the current user on a new task", %{conn: conn, dev: dev} do
      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      html = lv |> element("button", "Record task") |> render_click()

      assert html =~ ~s(<option selected="" value="#{dev.id}">)
    end

    test "responsible dropdown only lists tech users", %{conn: conn, team: team, dev: dev} do
      # A non-tech user must not appear as a responsible option.
      member = create_user("team_member", "member@example.com", team.id)

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")
      html = lv |> element("button", "Record task") |> render_click()

      assert html =~ ~s(value="#{dev.id}")
      refute html =~ ~s(value="#{member.id}")
    end

    test "lookup fields are dropdowns of existing values by default", %{conn: conn} do
      {:ok, _} = TechOps.resolve_or_create_reporter("Alejandra")

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")
      html = lv |> element("button", "Record task") |> render_click()

      assert html =~ ~s(<select name="task[reporter_name]")
      assert html =~ "Alejandra"
    end

    test "the new-value button swaps the dropdown for a datalist input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tech-ops")
      lv |> element("button", "Record task") |> render_click()

      html = lv |> element("button[phx-value-field='reporter']") |> render_click()

      # The reporter field is now free text; issue origin stays a dropdown.
      assert html =~ ~s(name="task[reporter_name]" value="" list="tech-ops-reporters")
      refute html =~ ~s(<select name="task[reporter_name]")
      assert html =~ ~s(<select name="task[issue_origin_name]")

      # Toggling back restores the dropdown.
      html = lv |> element("button[phx-value-field='reporter']") |> render_click()
      assert html =~ ~s(<select name="task[reporter_name]")
    end

    test "editing a task preselects its current lookup values", %{conn: conn} do
      {:ok, _} = TechOps.resolve_or_create_reporter("Alejandra")

      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x",
          "reporter_name" => "Alejandra"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{task.id}']")
      |> render_click()

      assert render(lv) =~ ~s(<option value="Alejandra" selected="">)
    end

    test "shows validation errors on an incomplete form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv |> element("button", "Record task") |> render_click()

      html =
        lv
        |> form("#tech-ops-task-form", task: %{recorded_on: "", reported_problem: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert TechOps.list_tech_ops_tasks() == []
    end

    test "edits an existing task", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "original"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv |> element("button[phx-value-id='#{task.id}']", "Edit") |> render_click()

      html =
        lv
        |> form("#tech-ops-task-form",
          task: %{status: "resolved", resolution: "fixed it"}
        )
        |> render_submit()

      assert html =~ "Resolved"
      assert html =~ "fixed it"
    end

    test "deletes a task", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "to be removed"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv
      |> element("button[phx-click='open_delete_modal'][phx-value-id='#{task.id}']")
      |> render_click()

      lv |> element("button", "Delete Task") |> render_click()

      assert TechOps.list_tech_ops_tasks() == []
    end

    test "opening edit on a concurrently-deleted task does not crash", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "stale"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      # Another user deletes it after this page rendered.
      TechOps.delete_tech_ops_task(task)

      # Must not raise / crash the process.
      lv
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{task.id}']")
      |> render_click()

      # LiveView is still alive, the stale row is gone, and the user is informed.
      assert render(lv) =~ "Tech Ops"
      refute render(lv) =~ "stale"
    end

    test "opening delete on a concurrently-deleted task does not crash", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "stale"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      TechOps.delete_tech_ops_task(task)

      lv
      |> element("button[phx-click='open_delete_modal'][phx-value-id='#{task.id}']")
      |> render_click()

      assert render(lv) =~ "Tech Ops"
      refute render(lv) =~ "stale"
    end

    test "stale edit does not create orphaned lookup values", %{conn: conn} do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "stale"
        })

      {:ok, lv, _html} = live(conn, ~p"/tech-ops")

      lv
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{task.id}']")
      |> render_click()

      # Another user deletes it while the edit modal is open.
      TechOps.delete_tech_ops_task(task)

      # Submit the edit with a brand-new issue-origin value.
      lv |> element("button[phx-value-field='issue_origin']") |> render_click()

      lv
      |> form("#tech-ops-task-form",
        task: %{reported_problem: "stale", issue_origin_name: "Brand New Origin"}
      )
      |> render_submit()

      # The rejected edit must not have persisted the new lookup value.
      assert TechOps.list_issue_origins() == []
      # The task edit itself was discarded (task remains deleted).
      assert TechOps.list_tech_ops_tasks() == []
    end
  end
end
