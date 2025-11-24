defmodule HermesWeb.Admin.DashboardLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Accounts
  alias HermesWeb.Presence

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to global presence updates
      Phoenix.PubSub.subscribe(Hermes.PubSub, "users:online")
    end

    {:ok,
     socket
     |> assign(:page_title, "Admin Dashboard")
     |> assign_stats()
     |> assign_users()}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{joins: joins, leaves: leaves}},
        socket
      ) do
    # Get current users map
    users = socket.assigns.users

    # Handle leaves - update database and mark as offline
    users =
      Enum.reduce(leaves, users, fn {user_id, _}, acc ->
        case Map.get(acc, user_id) do
          nil ->
            acc

          user ->
            # Update last_seen_at in database asynchronously
            Task.start(fn ->
              try do
                user_record = Accounts.get_user!(user.id)
                Accounts.update_last_seen(user_record)
              rescue
                _ -> :ok
              end
            end)

            # Update local state - mark as offline with current timestamp
            Map.put(acc, user_id, %{
              user
              | online: false,
                current_view: nil,
                last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
        end
      end)

    # Handle joins - mark as online or update view
    users =
      Enum.reduce(joins, users, fn {user_id, %{metas: metas}}, acc ->
        meta = List.first(metas)

        case Map.get(acc, user_id) do
          nil ->
            # New user
            Map.put(acc, user_id, %{
              id: String.to_integer(user_id),
              email: meta.email,
              role: meta.role,
              current_view: meta.current_view,
              last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
              online: true
            })

          existing_user ->
            # Update existing user's view
            Map.put(acc, user_id, %{existing_user | current_view: meta.current_view, online: true})
        end
      end)

    {:noreply, assign(socket, :users, users)}
  end

  defp assign_stats(socket) do
    socket
    |> assign(:total_users, count_users())
    |> assign(:total_teams, count_teams())
    |> assign(:admin_users, count_admin_users())
    |> assign(:total_requests, count_requests())
  end

  defp assign_users(socket) do
    # Get online users from Presence
    online_users =
      Presence.list("users:online")
      |> Enum.map(fn {user_id, %{metas: metas}} ->
        meta = List.first(metas)

        {user_id,
         %{
           id: String.to_integer(user_id),
           email: meta.email,
           role: meta.role,
           current_view: meta.current_view,
           last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
           online: true
         }}
      end)
      |> Map.new()

    # Get recently active users from database (last 7 days)
    recently_active =
      Accounts.list_recently_active_users(7)
      |> Enum.map(fn user ->
        {Integer.to_string(user.id),
         %{
           id: user.id,
           email: user.email,
           role: user.role,
           current_view: nil,
           last_seen_at: user.last_seen_at,
           online: false
         }}
      end)
      |> Map.new()

    # Merge: online users take precedence
    users = Map.merge(recently_active, online_users)

    assign(socket, :users, users)
  end

  defp count_users do
    Accounts.list_users() |> length()
  end

  defp count_teams do
    Accounts.list_teams() |> length()
  end

  defp count_admin_users do
    Accounts.list_users()
    |> Enum.filter(&Accounts.is_admin?/1)
    |> length()
  end

  defp count_requests do
    # Get the count from the Requests context
    case Hermes.Repo.aggregate(Hermes.Requests.Request, :count, :id) do
      count when is_integer(count) -> count
      _ -> 0
    end
  end


  defp format_last_seen(nil), do: "Never"

  defp format_last_seen(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
