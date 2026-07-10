defmodule HermesWeb.AuthControllerTest do
  use HermesWeb.ConnCase

  alias Hermes.Accounts

  @password "secret123"

  setup do
    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "user@example.com",
        hashed_password: :crypto.hash(:sha256, @password) |> Base.encode16(case: :lower),
        role: "team_member",
        team_id: team.id
      })

    %{user: user}
  end

  describe "redirect after login" do
    test "visiting a protected page while logged out stores the return path", %{conn: conn} do
      conn = get(conn, ~p"/backlog?status=open")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_return_to) == "/backlog?status=open"
    end

    test "logging in redirects to the originally requested page", %{conn: conn, user: user} do
      conn = get(conn, ~p"/backlog?status=open")

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      assert redirected_to(conn) == "/backlog?status=open"
      refute get_session(conn, :user_return_to)
    end

    test "logging in without a stored return path redirects to the dashboard", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "ignores a non-local stored return path", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(%{user_return_to: "//evil.com/phish"})
        |> post(~p"/login", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "failed login does not clear the stored return path", %{conn: conn, user: user} do
      conn = get(conn, ~p"/backlog")

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "wrong"}
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_return_to) == "/backlog"
    end
  end
end
