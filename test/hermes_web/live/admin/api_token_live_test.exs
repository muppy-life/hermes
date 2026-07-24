defmodule HermesWeb.Admin.ApiTokenLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts

  defp create_user(attrs) do
    {:ok, user} =
      Accounts.create_user(
        Map.merge(
          %{
            hashed_password: "h",
            role: "team_member"
          },
          attrs
        )
      )

    user
  end

  setup %{conn: conn} do
    {:ok, team} = Accounts.create_team(%{name: "Platform", description: "d"})

    admin =
      create_user(%{email: "admin@example.com", role: "admin", is_admin: true, team_id: team.id})

    dev = create_user(%{email: "dev@example.com", role: "dev_team", team_id: team.id})
    member = create_user(%{email: "member@example.com", role: "team_member", team_id: team.id})

    %{conn: conn, team: team, admin: admin, dev: dev, member: member}
  end

  describe "access control" do
    test "unauthenticated visitor is redirected to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/api-tokens")
    end

    test "a non-admin user is redirected to the dashboard", %{conn: conn, dev: dev} do
      conn = init_test_session(conn, %{user_id: dev.id})

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/admin/api-tokens")

      assert flash["error"] =~ "administrator"
    end

    test "an admin can load the view", %{conn: conn, admin: admin} do
      conn = init_test_session(conn, %{user_id: admin.id})
      {:ok, _lv, html} = live(conn, ~p"/admin/api-tokens")
      assert html =~ "API Tokens"
    end
  end

  describe "creating a token" do
    setup %{conn: conn, admin: admin} do
      conn = init_test_session(conn, %{user_id: admin.id})
      {:ok, lv, _html} = live(conn, ~p"/admin/api-tokens")
      # The form lives in a modal that is hidden until "New token" is clicked.
      lv |> element("button[phx-click=open_new_modal]") |> render_click()
      %{lv: lv}
    end

    test "shows the raw token once for a tech-team user", %{lv: lv, dev: dev} do
      html =
        lv
        |> form("form[phx-submit=create_token]", %{"user_id" => dev.id, "name" => "Claude MCP"})
        |> render_submit()

      # The raw token is displayed once, prefixed for identification, with the
      # "shown once" warning copy.
      assert html =~ "hermes_"
      assert html =~ "it will not be shown again"
      # And it is now persisted for that user.
      assert [%{name: "Claude MCP"}] = Accounts.list_api_tokens(dev)
    end

    test "the form only offers tech-team users", %{lv: lv, dev: dev, admin: admin, member: member} do
      html = render(lv)
      # dev_team and admin are selectable; a plain team_member is not.
      assert html =~ ~s(value="#{dev.id}")
      assert html =~ ~s(value="#{admin.id}")
      refute html =~ ~s(value="#{member.id}")
    end

    test "server-side guard rejects a non-tech-team user id", %{lv: lv, member: member} do
      # Bypass the select's option list to exercise the defense-in-depth check
      # in create_token (e.g. a forged submission). No token is minted.
      render_submit(lv, "create_token", %{"user_id" => to_string(member.id), "name" => "x"})

      assert Accounts.list_api_tokens(member) == []
    end

    test "requires a name", %{lv: lv, dev: dev} do
      lv
      |> form("form[phx-submit=create_token]", %{"user_id" => dev.id, "name" => ""})
      |> render_submit()

      assert Accounts.list_api_tokens(dev) == []
    end

    test "requires a user selection", %{lv: lv, dev: dev, member: member} do
      lv
      |> form("form[phx-submit=create_token]", %{"user_id" => "", "name" => "x"})
      |> render_submit()

      # No token minted for anyone when no user is chosen.
      assert Accounts.list_api_tokens(dev) == []
      assert Accounts.list_api_tokens(member) == []
    end
  end

  describe "revoking a token" do
    test "removes the token", %{conn: conn, admin: admin, dev: dev} do
      {:ok, _raw, token} = Accounts.create_api_token(dev, "to-revoke")

      conn = init_test_session(conn, %{user_id: admin.id})
      {:ok, lv, html} = live(conn, ~p"/admin/api-tokens")
      assert html =~ "to-revoke"

      html = lv |> element("button[phx-value-id='#{token.id}']") |> render_click()

      refute html =~ "to-revoke"
      assert Accounts.list_api_tokens(dev) == []
    end
  end
end
