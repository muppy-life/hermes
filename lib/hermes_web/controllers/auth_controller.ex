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
        # Hash the input password and compare with stored hash
        hashed_input = :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
        if user.hashed_password == hashed_input do
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
