defmodule HermesWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for loading current user from session.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Hermes.Accounts

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      # Track user presence globally
      if Phoenix.LiveView.connected?(socket) do
        track_user_presence(socket)
      end

      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: "/")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: "/dashboard")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
          |> Phoenix.LiveView.redirect(to: "/")

        {:halt, socket}

      not Accounts.is_admin?(socket.assigns.current_user) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must be an administrator to access this page.")
          |> Phoenix.LiveView.redirect(to: "/dashboard")

        {:halt, socket}

      true ->
        # Track admin user presence globally
        if Phoenix.LiveView.connected?(socket) do
          track_user_presence(socket)
        end

        {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_id = session["user_id"] do
        Accounts.get_user!(user_id)
      end
    end)
  end

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user!(user_id)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end

  defp track_user_presence(socket) do
    user = socket.assigns.current_user
    current_path = get_current_path(socket)

    # Update last_seen_at in database
    Task.start(fn ->
      Accounts.update_last_seen(user)
    end)

    # Track user presence on a global topic
    {:ok, _} =
      HermesWeb.Presence.track(self(), "users:online", user.id, %{
        email: user.email,
        role: user.role,
        current_view: current_path,
        joined_at: System.system_time(:second)
      })

    :ok
  end

  defp get_current_path(socket) do
    case socket.view do
      HermesWeb.DashboardLive -> "Dashboard"
      HermesWeb.RequestLive.Index -> "Backlog"
      HermesWeb.RequestLive.New -> "New Request"
      HermesWeb.RequestLive.Show -> "Request Details"
      HermesWeb.RequestLive.Edit -> "Edit Request"
      HermesWeb.KanbanLive.Index -> "Boards"
      HermesWeb.KanbanLive.Board -> "Kanban Board"
      HermesWeb.Admin.DashboardLive.Index -> "Admin Dashboard"
      HermesWeb.Admin.UserLive.Index -> "User Management"
      _ -> "Unknown"
    end
  end
end
