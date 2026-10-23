defmodule HermesWeb.RequestLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Requests.Request

  setup %{conn: conn} do
    # Oban runs inline in tests, so notification emails are delivered from the
    # LiveView process; route them to the test process instead of the LiveView,
    # which has no handler for them and would crash mid-test.
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "user@example.com",
        hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
        role: "team_member",
        team_id: team.id
      })

    %{conn: init_test_session(conn, %{user_id: user.id}), user: user}
  end

  describe "unknown request ids" do
    test "show redirects to the backlog with a flash", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/backlog", flash: flash}}} =
               live(conn, ~p"/backlog/999999")

      assert flash["error"] == "Request not found"
    end

    test "show handles non-integer ids", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/backlog", flash: flash}}} =
               live(conn, ~p"/backlog/abc")

      assert flash["error"] == "Request not found"
    end

    test "edit redirects to the backlog with a flash", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/backlog", flash: flash}}} =
               live(conn, ~p"/backlog/999999/edit")

      assert flash["error"] == "Request not found"
    end

    test "edit handles non-integer ids", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/backlog", flash: flash}}} =
               live(conn, ~p"/backlog/abc/edit")

      assert flash["error"] == "Request not found"
    end
  end

  describe "new request form" do
    setup %{conn: conn, user: user} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@example.com",
          hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
          role: "admin",
          team_id: user.team_id
        })

      {:ok, other_team} = Accounts.create_team(%{name: "Other Team", description: "d"})

      {:ok, member} =
        Accounts.create_user(%{
          name: "Mary",
          surname: "Vega",
          email: "member@example.com",
          hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
          role: "team_member",
          team_id: other_team.id
        })

      %{
        admin_conn: init_test_session(conn, %{user_id: admin.id}),
        admin: admin,
        other_team: other_team,
        member: member
      }
    end

    test "admin creates a request in the name of a member of another team", %{
      admin_conn: conn,
      other_team: other_team,
      member: member
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      # Picking another team reloads its members into the user select,
      # labeled by display name with the email for disambiguation
      html =
        view
        |> form("#step-1-form", request: %{requesting_team_id: to_string(other_team.id)})
        |> render_change()

      assert html =~ "Mary Vega (member@example.com)"

      view
      |> element(~s|button[phx-value-field="kind"][phx-value-pick="problema"]|)
      |> render_click()

      view |> element(~s|button[phx-value-priority="normal"]|) |> render_click()

      view
      |> element(~s|button[phx-value-field="target_user_type"][phx-value-pick="internal"]|)
      |> render_click()

      view
      |> form("#step-1-form",
        request: %{title: "On behalf request", created_by_id: to_string(member.id)}
      )
      |> render_submit()

      view
      |> form("#step-2-form", request: %{current_situation: "bad", goal_description: "good"})
      |> render_submit()

      view |> element(~s|button[phx-value-area="eficiencia"]|) |> render_click()
      view |> element(~s|button[phx-value-level="medio"]|) |> render_click()

      view |> form("#step-3-form") |> render_submit()

      request =
        Hermes.Repo.get_by!(Request, title: "On behalf request")

      assert request.created_by_id == member.id
      assert request.requesting_team_id == other_team.id
    end

    test "a forged or stale user outside the requesting team is rejected", %{
      admin_conn: conn,
      other_team: other_team,
      user: outsider
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      view
      |> form("#step-1-form", request: %{requesting_team_id: to_string(other_team.id)})
      |> render_change()

      # `outsider` belongs to another team; the select never offers them, so
      # forge the id by sending the submit event directly to the component.
      view
      |> with_target("#new-request-form")
      |> render_submit("submit", %{
        "request" => %{
          "title" => "Forged request",
          "priority" => "2",
          "created_by_id" => to_string(outsider.id),
          "impact_area" => "eficiencia",
          "impact_level" => "medio"
        }
      })

      assert Hermes.Repo.get_by(Request, title: "Forged request") == nil

      # Back on step 1 with the member list reloaded for the requesting team
      html = render(view)
      assert html =~ "step-1-form"
      assert html =~ "member@example.com"
    end

    test "a team change bundled with the step submit reloads the member list", %{
      admin_conn: conn,
      other_team: other_team,
      member: member
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      view
      |> element(~s|button[phx-value-field="kind"][phx-value-pick="problema"]|)
      |> render_click()

      view |> element(~s|button[phx-value-priority="normal"]|) |> render_click()

      view
      |> element(~s|button[phx-value-field="target_user_type"][phx-value-pick="internal"]|)
      |> render_click()

      # The team change arrives with the step submit, without a validate event
      view
      |> form("#step-1-form",
        request: %{title: "Bundled team change", requesting_team_id: to_string(other_team.id)}
      )
      |> render_submit()

      view
      |> form("#step-2-form", request: %{current_situation: "bad", goal_description: "good"})
      |> render_submit()

      view |> element(~s|button[phx-value-area="eficiencia"]|) |> render_click()
      view |> element(~s|button[phx-value-level="medio"]|) |> render_click()

      view |> form("#step-3-form") |> render_submit()

      request = Hermes.Repo.get_by!(Request, title: "Bundled team change")

      assert request.created_by_id == member.id
      assert request.requesting_team_id == other_team.id
    end

    test "regular members do not see the team or user pickers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      html = view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      refute html =~ "Requesting user"
      refute html =~ "request[requesting_team_id]"
      refute html =~ "request[created_by_id]"
    end

    test "a member with an extra team picks the requesting team but not the user", %{
      conn: conn,
      user: user,
      other_team: other_team
    } do
      {:ok, _} = Accounts.update_user(user, %{extra_team_ids: [other_team.id]})
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      assert has_element?(view, "#requesting-team-select option[value='#{user.team_id}']")
      assert has_element?(view, "#requesting-team-select option[value='#{other_team.id}']")
      refute has_element?(view, "#requesting-user-select")

      view
      |> form("#step-1-form", request: %{requesting_team_id: to_string(other_team.id)})
      |> render_change()

      view
      |> element(~s|button[phx-value-field="kind"][phx-value-pick="problema"]|)
      |> render_click()

      view |> element(~s|button[phx-value-priority="normal"]|) |> render_click()

      view
      |> element(~s|button[phx-value-field="target_user_type"][phx-value-pick="internal"]|)
      |> render_click()

      view |> form("#step-1-form", request: %{title: "Extra team request"}) |> render_submit()

      view
      |> form("#step-2-form", request: %{current_situation: "bad", goal_description: "good"})
      |> render_submit()

      view |> element(~s|button[phx-value-area="eficiencia"]|) |> render_click()
      view |> element(~s|button[phx-value-level="medio"]|) |> render_click()

      view |> form("#step-3-form") |> render_submit()

      request = Hermes.Repo.get_by!(Request, title: "Extra team request")

      assert request.requesting_team_id == other_team.id
      assert request.created_by_id == user.id
    end

    test "a member with an extra team cannot forge an unrelated team or creator", %{
      conn: conn,
      user: user,
      other_team: other_team,
      member: member
    } do
      {:ok, unrelated} = Accounts.create_team(%{name: "Unrelated", description: "d"})
      {:ok, _} = Accounts.update_user(user, %{extra_team_ids: [other_team.id]})
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      view
      |> with_target("#new-request-form")
      |> render_submit("submit", %{
        "request" => %{
          "title" => "Extra team forged request",
          "priority" => "2",
          "requesting_team_id" => to_string(unrelated.id),
          "created_by_id" => to_string(member.id),
          "impact_area" => "eficiencia",
          "impact_level" => "medio"
        }
      })

      request = Hermes.Repo.get_by!(Request, title: "Extra team forged request")

      assert request.requesting_team_id == user.team_id
      assert request.created_by_id == user.id
    end

    test "a regular member forging team and user ids is locked to their own", %{
      conn: conn,
      user: user,
      other_team: other_team,
      member: member
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      view
      |> with_target("#new-request-form")
      |> render_submit("submit", %{
        "request" => %{
          "title" => "Member forged request",
          "priority" => "2",
          "requesting_team_id" => to_string(other_team.id),
          "created_by_id" => to_string(member.id),
          "impact_area" => "eficiencia",
          "impact_level" => "medio"
        }
      })

      request = Hermes.Repo.get_by!(Request, title: "Member forged request")

      assert request.created_by_id == user.id
      assert request.requesting_team_id == user.team_id
    end
  end

  describe "edit request reporter" do
    setup %{user: user} do
      {:ok, teammate} =
        Accounts.create_user(%{
          name: "Tom",
          surname: "Mate",
          email: "teammate@example.com",
          hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
          role: "team_member",
          team_id: user.team_id
        })

      {:ok, other_team} = Accounts.create_team(%{name: "Other Team", description: "d"})

      {:ok, member} =
        Accounts.create_user(%{
          name: "Mary",
          surname: "Vega",
          email: "member@example.com",
          hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
          role: "team_member",
          team_id: other_team.id
        })

      {:ok, request} =
        Hermes.Requests.create_request(%{
          "title" => "Reporter request",
          "priority" => 2,
          "requesting_team_id" => user.team_id,
          "created_by_id" => user.id
        })

      %{teammate: teammate, other_team: other_team, member: member, request: request}
    end

    test "changes the reporter within the same team", %{
      conn: conn,
      user: user,
      teammate: teammate,
      request: request
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog/#{request.id}")

      view |> element(~s|button[phx-click="open_edit_modal"]|) |> render_click()

      view
      |> form("#edit-request-form",
        request: %{requesting_team_id: user.team_id, created_by_id: teammate.id}
      )
      |> render_submit()

      assert Hermes.Repo.get!(Request, request.id).created_by_id == teammate.id
    end

    test "changing the team reloads its members as reporters", %{
      conn: conn,
      other_team: other_team,
      member: member,
      request: request
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog/#{request.id}")

      view |> element(~s|button[phx-click="open_edit_modal"]|) |> render_click()

      html =
        view
        |> form("#edit-request-form", request: %{requesting_team_id: other_team.id})
        |> render_change()

      assert html =~ "Mary Vega (member@example.com)"
      refute html =~ "teammate@example.com"

      view
      |> form("#edit-request-form", request: %{requesting_team_id: other_team.id})
      |> render_submit(%{request: %{created_by_id: member.id}})

      request = Hermes.Repo.get!(Request, request.id)
      assert request.requesting_team_id == other_team.id
      assert request.created_by_id == member.id
    end

    test "a reporter outside the requesting team is not saved", %{
      conn: conn,
      user: user,
      member: member,
      request: request
    } do
      {:ok, view, _html} = live(conn, ~p"/backlog/#{request.id}")

      view |> element(~s|button[phx-click="open_edit_modal"]|) |> render_click()

      view
      |> form("#edit-request-form")
      |> render_submit(%{request: %{created_by_id: member.id}})

      assert Hermes.Repo.get!(Request, request.id).created_by_id == user.id
    end
  end
end
