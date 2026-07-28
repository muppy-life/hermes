defmodule Hermes.Accounts.ApiTokenTest do
  use Hermes.DataCase

  alias Hermes.Accounts

  setup do
    {:ok, team} = Accounts.create_team(%{name: "Team", description: "d"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "dev@test.com",
        hashed_password: "hashed_password",
        role: "dev_team",
        team_id: team.id
      })

    %{team: team, user: user}
  end

  describe "create_api_token/2" do
    test "returns a raw token and stores only its hash", %{user: user} do
      assert {:ok, raw, token} = Accounts.create_api_token(user, "Claude MCP")
      assert String.starts_with?(raw, "hermes_")
      assert token.name == "Claude MCP"
      assert token.user_id == user.id
      refute token.token_hash == raw
      assert token.token_hash == Accounts.ApiToken.hash_token(raw)
    end

    test "requires a name", %{user: user} do
      assert {:error, changeset} = Accounts.create_api_token(user, "")
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_api_token/1" do
    test "resolves the owner for a valid raw token", %{user: user} do
      {:ok, raw, _token} = Accounts.create_api_token(user, "t")
      assert %Accounts.User{id: id} = Accounts.get_user_by_api_token(raw)
      assert id == user.id
    end

    test "touches last_used_at on success", %{user: user} do
      {:ok, raw, token} = Accounts.create_api_token(user, "t")
      assert is_nil(token.last_used_at)
      Accounts.get_user_by_api_token(raw)
      assert Accounts.get_api_token!(token.id).last_used_at
    end

    test "returns nil for an unknown token" do
      assert is_nil(Accounts.get_user_by_api_token("hermes_nope"))
    end

    test "returns nil for a non-binary", do: assert(is_nil(Accounts.get_user_by_api_token(nil)))

    test "returns nil when the owner is soft-deleted", %{user: user} do
      {:ok, raw, _token} = Accounts.create_api_token(user, "t")
      Accounts.delete_user(user)
      assert is_nil(Accounts.get_user_by_api_token(raw))
    end
  end

  describe "revoke_api_token/1" do
    test "invalidates the token", %{user: user} do
      {:ok, raw, token} = Accounts.create_api_token(user, "t")
      assert {:ok, _} = Accounts.revoke_api_token(token)
      assert is_nil(Accounts.get_user_by_api_token(raw))
    end
  end
end
