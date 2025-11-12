defmodule HermesWeb.AuthLive.Login do
  use HermesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # If already logged in, redirect to dashboard
    if socket.assigns[:current_user] do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      # Show demo accounts only in dev/test environments
      show_demo_accounts = Application.get_env(:hermes, :env) in [:dev, :test]

      socket = socket
      |> assign(:page_title, gettext("Login"))
      |> assign(:show_demo_accounts, show_demo_accounts)

      {:ok, socket}
    end
  end
end
