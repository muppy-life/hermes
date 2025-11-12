defmodule HermesWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: HermesWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a back button with consistent styling across the app.

  ## Examples

      <.back_button navigate={~p"/boards"}>Back to Boards</.back_button>
      <.back_button navigate={@return_to} />
  """
  attr :navigate, :string, required: true, doc: "the path to navigate back to"
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block

  def back_button(assigns) do
    assigns =
      assigns
      |> assign_new(:inner_block, fn -> [] end)
      |> assign(:btn_class, ["btn btn-ghost", assigns[:class]] |> Enum.reject(&is_nil/1) |> Enum.join(" "))

    ~H"""
    <.link navigate={@navigate}>
      <.button class={@btn_class} {@rest}>
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          Back
        <% end %>
      </.button>
    </.link>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-4", "pb-2"]}>
      <div>
        <h1 class="text-base font-semibold leading-6">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-xs text-base-content/70 mt-0.5">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none flex gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(HermesWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(HermesWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a priority badge with color coding from yellow (low) to red (critical).

  ## Examples

      <.priority_badge priority={1} />
      <.priority_badge priority={4} size="sm" />
  """
  attr :priority, :integer, required: true, doc: "priority level (1-4)"
  attr :size, :string, default: "md", values: ["sm", "md", "lg"], doc: "badge size"
  attr :rest, :global, doc: "arbitrary HTML attributes"

  def priority_badge(assigns) do
    ~H"""
    <span class={[
      "badge whitespace-nowrap",
      priority_size_class(@size),
      priority_color_class(@priority)
    ]} {@rest}>
      <%= priority_label(@priority) %>
    </span>
    """
  end

  defp priority_label(priority) do
    case priority do
      1 -> "Low"
      2 -> "Normal"
      3 -> "Important"
      4 -> "Critical"
      _ -> "Unknown"
    end
  end

  defp priority_color_class(priority) do
    case priority do
      1 -> "bg-yellow-200 text-yellow-900 border-yellow-300"
      2 -> "bg-orange-200 text-orange-900 border-orange-300"
      3 -> "bg-red-300 text-red-900 border-red-400"
      4 -> "bg-red-500 text-white border-red-600"
      _ -> "badge-ghost"
    end
  end

  @doc """
  Returns priority color classes for use in filters and other components.
  Accepts both integer and string priority values.

  ## Examples

      priority_filter_class("4") # => "bg-red-500 text-white border-red-600"
      priority_filter_class(1) # => "bg-yellow-200 text-yellow-900 border-yellow-300"
  """
  def priority_filter_class(priority) when is_binary(priority) do
    case priority do
      "4" -> "bg-red-500 text-white border-red-600"
      "3" -> "bg-red-300 text-red-900 border-red-400"
      "2" -> "bg-orange-200 text-orange-900 border-orange-300"
      "1" -> "bg-yellow-200 text-yellow-900 border-yellow-300"
      _ -> "bg-transparent hover:bg-base-300"
    end
  end

  def priority_filter_class(priority) when is_integer(priority) do
    priority_filter_class(Integer.to_string(priority))
  end

  def priority_filter_class(_), do: "bg-transparent hover:bg-base-300"

  defp priority_size_class(size) do
    case size do
      "sm" -> "badge-sm text-xs"
      "md" -> "badge-md text-sm"
      "lg" -> "badge-lg text-base"
      _ -> "badge-md text-sm"
    end
  end

  @doc """
  Renders a status badge with color coding based on request status.

  ## Examples

      <.status_badge status="pending" />
      <.status_badge status="completed" size="sm" />
  """
  attr :status, :string, required: true, doc: "request status"
  attr :size, :string, default: "md", values: ["sm", "md", "lg"], doc: "badge size"
  attr :rest, :global, doc: "arbitrary HTML attributes"

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge whitespace-nowrap",
      status_size_class(@size),
      status_color_class(@status)
    ]} {@rest}>
      <%= status_label(@status) %>
    </span>
    """
  end

  defp status_label(status) do
    case status do
      "pending" -> "Pending"
      "in_progress" -> "In Progress"
      "completed" -> "Completed"
      "blocked" -> "Blocked"
      _ -> String.capitalize(status)
    end
  end

  defp status_color_class(status) do
    case status do
      "pending" -> "bg-yellow-200 text-yellow-900 border-yellow-300"
      "in_progress" -> "bg-blue-200 text-blue-900 border-blue-300"
      "completed" -> "bg-green-200 text-green-900 border-green-300"
      "blocked" -> "bg-red-200 text-red-900 border-red-300"
      _ -> "badge-ghost"
    end
  end

  defp status_size_class(size) do
    case size do
      "sm" -> "badge-sm text-xs"
      "md" -> "badge-md text-sm"
      "lg" -> "badge-lg text-base"
      _ -> "badge-md text-sm"
    end
  end

  @doc """
  Renders a kind badge with color coding based on request type.

  ## Examples

      <.kind_badge kind="problem" />
      <.kind_badge kind="new_need" size="sm" />
  """
  attr :kind, :string, required: true, doc: "request kind/type"
  attr :size, :string, default: "md", values: ["sm", "md", "lg"], doc: "badge size"
  attr :rest, :global, doc: "arbitrary HTML attributes"

  def kind_badge(assigns) do
    ~H"""
    <span class={[
      "badge whitespace-nowrap",
      kind_size_class(@size),
      kind_color_class(@kind)
    ]} {@rest}>
      <%= kind_label(@kind) %>
    </span>
    """
  end

  defp kind_label(kind) do
    case kind do
      "problem" -> "Problem"
      :problem -> "Problem"
      "new_need" -> "New Need"
      :new_need -> "New Need"
      "improvement" -> "Improvement"
      :improvement -> "Improvement"
      _ when is_atom(kind) -> kind |> Atom.to_string() |> String.capitalize()
      _ when is_binary(kind) -> String.capitalize(kind)
      _ -> "Unknown"
    end
  end

  defp kind_color_class(kind) do
    case kind do
      "problem" -> "bg-red-200 text-red-900 border-red-300"
      :problem -> "bg-red-200 text-red-900 border-red-300"
      "new_need" -> "bg-green-200 text-green-900 border-green-300"
      :new_need -> "bg-green-200 text-green-900 border-green-300"
      "improvement" -> "bg-blue-200 text-blue-900 border-blue-300"
      :improvement -> "bg-blue-200 text-blue-900 border-blue-300"
      _ -> "badge-ghost"
    end
  end

  defp kind_size_class(size) do
    case size do
      "sm" -> "badge-sm text-xs"
      "md" -> "badge-md text-sm"
      "lg" -> "badge-lg text-base"
      _ -> "badge-md text-sm"
    end
  end

  @doc """
  Renders a filter bar for requests.

  ## Examples

      <.request_filters
        show_status={true}
        filter_status={@filter_status}
        filter_priority={@filter_priority}
        filter_team={@filter_team}
        teams={@teams}
        total_count={@total_count}
      />
  """
  attr :show_status, :boolean, default: true, doc: "whether to show the status filter"
  attr :filter_status, :string, default: "all"
  attr :filter_priority, :string, default: "all"
  attr :filter_team, :string, default: "all"
  attr :teams, :list, required: true
  attr :total_count, :integer, default: 0

  def request_filters(assigns) do
    ~H"""
    <div class="bg-base-100 shadow-sm border border-base-300 rounded-lg p-3 mt-2 sticky top-12 z-10">
      <div class="flex items-center justify-between gap-3">
        <form phx-change="apply_filters" class="flex-1">
          <div class={["grid grid-cols-1 gap-3", if(@show_status, do: "md:grid-cols-4", else: "md:grid-cols-3")]}>
            <!-- Status Filter -->
            <%= if @show_status do %>
              <select class="select select-bordered select-sm" name="status">
                <option value="all" selected={@filter_status == "all"}>All Statuses</option>
                <option value="new" selected={@filter_status == "new"}>New</option>
                <option value="pending" selected={@filter_status == "pending"}>Pending</option>
                <option value="in_progress" selected={@filter_status == "in_progress"}>In Progress</option>
                <option value="review" selected={@filter_status == "review"}>Review</option>
                <option value="completed" selected={@filter_status == "completed"}>Completed</option>
                <option value="blocked" selected={@filter_status == "blocked"}>Blocked</option>
              </select>
            <% end %>

            <!-- Priority Filter -->
            <select class="select select-bordered select-sm" name="priority">
              <option value="all" selected={@filter_priority == "all"}>All Priorities</option>
              <option value="4" selected={@filter_priority == "4"}>Critical</option>
              <option value="3" selected={@filter_priority == "3"}>Important</option>
              <option value="2" selected={@filter_priority == "2"}>Normal</option>
              <option value="1" selected={@filter_priority == "1"}>Low</option>
            </select>

            <!-- Team Filter -->
            <select class="select select-bordered select-sm" name="team">
              <option value="all" selected={@filter_team == "all"}>All Teams</option>
              <%= for team <- @teams do %>
                <option value={team.id} selected={@filter_team == to_string(team.id)}><%= team.name %></option>
              <% end %>
            </select>

            <!-- Clear Filters Button -->
            <button type="button" phx-click="clear_filters" class="btn btn-outline btn-sm">
              Clear
            </button>
          </div>
        </form>

        <!-- Item Count -->
        <div class="text-sm opacity-70 whitespace-nowrap">
          <%= @total_count %> items
        </div>
      </div>
    </div>
    """
  end
end
