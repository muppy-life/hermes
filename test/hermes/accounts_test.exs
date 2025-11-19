defmodule Hermes.AccountsTest do
  use Hermes.DataCase

  alias Hermes.Accounts

  describe "admin authorization" do
    setup do
      # Create a test team
      {:ok, team} =
        Accounts.create_team(%{
          name: "Test Team",
          description: "A test team"
        })

      # Create a regular user
      {:ok, regular_user} =
        Accounts.create_user(%{
          email: "user@test.com",
          hashed_password: "hashed_password",
          role: "team_member",
          team_id: team.id,
          is_admin: false
        })

      # Create an admin user
      {:ok, admin_user} =
        Accounts.create_user(%{
          email: "admin@test.com",
          hashed_password: "hashed_password",
          role: "team_member",
          team_id: team.id,
          is_admin: true
        })

      # Create a dev team user
      {:ok, dev_user} =
        Accounts.create_user(%{
          email: "dev@test.com",
          hashed_password: "hashed_password",
          role: "dev_team",
          team_id: team.id,
          is_admin: false
        })

      # Create a product owner user
      {:ok, po_user} =
        Accounts.create_user(%{
          email: "po@test.com",
          hashed_password: "hashed_password",
          role: "product_owner",
          team_id: team.id,
          is_admin: false
        })

      # Create a second team for cross-team access tests
      {:ok, team2} =
        Accounts.create_team(%{
          name: "Test Team 2",
          description: "Another test team"
        })

      %{
        team: team,
        team2: team2,
        regular_user: regular_user,
        admin_user: admin_user,
        dev_user: dev_user,
        po_user: po_user
      }
    end

    test "is_admin?/1 returns true for admin users", %{admin_user: admin_user} do
      assert Accounts.is_admin?(admin_user) == true
    end

    test "is_admin?/1 returns false for non-admin users", %{regular_user: regular_user} do
      assert Accounts.is_admin?(regular_user) == false
    end

    test "is_admin?/1 returns false for dev_team users", %{dev_user: dev_user} do
      assert Accounts.is_admin?(dev_user) == false
    end

    test "is_admin?/1 returns false for product_owner users", %{po_user: po_user} do
      assert Accounts.is_admin?(po_user) == false
    end

    test "is_admin?/1 returns false for nil" do
      assert Accounts.is_admin?(nil) == false
    end

    test "is_dev_team?/1 returns true for admin users", %{admin_user: admin_user} do
      assert Accounts.is_dev_team?(admin_user) == true
    end

    test "is_dev_team?/1 returns true for dev_team role", %{dev_user: dev_user} do
      assert Accounts.is_dev_team?(dev_user) == true
    end

    test "is_dev_team?/1 returns false for regular users", %{regular_user: regular_user} do
      assert Accounts.is_dev_team?(regular_user) == false
    end

    test "is_product_owner?/1 returns true for admin users", %{admin_user: admin_user} do
      assert Accounts.is_product_owner?(admin_user) == true
    end

    test "is_product_owner?/1 returns true for product_owner role", %{po_user: po_user} do
      assert Accounts.is_product_owner?(po_user) == true
    end

    test "is_product_owner?/1 returns false for regular users", %{regular_user: regular_user} do
      assert Accounts.is_product_owner?(regular_user) == false
    end

    test "can_access_team?/2 returns true for admin on any team", %{
      admin_user: admin_user,
      team: team,
      team2: team2
    } do
      assert Accounts.can_access_team?(admin_user, team.id) == true
      assert Accounts.can_access_team?(admin_user, team2.id) == true
      assert Accounts.can_access_team?(admin_user, 999) == true
    end

    test "can_access_team?/2 returns true for user on their own team", %{
      regular_user: regular_user,
      team: team
    } do
      assert Accounts.can_access_team?(regular_user, team.id) == true
    end

    test "can_access_team?/2 returns false for user on different team", %{
      regular_user: regular_user,
      team2: team2
    } do
      assert Accounts.can_access_team?(regular_user, team2.id) == false
    end

    test "update_user/2 can set is_admin to true", %{regular_user: regular_user} do
      assert regular_user.is_admin == false

      {:ok, updated_user} = Accounts.update_user(regular_user, %{is_admin: true})

      assert updated_user.is_admin == true
      assert Accounts.is_admin?(updated_user) == true
    end

    test "update_user/2 can set is_admin to false", %{admin_user: admin_user} do
      assert admin_user.is_admin == true

      {:ok, updated_user} = Accounts.update_user(admin_user, %{is_admin: false})

      assert updated_user.is_admin == false
      assert Accounts.is_admin?(updated_user) == false
    end

    test "create_user/1 creates user with is_admin false by default" do
      {:ok, team} =
        Accounts.create_team(%{
          name: "Default Team",
          description: "Team for default test"
        })

      {:ok, user} =
        Accounts.create_user(%{
          email: "default@test.com",
          hashed_password: "hashed_password",
          role: "team_member",
          team_id: team.id
        })

      assert user.is_admin == false
    end

    test "create_user/1 can create user with is_admin true" do
      {:ok, team} =
        Accounts.create_team(%{
          name: "Admin Team",
          description: "Team for admin test"
        })

      {:ok, user} =
        Accounts.create_user(%{
          email: "newadmin@test.com",
          hashed_password: "hashed_password",
          role: "team_member",
          team_id: team.id,
          is_admin: true
        })

      assert user.is_admin == true
      assert Accounts.is_admin?(user) == true
    end
  end
end
