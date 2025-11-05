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
        # For MVP: simple password check (in production use proper hashing!)
        if user.hashed_password == password do
          conn
          |> put_flash(:info, "Welcome back, #{user.email}!")
          |> put_session(:user_id, user.id)
          |> configure_session(renew: true)
          |> redirect(to: ~p"/dashboard")
        else
          conn
          |> put_flash(:error, "Invalid email or password")
          |> redirect(to: ~p"/")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> clear_session()
    |> redirect(to: ~p"/")
  end
end
