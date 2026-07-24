defmodule Hermes.TechOpsTest do
  use Hermes.DataCase

  alias Hermes.Accounts
  alias Hermes.TechOps
  alias Hermes.TechOps.Task

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

  describe "create_tech_ops_task/1" do
    test "creates a task with valid attributes", %{user: user} do
      attrs = %{
        "recorded_on" => Date.utc_today(),
        "reported_problem" => "Server is down",
        "issue_origin" => "monitoring alert",
        "status" => "open",
        "responsible_id" => user.id
      }

      assert {:ok, %Task{} = task} = TechOps.create_tech_ops_task(attrs)
      assert task.reported_problem == "Server is down"
      assert task.issue_origin == "monitoring alert"
      assert task.status == :open
      assert task.responsible_id == user.id
    end

    test "defaults status to :open when omitted" do
      attrs = %{"recorded_on" => Date.utc_today(), "reported_problem" => "x"}
      assert {:ok, %Task{status: :open}} = TechOps.create_tech_ops_task(attrs)
    end

    test "allows an unassigned responsible" do
      attrs = %{"recorded_on" => Date.utc_today(), "reported_problem" => "x"}
      assert {:ok, %Task{responsible_id: nil}} = TechOps.create_tech_ops_task(attrs)
    end

    test "requires recorded_on and reported_problem" do
      assert {:error, changeset} = TechOps.create_tech_ops_task(%{})
      assert %{recorded_on: ["can't be blank"]} = errors_on(changeset)
      assert %{reported_problem: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an invalid status" do
      attrs = %{
        "recorded_on" => Date.utc_today(),
        "reported_problem" => "x",
        "status" => "nonsense"
      }

      assert {:error, changeset} = TechOps.create_tech_ops_task(attrs)
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_tech_ops_tasks/0" do
    test "returns tasks newest-recorded first with responsible preloaded", %{user: user} do
      {:ok, _older} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => ~D[2026-01-01],
          "reported_problem" => "older",
          "responsible_id" => user.id
        })

      {:ok, _newer} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => ~D[2026-07-01],
          "reported_problem" => "newer"
        })

      assert [newer, older] = TechOps.list_tech_ops_tasks()
      assert newer.reported_problem == "newer"
      assert older.reported_problem == "older"
      assert %Accounts.User{} = older.responsible
    end
  end

  describe "update_tech_ops_task/2" do
    test "updates status and resolution" do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x"
        })

      assert {:ok, updated} =
               TechOps.update_tech_ops_task(task, %{
                 "status" => "resolved",
                 "resolution" => "restarted the box"
               })

      assert updated.status == :resolved
      assert updated.resolution == "restarted the box"
    end
  end

  describe "delete_tech_ops_task/1" do
    test "deletes the task" do
      {:ok, task} =
        TechOps.create_tech_ops_task(%{
          "recorded_on" => Date.utc_today(),
          "reported_problem" => "x"
        })

      assert {:ok, _} = TechOps.delete_tech_ops_task(task)
      assert_raise Ecto.NoResultsError, fn -> TechOps.get_tech_ops_task!(task.id) end
    end
  end
end
