defmodule HermesWeb.Plugs.Locale do
  @moduledoc """
  Plug to handle locale setting from session or query parameters.
  """
  import Plug.Conn

  @supported_locales ["en", "es"]
  @default_locale "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = get_locale_from_params(conn) || get_locale_from_session(conn) || @default_locale

    if locale in @supported_locales do
      Gettext.put_locale(HermesWeb.Gettext, locale)

      conn
      |> put_session(:locale, locale)
      |> Plug.Conn.assign(:locale, locale)
    else
      conn
    end
  end

  defp get_locale_from_params(conn) do
    conn.params["locale"]
  end

  defp get_locale_from_session(conn) do
    get_session(conn, :locale)
  end

  @doc """
  LiveView on_mount hook to set locale in socket assigns
  """
  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || @default_locale
    Gettext.put_locale(HermesWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  @doc """
  Returns the default locale.
  """
  def default_locale, do: @default_locale
end
