defmodule Hermes.Workers.RequestNotificationWorkerTest do
  use Hermes.DataCase

  import Swoosh.TestAssertions

  alias Hermes.Accounts
  alias Hermes.Requests

  setup do
    {:ok, team} = Accounts.create_team(%{name: "Requesting", description: "d"})
    {:ok, dev_team} = Accounts.create_team(%{name: "Dev", description: "d"})

    {:ok, requester} = create_user("requester@example.com", "team_member", team.id)
    {:ok, teammate} = create_user("teammate@example.com", "team_member", team.id)
    {:ok, dev} = create_user("dev@example.com", "dev_team", dev_team.id)

    %{team: team, dev_team: dev_team, requester: requester, teammate: teammate, dev: dev}
  end

  defp create_user(email, role, team_id) do
    Accounts.create_user(%{
      email: email,
      hashed_password: :crypto.hash(:sha256, "secret123") |> Base.encode16(case: :lower),
      role: role,
      team_id: team_id
    })
  end

  defp request_attrs(ctx) do
    %{
      "title" => "Notify test",
      "priority" => 2,
      "status" => "new",
      "requesting_team_id" => ctx.team.id,
      "assigned_to_team_id" => ctx.dev_team.id,
      "created_by_id" => ctx.requester.id
    }
  end

  test "the creator is excluded when they created the request themselves", ctx do
    {:ok, _request} = Requests.create_request(request_attrs(ctx), ctx.requester.id)

    assert_email_sent(fn email ->
      recipients = Enum.map(email.to, fn {_name, address} -> address end)

      assert Enum.sort(recipients) == ["dev@example.com", "teammate@example.com"]
    end)
  end

  test "the creator is notified when someone else created the request in their name", ctx do
    {:ok, _request} = Requests.create_request(request_attrs(ctx), ctx.dev.id)

    assert_email_sent(fn email ->
      recipients = Enum.map(email.to, fn {_name, address} -> address end)

      assert Enum.sort(recipients) == [
               "dev@example.com",
               "requester@example.com",
               "teammate@example.com"
             ]
    end)
  end
end
