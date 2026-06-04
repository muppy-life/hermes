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
  attr :unread_notifications_count, :integer, default: 0, doc: "number of unread notifications"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-base-100 m-0 p-0">
      <header class="bg-base-200 border-b border-base-300 px-7 fixed top-0 z-50 flex items-center gap-[18px] w-full m-0 h-[72px]">
        <div class="flex items-center gap-2.5 w-52">
          <a
            href={if @current_user, do: ~p"/dashboard", else: ~p"/"}
            class="flex items-center gap-2.5 transition-transform hover:scale-105"
          >
            <img
              src={HermesWeb.Endpoint.static_url() <> "/images/logo_light_themes.png"}
              class="h-8 w-auto block dark:hidden [[data-theme=dark]_&]:hidden"
            />
            <img
              src={HermesWeb.Endpoint.static_url() <> "/images/logo_dark_themes.png"}
              class="h-8 w-auto hidden dark:block [[data-theme=dark]_&]:block [[data-theme=light]_&]:hidden"
            />
            <span class="text-base font-bold text-base-content tracking-tight leading-none">
              Hermes
              <small class="block text-[10px] font-medium text-base-content/50 tracking-wide uppercase mt-0.5">
                muppy
              </small>
            </span>
          </a>
        </div>

        <%= if @current_user do %>
          <nav id="nav-tabs" phx-hook="ActiveNav" class="flex-1 flex justify-center">
            <div class="flex gap-0.5 bg-base-300 p-1 rounded-full">
              <a href={~p"/dashboard"} class={nav_tab_class()} data-path="/dashboard">
                <.icon name="hero-squares-2x2" class="size-3.5" />{gettext("Dashboard")}
              </a>
              <a href={~p"/backlog"} class={nav_tab_class()} data-path="/backlog">
                <.icon name="hero-list-bullet" class="size-3.5" />{gettext("Backlog")}
              </a>
              <a href={~p"/boards"} class={nav_tab_class()} data-path="/boards">
                <.icon name="hero-view-columns" class="size-3.5" />{gettext("Boards")}
              </a>
              <%= if Hermes.Accounts.is_admin?(@current_user) do %>
                <a href={~p"/admin"} class={nav_tab_class()} data-path="/admin">
                  <.icon name="hero-cog-6-tooth" class="size-3.5" />{gettext("Admin")}
                </a>
              <% end %>
            </div>
          </nav>
        <% else %>
          <div class="flex-1"></div>
        <% end %>

        <div class="flex items-center justify-end gap-2 w-52">
          <%= if @current_user do %>
            <%!-- Search is not wired up yet; visual-only stub matching the topnav design. --%>
            <button
              type="button"
              class="shrink-0 w-[38px] h-[38px] bg-base-300 hover:bg-base-content/10 rounded-full flex items-center justify-center text-base-content/70 hover:text-base-content transition-colors"
              title={gettext("Search")}
              phx-click={show_coming_soon(gettext("Search"))}
            >
              <.icon name="hero-magnifying-glass" class="size-[17px]" />
            </button>
          <% end %>
          <.language_selector locale={assigns[:locale] || "en"} />
          <%= if @current_user do %>
            <.link
              href={~p"/notifications"}
              class="relative shrink-0 w-[38px] h-[38px] bg-base-300 hover:bg-base-content/10 rounded-full flex items-center justify-center text-base-content/70 hover:text-base-content transition-colors"
              title={gettext("Notifications")}
            >
              <.icon name="hero-bell" class="size-[17px]" />
              <%= if @unread_notifications_count > 0 do %>
                <span class="badge badge-error badge-xs absolute -top-0.5 -right-0.5">
                  {if @unread_notifications_count > 99,
                    do: "99+",
                    else: @unread_notifications_count}
                </span>
              <% end %>
            </.link>
            <.user_menu current_user={@current_user} />
          <% else %>
            <.theme_toggle />
          <% end %>
        </div>
      </header>

      <main class="fixed top-[72px] bottom-[30px] left-0 right-0 overflow-auto bg-base-100">
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

    <%!-- Toast stack (bottom-right). Toasts are appended by the app-toast
         handler in app.js; styling lives in app.css (.app-toast). --%>
    <div id="toast-c" class="fixed bottom-6 right-6 z-[500] flex flex-col gap-2"></div>

    <.flash_group flash={@flash} />
    """
  end

  # Client-side JS to show a "coming soon" toast. The full message is
  # composed here (gettext is server-side) and shown by the app-toast
  # handler in app.js.
  defp show_coming_soon(feature) do
    message = gettext("%{feature} is coming soon. Stay tuned!", feature: feature)
    JS.dispatch("phx:app-toast", detail: %{message: message, type: "info"})
  end

  # Tailwind/daisyUI classes for a top-nav pill tab. The active state
  # (bg-primary) is toggled client-side by the ActiveNav hook.
  defp nav_tab_class do
    "nav-tab flex items-center gap-1.5 px-[18px] py-2 rounded-full text-[12.5px] " <>
      "font-medium text-base-content/70 hover:text-base-content whitespace-nowrap " <>
      "transition-colors cursor-pointer"
  end

  # Two-letter initials derived from the email local-part.
  defp user_initials(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.replace(~r/[._-]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp user_initials(_), do: "?"

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
      <button
        tabindex="0"
        class="shrink-0 h-[38px] px-3 bg-base-300 hover:bg-base-content/10 rounded-full flex items-center justify-center gap-1.5 text-base-content/70 hover:text-base-content text-[11.5px] font-semibold tracking-wider transition-colors"
        title={gettext("Change language")}
      >
        <.icon name="hero-language" class="size-[15px] text-base-content/50" />
        {String.upcase(@current_locale)}
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
      class="shrink-0 w-[38px] h-[38px] bg-base-300 hover:bg-base-content/10 rounded-full flex items-center justify-center text-base-content/70 hover:text-base-content transition-colors [[data-theme=light]_&]:hidden [[data-theme=system]_&]:hidden"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="light"
      title="Light mode"
    >
      <.icon name="hero-moon" class="size-[17px]" />
    </button>
    <button
      class="shrink-0 w-[38px] h-[38px] bg-base-300 hover:bg-base-content/10 rounded-full flex items-center justify-center text-base-content/70 hover:text-base-content transition-colors [[data-theme=dark]_&]:hidden"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="dark"
      title="Dark mode"
    >
      <.icon name="hero-sun" class="size-[17px]" />
    </button>
    """
  end

  @doc """
  Profile dropdown anchored to the avatar. Holds account info plus the
  profile, theme and logout actions (the theme toggle lives here rather
  than as a standalone header button).
  """
  attr :current_user, :map, required: true

  def user_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button
        tabindex="0"
        class="shrink-0 w-[38px] h-[38px] rounded-full bg-primary text-primary-content flex items-center justify-center text-xs font-semibold tracking-wide cursor-pointer"
        title={@current_user.email}
      >
        {user_initials(@current_user.email)}
      </button>
      <ul
        tabindex="0"
        class="dropdown-content z-[1] menu p-1.5 shadow-md bg-base-200 rounded-box w-72 border border-base-300 mt-1 gap-0.5"
      >
        <li class="menu-title pointer-events-none -mx-1.5 -mt-1.5 mb-1.5 !p-0 border-b border-base-content/15">
          <div class="flex items-center gap-3 px-3 py-3.5">
            <span class="shrink-0 w-[38px] h-[38px] rounded-full bg-primary text-primary-content flex items-center justify-center text-[13px] font-semibold tracking-wide">
              {user_initials(@current_user.email)}
            </span>
            <div class="min-w-0 flex-1">
              <div class="text-[13px] font-semibold text-base-content truncate leading-tight">
                {@current_user.email}
              </div>
              <div class="text-[11px] text-base-content/50 leading-tight mt-0.5">
                {Phoenix.Naming.humanize(@current_user.role)}
              </div>
            </div>
          </div>
        </li>

        <li>
          <button
            type="button"
            class="gap-2.5 text-base-content/70"
            phx-click={show_coming_soon(gettext("My profile"))}
          >
            <.icon name="hero-user" class="size-[15px] text-base-content/40" />{gettext("My profile")}
          </button>
        </li>
        <%= if Hermes.Accounts.is_admin?(@current_user) do %>
          <li>
            <.link href={~p"/admin"} class="gap-2.5 text-base-content/70">
              <.icon name="hero-shield-check" class="size-[15px] text-base-content/40" />{gettext(
                "Admin"
              )}
            </.link>
          </li>
        <% end %>
        <li>
          <button
            type="button"
            class="gap-2.5 text-base-content/70"
            phx-click={show_coming_soon(gettext("Shortcuts"))}
          >
            <.icon name="hero-command-line" class="size-[15px] text-base-content/40" />{gettext(
              "Shortcuts"
            )}
            <kbd class="ml-auto text-[10.5px] text-base-content/40 font-normal">⌘K</kbd>
          </button>
        </li>

        <li class="mt-1.5 -mx-1.5 px-1.5 border-t border-base-content/15 pt-1.5">
          <button
            type="button"
            class="gap-2.5 text-base-content/70 [[data-theme=dark]_&]:hidden"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="dark"
          >
            <.icon name="hero-moon" class="size-[15px] text-base-content/40" />{gettext("Dark mode")}
          </button>
          <button
            type="button"
            class="gap-2.5 text-base-content/70 hidden [[data-theme=dark]_&]:flex"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="light"
          >
            <.icon name="hero-sun" class="size-[15px] text-base-content/40" />{gettext("Light mode")}
          </button>
        </li>
        <li>
          <button
            type="button"
            class="gap-2.5 text-base-content/70"
            phx-click={show_coming_soon(gettext("Help center"))}
          >
            <.icon name="hero-question-mark-circle" class="size-[15px] text-base-content/40" />{gettext(
              "Help center"
            )}
          </button>
        </li>

        <li class="mt-1.5 -mx-1.5 px-1.5 border-t border-base-content/15 pt-1.5">
          <.link href={~p"/logout"} method="delete" class="gap-2.5 text-error hover:bg-error/10">
            <.icon name="hero-arrow-right-on-rectangle" class="size-[15px]" />{gettext("Logout")}
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
