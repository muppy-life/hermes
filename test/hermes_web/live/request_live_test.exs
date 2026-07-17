defmodule HermesWeb.RequestLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts
  alias Hermes.Requests.Request

  setup %{conn: conn} do
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

      # Picking another team reloads its members into the user select
      html =
        view
        |> form("#step-1-form", request: %{requesting_team_id: to_string(other_team.id)})
        |> render_change()

      assert html =~ "member@example.com"

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

    test "a forged user outside the requesting team falls back to the creator", %{
      admin_conn: conn,
      admin: admin,
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

      request = Hermes.Repo.get_by!(Request, title: "Forged request")

      assert request.created_by_id == admin.id
      assert request.requesting_team_id == other_team.id
    end

    test "regular members do not see the team or user pickers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/backlog")

      html = view |> element(~s|button[phx-click="show_new_request"]|) |> render_click()

      refute html =~ "Requesting user"
      refute html =~ "request[requesting_team_id]"
      refute html =~ "request[created_by_id]"
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
end
