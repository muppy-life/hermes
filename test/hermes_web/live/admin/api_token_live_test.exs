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

    test "creates a token owned by the current admin and shows it once", %{lv: lv, admin: admin} do
      html =
        lv
        |> form("form[phx-submit=create_token]", %{"name" => "Claude MCP"})
        |> render_submit()

      # The raw token is displayed once, prefixed for identification, with the
      # "shown once" warning copy.
      assert html =~ "hermes_"
      assert html =~ "it will not be shown again"
      # And it belongs to the admin who created it — not anyone else.
      assert [%{name: "Claude MCP"}] = Accounts.list_api_tokens(admin)
    end

    test "the form has no user picker (owner is always self)", %{lv: lv, admin: admin} do
      html = render(lv)
      refute html =~ ~s(name="user_id")
      assert html =~ admin.email
    end

    test "requires a name", %{lv: lv, admin: admin} do
      lv
      |> form("form[phx-submit=create_token]", %{"name" => ""})
      |> render_submit()

      assert Accounts.list_api_tokens(admin) == []
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
