defmodule HermesWeb.NotificationLive.Index do
  use HermesWeb, :live_view

  alias Hermes.Notifications

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    notifications = Notifications.list_notifications(current_user.id)

    Notifications.mark_all_as_read(current_user.id)

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:notifications, notifications)
     |> assign(:unread_notifications_count, 0)}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    notification =
      Enum.find(socket.assigns.notifications, &(to_string(&1.id) == id))

    if notification do
      Notifications.mark_as_read(notification, current_user.id)

      updated =
        Enum.map(socket.assigns.notifications, fn n ->
          if n.id == notification.id,
            do: %{n | read_at: DateTime.utc_now() |> DateTime.truncate(:second)},
            else: n
        end)

      {:noreply, assign(socket, :notifications, updated)}
    else
      {:noreply, socket}
    end
  end
end
