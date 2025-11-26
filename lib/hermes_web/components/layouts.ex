defmodule HermesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HermesWeb, :html

  # Compile-time environment detection (Mix is not available in releases)
  @mix_env Mix.env()
  def mix_env, do: @mix_env

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the current user"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-base-100 m-0 p-0">
      <header class="navbar bg-base-300 px-4 py-0 sm:px-6 lg:px-8 fixed top-0 z-50 justify-between w-full m-0 min-h-[64px] h-[64px]">
        <div class="flex items-center gap-3">
          <a
            href={if @current_user, do: ~p"/dashboard", else: ~p"/"}
            class="flex items-center transition-transform hover:scale-110"
          >
            <img
              src={HermesWeb.Endpoint.static_url() <> "/images/logo_light_themes.png"}
              width="32"
              class="dark:hidden [[data-theme=dark]_&]:hidden"
            />
            <img
              src={HermesWeb.Endpoint.static_url() <> "/images/logo_dark_themes.png"}
              width="32"
              class="hidden dark:block [[data-theme=dark]_&]:block [[data-theme=light]_&]:hidden"
            />
          </a>
          <%= if @current_user do %>
            <div class="text-sm">
              <div class="font-semibold">{@current_user.email}</div>
              <div class="text-xs text-gray-600">{Phoenix.Naming.humanize(@current_user.role)}</div>
            </div>
          <% end %>
        </div>
        <%= if @current_user do %>
          <div class="flex items-center">
            <ul class="flex flex-row items-center">
              <li>
                <a href={~p"/dashboard"} class="btn btn-ghost">{gettext("Dashboard")}</a>
              </li>
              <li>
                <a href={~p"/backlog"} class="btn btn-ghost">{gettext("Backlog")}</a>
              </li>
              <li>
                <a href={~p"/boards"} class="btn btn-ghost">{gettext("Boards")}</a>
              </li>
              <%= if Hermes.Accounts.is_admin?(@current_user) do %>
                <li>
                  <a href={~p"/admin"} class="btn btn-ghost">{gettext("Admin")}</a>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
        <div class="flex items-center">
          <ul class="flex flex-row items-center">
            <li>
              <.language_selector locale={assigns[:locale] || "en"} />
            </li>
            <li>
              <.theme_toggle />
            </li>
            <%= if @current_user do %>
              <li>
                <.link href={~p"/logout"} method="delete" class="btn btn-ghost">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </header>

      <main class="fixed top-[64px] bottom-[30px] left-0 right-0 overflow-auto bg-base-100">
        <div class="mx-8 h-full">
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="fixed bottom-0 left-0 right-0 border-t border-base-300 bg-base-100 flex-shrink-0 z-40">
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 h-[30px] flex items-center">
          <div class="flex items-center justify-between gap-2 text-[10px] text-base-content/60 w-full">
            <div class="flex items-center gap-2">
              <span>© 2025 Muppy</span>
              <span class="hidden sm:inline">•</span>
              <a href="mailto:tech@muppy.com" class="hover:text-primary transition-colors">
                tech@muppy.com
              </a>
            </div>
            <div class="flex items-center gap-2">
              <%= if mix_env() != :prod do %>
                <span class={"badge badge-xs #{if mix_env() == :dev, do: "badge-warning", else: "badge-info"}"}>
                  {mix_env() |> Atom.to_string() |> String.upcase()}
                </span>
                <span class="hidden sm:inline">•</span>
              <% end %>
              <span>v0.1.0</span>
              <span class="hidden sm:inline">•</span>
              <span>Updated {Calendar.strftime(DateTime.utc_now(), "%b %d, %Y")}</span>
            </div>
          </div>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides language selector for internationalization.
  """
  attr :locale, :string, default: nil

  def language_selector(assigns) do
    # Get current locale from Gettext
    current_locale = Gettext.get_locale(HermesWeb.Gettext)
    assigns = assign(assigns, :current_locale, current_locale)

    ~H"""
    <div class="dropdown dropdown-end">
      <button tabindex="0" class="btn btn-ghost">
        <%= case @current_locale do %>
          <% "es" -> %>
            <span class="text-xl">🇪🇸</span>
          <% _ -> %>
            <span class="text-xl">🇺🇸</span>
        <% end %>
      </button>
      <ul
        tabindex="0"
        class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-40 border border-base-300 mt-1"
      >
        <li>
          <a href="?locale=en" class={["gap-2", @current_locale == "en" && "active"]}>
            <span class="text-lg">🇺🇸</span>
            <span>English</span>
          </a>
        </li>
        <li>
          <a href="?locale=es" class={["gap-2", @current_locale == "es" && "active"]}>
            <span class="text-lg">🇪🇸</span>
            <span>Español</span>
          </a>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <button
      class="btn btn-ghost [[data-theme=light]_&]:hidden [[data-theme=system]_&]:hidden"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="light"
    >
      <span class="text-xl">🌙</span>
    </button>
    <button
      class="btn btn-ghost [[data-theme=dark]_&]:hidden"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="dark"
    >
      <span class="text-xl">☀️</span>
    </button>
    """
  end
end
