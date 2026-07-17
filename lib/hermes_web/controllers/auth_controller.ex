defmodule HermesWeb.AuthController do
  use HermesWeb, :controller

  alias Hermes.Accounts

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/")

      user ->
        # Hash input password and compare with stored hash
        hashed_input = :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)

        if user.hashed_password == hashed_input do
          return_to = safe_return_to(get_session(conn, :user_return_to))

          conn
          |> put_flash(:info, "Welcome back, #{Hermes.Accounts.User.display_name(user)}!")
          |> delete_session(:user_return_to)
          |> put_session(:user_id, user.id)
          |> configure_session(renew: true)
          |> redirect(to: return_to)
        else
          conn
          |> put_flash(:error, "Invalid email or password")
          |> redirect(to: ~p"/")
        end
    end
  end

  # Only follow local paths; anything else (nil, external or
  # protocol-relative URLs) falls back to the dashboard.
  defp safe_return_to("//" <> _), do: ~p"/dashboard"
  defp safe_return_to("/" <> _ = path), do: path
  defp safe_return_to(_), do: ~p"/dashboard"

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> clear_session()
    |> redirect(to: ~p"/")
  end
end
