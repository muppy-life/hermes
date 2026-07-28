defmodule HermesWeb.Api.MeController do
  @moduledoc "Returns the authenticated token owner. Useful for verifying a token."
  use HermesWeb, :controller

  alias Hermes.Accounts.User

  def show(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      data: %{
        id: user.id,
        name: User.display_name(user),
        email: user.email,
        role: user.role,
        is_admin: user.is_admin
      }
    })
  end
end
