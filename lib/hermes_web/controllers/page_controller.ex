defmodule HermesWeb.PageController do
  use HermesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
