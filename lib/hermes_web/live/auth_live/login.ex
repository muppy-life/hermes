defmodule HermesWeb.AuthLive.Login do
  use HermesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # If already logged in, redirect to dashboard
    if socket.assigns[:current_user] do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      {:ok, assign(socket, :page_title, gettext("Login"))}
    end
  end
end
