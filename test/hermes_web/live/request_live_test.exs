defmodule HermesWeb.RequestLiveTest do
  use HermesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hermes.Accounts

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
end
