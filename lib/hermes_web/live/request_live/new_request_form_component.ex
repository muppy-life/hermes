defmodule HermesWeb.RequestLive.NewRequestFormComponent do
  use HermesWeb, :live_component

  require Logger

  alias Hermes.Accounts
  alias Hermes.Requests

  @max_file_size 15 * 1_024 * 1_024

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_step, fn -> 1 end)
     |> assign_new(:form_data, fn -> default_form_data() end)
     |> assign_new(:submitted, fn -> false end)
     |> assign_new(:created_request, fn -> nil end)
     |> allow_upload(:files,
       accept: ~w(.jpg .jpeg .png .pdf .doc .docx .xls .xlsx),
       max_entries: 10,
       max_file_size: @max_file_size,
       auto_upload: true
     )}
  end

  defp default_form_data do
    %{
      "title" => "",
      "kind" => "",
      "priority" => nil,
      "target_user_type" => "",
      "current_situation" => "",
      "goal_description" => "",
      "impact_area" => "",
      "impact_level" => "",
      "goal_target" => ""
    }
  end

  # === Event handlers ===

  @impl true
  def handle_event("pick", %{"field" => field, "pick" => value}, socket)
      when field in ~w(kind target_user_type goal_target) do
    {:noreply, assign(socket, :form_data, Map.put(socket.assigns.form_data, field, value))}
  end

  def handle_event("pick_priority", %{"priority" => priority}, socket) do
    {:noreply,
     assign(
       socket,
       :form_data,
       Map.put(socket.assigns.form_data, "priority", to_priority(priority))
     )}
  end

  def handle_event("pick_impact", %{"area" => area}, socket) do
    {:noreply, assign(socket, :form_data, Map.put(socket.assigns.form_data, "impact_area", area))}
  end

  def handle_event("pick_level", %{"level" => level}, socket) do
    {:noreply,
     assign(socket, :form_data, Map.put(socket.assigns.form_data, "impact_level", level))}
  end

  def handle_event("validate", %{"request" => params}, socket) do
    {:noreply, assign(socket, :form_data, Map.merge(socket.assigns.form_data, params))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("go_step", %{"step" => step} = params, socket) do
    current_step = socket.assigns.current_step
    target_step = parse_step(step, current_step)
    form_data = Map.merge(socket.assigns.form_data, Map.get(params, "request", %{}))

    # Backward navigation skips validation so users can revise earlier steps.
    if target_step <= current_step do
      {:noreply,
       socket
       |> assign(:form_data, form_data)
       |> assign(:current_step, target_step)}
    else
      case validate_step(current_step, form_data) do
        :ok ->
          {:noreply,
           socket
           |> assign(:form_data, form_data)
           |> assign(:current_step, target_step)}

        {:error, msg} ->
          send(self(), {:new_request_flash, :error, msg})
          {:noreply, assign(socket, :form_data, form_data)}
      end
    end
  end

  def handle_event("cancel", _params, socket) do
    send(self(), :hide_new_request)
    {:noreply, socket}
  end

  def handle_event("submit", params, socket) do
    form_data = Map.merge(socket.assigns.form_data, Map.get(params, "request", %{}))

    case validate_step(3, form_data) do
      :ok ->
        do_submit(form_data, socket)

      {:error, msg} ->
        send(self(), {:new_request_flash, :error, msg})
        {:noreply, assign(socket, :form_data, form_data)}
    end
  end

  def handle_event("close_success", _params, socket) do
    send(self(), :hide_new_request)
    {:noreply, socket}
  end

  defp do_submit(form_data, socket) do
    current_user = socket.assigns.current_user
    dev_team = Accounts.get_dev_team()

    if is_nil(dev_team) do
      Logger.warning("No dev team found — new request will have no assigned team")
    end

    final_params =
      form_data
      |> Map.update("kind", nil, &kind_to_enum/1)
      |> Map.update("impact_area", nil, &impact_area_to_enum/1)
      |> Map.update("impact_level", nil, &impact_level_to_enum/1)
      |> blank_to_nil()
      |> Map.put("created_by_id", current_user.id)
      |> Map.put("requesting_team_id", current_user.team_id)
      |> Map.put("assigned_to_team_id", dev_team && dev_team.id)
      |> Map.put("status", "new")

    case Requests.create_request(final_params, current_user.id) do
      {:ok, request} ->
        consume_uploaded_files(socket, request.id)
        send(self(), {:new_request_created, request})

        {:noreply,
         socket
         |> assign(:submitted, true)
         |> assign(:created_request, request)
         |> assign(:current_step, 4)}

      {:error, %Ecto.Changeset{} = changeset} ->
        send(self(), {:new_request_flash, :error, format_errors(changeset)})
        {:noreply, assign(socket, :current_step, 1)}
    end
  end

  defp consume_uploaded_files(socket, request_id) do
    consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
      result =
        Requests.upload_request_image(request_id, %{
          path: path,
          client_name: entry.client_name,
          content_type: entry.client_type
        })

      case result do
        {:ok, _} = ok ->
          {:ok, ok}

        {:error, reason} ->
          Logger.warning("Failed to upload request attachment: #{inspect(reason)}")
          {:ok, {:error, reason}}
      end
    end)
  end

  # === Helpers ===

  defp to_priority("critica"), do: 4
  defp to_priority("importante"), do: 3
  defp to_priority("normal"), do: 2
  defp to_priority("baja"), do: 1
  defp to_priority(_), do: nil

  defp blank_to_nil(params) do
    Map.new(params, fn
      {k, v} when is_binary(v) -> if String.trim(v) == "", do: {k, nil}, else: {k, v}
      pair -> pair
    end)
  end

  defp parse_step(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n >= 1 and n <= 3 -> n
      _ -> fallback
    end
  end

  defp validate_step(1, form_data) do
    cond do
      blank?(form_data["title"]) -> {:error, gettext("Title is required")}
      blank?(form_data["kind"]) -> {:error, gettext("Select the type of need")}
      is_nil(form_data["priority"]) -> {:error, gettext("Select the priority")}
      blank?(form_data["target_user_type"]) -> {:error, gettext("Select the target user")}
      true -> :ok
    end
  end

  defp validate_step(2, form_data) do
    cond do
      blank?(form_data["current_situation"]) ->
        {:error, gettext("Describe the current situation")}

      blank?(form_data["goal_description"]) ->
        {:error, gettext("Describe the expected result")}

      true ->
        :ok
    end
  end

  defp validate_step(3, form_data) do
    cond do
      blank?(form_data["impact_area"]) -> {:error, gettext("Select the impact area")}
      blank?(form_data["impact_level"]) -> {:error, gettext("Select the impact level")}
      true -> :ok
    end
  end

  defp validate_step(_, _), do: :ok

  defp blank?(nil), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp priority_label(4), do: gettext("Critical")
  defp priority_label(3), do: gettext("Important")
  defp priority_label(2), do: gettext("Normal")
  defp priority_label(1), do: gettext("Low")
  defp priority_label(_), do: "—"

  defp kind_label("problema"), do: gettext("Operational problem")
  defp kind_label("nueva"), do: gettext("New need")
  defp kind_label("mejora"), do: gettext("Improvement")
  defp kind_label(_), do: "—"

  defp kind_to_enum("problema"), do: "problem"
  defp kind_to_enum("nueva"), do: "new_need"
  defp kind_to_enum("mejora"), do: "improvement"
  defp kind_to_enum(other), do: other

  defp impact_label("costes"), do: gettext("Reduces costs")
  defp impact_label("ingresos"), do: gettext("Increases revenue")
  defp impact_label("eficiencia"), do: gettext("Improves efficiency")
  defp impact_label("producto"), do: gettext("Improves product / UX")
  defp impact_label("otro"), do: gettext("Other")
  defp impact_label(_), do: "—"

  defp impact_area_to_enum("costes"), do: "cost_reduction"
  defp impact_area_to_enum("ingresos"), do: "revenue_increase"
  defp impact_area_to_enum("eficiencia"), do: "efficiency"
  defp impact_area_to_enum("producto"), do: "product_ux"
  defp impact_area_to_enum("otro"), do: "other"
  defp impact_area_to_enum(other), do: other

  defp level_label("alto"), do: gettext("High")
  defp level_label("medio"), do: gettext("Medium")
  defp level_label("bajo"), do: gettext("Low")
  defp level_label(_), do: "—"

  defp impact_level_to_enum("alto"), do: "high"
  defp impact_level_to_enum("medio"), do: "medium"
  defp impact_level_to_enum("bajo"), do: "low"
  defp impact_level_to_enum(other), do: other

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 15 MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("File type not accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files")
  defp upload_error_to_string(_), do: gettext("Upload error")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="new-request-overlay">
      <div id="form-overlay" class="open">
        <div id="form-inner">
          <aside id="form-sidebar">
            <div class="sidebar-hero-title">{gettext("Requests that drive real value")}</div>
            <div class="sidebar-hero-text">
              {gettext(
                "They are not tickets. They are business initiatives. The better you describe the problem, the faster we can execute."
              )}
            </div>

            <div class="fstep-rich-list">
              <div class={[
                "fstep-rich",
                @current_step == 1 && "active",
                @current_step > 1 && "done"
              ]}>
                <div class="fstep-rich-icon">
                  <.icon name="hero-clipboard-document-list" class="size-4" />
                </div>
                <div>
                  <div class="fstep-rich-lbl">{gettext("Request")}</div>
                  <div class="fstep-rich-desc">{gettext("Title, type, priority and user.")}</div>
                </div>
              </div>
              <div class={[
                "fstep-rich",
                @current_step == 2 && "active",
                @current_step > 2 && "done"
              ]}>
                <div class="fstep-rich-icon">
                  <.icon name="hero-document-text" class="size-4" />
                </div>
                <div>
                  <div class="fstep-rich-lbl">{gettext("Context")}</div>
                  <div class="fstep-rich-desc">
                    {gettext("Current situation and expected result.")}
                  </div>
                </div>
              </div>
              <div class={[
                "fstep-rich",
                @current_step == 3 && "active",
                @current_step > 3 && "done"
              ]}>
                <div class="fstep-rich-icon">
                  <.icon name="hero-chart-bar" class="size-4" />
                </div>
                <div>
                  <div class="fstep-rich-lbl">{gettext("Impact")}</div>
                  <div class="fstep-rich-desc">{gettext("Business value and deliverable.")}</div>
                </div>
              </div>
            </div>

            <div style="flex:1"></div>

            <button type="button" phx-click="cancel" phx-target={@myself} class="fcancel">
              {gettext("Cancel")}
            </button>
          </aside>

          <div id="form-content">
            <%!-- Step 1 — Request --%>
            <%= if @current_step == 1 do %>
              <form
                phx-change="validate"
                phx-submit="go_step"
                phx-target={@myself}
                id="step-1-form"
                class="form-step-screen active"
              >
                <input type="hidden" name="step" value="2" />

                <div class="form-scroll">
                  <div class="step1-head">
                    <div>
                      <div class="form-card-title">{gettext("What are you requesting?")}</div>
                      <div class="form-card-sub">
                        {gettext(
                          "Define the type of need, the urgency and who it affects. This helps the PM route it correctly from the start."
                        )}
                      </div>
                    </div>
                    <div class="priority-badge">
                      <div class="pb-label">{gettext("Estimated priority")}</div>
                      <div class="pb-value">{priority_label(@form_data["priority"])}</div>
                      <div class="pb-help">{gettext("Calculated when you pick the urgency.")}</div>
                    </div>
                  </div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("01 — Identification")}</div>
                      <div class="f-sec-title">{gettext("Give your request a name")}</div>
                      <div class="f-sec-sub">
                        {gettext(
                          "A clear title lets the PM understand the problem before reading the rest."
                        )}
                      </div>
                    </div>
                    <label class="form-label">
                      {gettext("Title")}<span class="req">*</span>
                    </label>
                    <input
                      type="text"
                      name="request[title]"
                      class="form-input"
                      placeholder={gettext("e.g. Automate lead export from HubSpot")}
                      value={@form_data["title"]}
                    />
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("02 — Type of need")}</div>
                      <div class="f-sec-title">{gettext("What best describes your case?")}</div>
                      <div class="f-sec-sub">
                        {gettext("Classify the demand to speed up routing to the right team.")}
                      </div>
                    </div>
                    <div class="ic-grid c3">
                      <.ico_card
                        field="kind"
                        value="problema"
                        selected={@form_data["kind"] == "problema"}
                        icon="hero-exclamation-triangle"
                        label={gettext("Operational problem")}
                        sub={gettext("Something is broken or blocking")}
                        target={@myself}
                      />
                      <.ico_card
                        field="kind"
                        value="nueva"
                        selected={@form_data["kind"] == "nueva"}
                        icon="hero-sparkles"
                        label={gettext("New need")}
                        sub={gettext("A capability that does not exist")}
                        target={@myself}
                      />
                      <.ico_card
                        field="kind"
                        value="mejora"
                        selected={@form_data["kind"] == "mejora"}
                        icon="hero-wrench-screwdriver"
                        label={gettext("Improvement")}
                        sub={gettext("Improve something existing")}
                        target={@myself}
                      />
                    </div>
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section" style="margin-bottom:0">
                    <div class="step1-split">
                      <div>
                        <div class="f-sec-head">
                          <div class="f-sec-num">{gettext("03 — Urgency")}</div>
                          <div class="f-sec-title">{gettext("How much does this block?")}</div>
                        </div>
                        <div class="prio-track">
                          <.prio_opt
                            p="critica"
                            selected={@form_data["priority"] == 4}
                            label={gettext("Critical")}
                            sub={gettext("Blocks now")}
                            target={@myself}
                          />
                          <.prio_opt
                            p="importante"
                            selected={@form_data["priority"] == 3}
                            label={gettext("High")}
                            sub={gettext("High impact")}
                            target={@myself}
                          />
                          <.prio_opt
                            p="normal"
                            selected={@form_data["priority"] == 2}
                            label={gettext("Normal")}
                            sub={gettext("No urgency")}
                            target={@myself}
                          />
                          <.prio_opt
                            p="baja"
                            selected={@form_data["priority"] == 1}
                            label={gettext("Low")}
                            sub={gettext("If there is time")}
                            target={@myself}
                          />
                        </div>
                      </div>
                      <div>
                        <div class="f-sec-head">
                          <div class="f-sec-num">{gettext("04 — Target user")}</div>
                          <div class="f-sec-title">{gettext("Who is this for?")}</div>
                        </div>
                        <div class="ic-grid c2">
                          <.ico_card
                            field="target_user_type"
                            value="internal"
                            selected={@form_data["target_user_type"] == "internal"}
                            icon="hero-building-office"
                            label={gettext("Internal team")}
                            target={@myself}
                            compact
                          />
                          <.ico_card
                            field="target_user_type"
                            value="external"
                            selected={@form_data["target_user_type"] == "external"}
                            icon="hero-users"
                            label={gettext("Client / provider")}
                            target={@myself}
                            compact
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="form-foot">
                  <button
                    type="button"
                    phx-click="cancel"
                    phx-target={@myself}
                    class="btn btn-ghost btn-sm"
                  >
                    {gettext("Cancel")}
                  </button>
                  <button type="submit" class="btn btn-primary btn-sm">
                    {gettext("Next")} <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
              </form>
            <% end %>

            <%!-- Step 2 — Context --%>
            <%= if @current_step == 2 do %>
              <form
                phx-change="validate"
                phx-submit="go_step"
                phx-target={@myself}
                id="step-2-form"
                class="form-step-screen active"
              >
                <input type="hidden" name="step" value="3" />
                <div class="form-scroll">
                  <div class="form-card-title">{gettext("Tell us the context")}</div>
                  <div class="form-card-sub" style="margin-bottom:26px">
                    {gettext(
                      "Context is what turns a ticket into an executable initiative. Be specific: who is affected, how often and what consequences it has."
                    )}
                  </div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("05 — Current situation")}</div>
                      <div class="f-sec-title">{gettext("What is happening today?")}</div>
                      <div class="f-sec-sub">
                        {gettext("Describe the current process, pain points and operational impact.")}
                      </div>
                    </div>
                    <textarea
                      name="request[current_situation]"
                      class="form-textarea"
                      placeholder={
                        gettext(
                          "Describe the current situation, what problems you have, which teams are affected and what consequences it has..."
                        )
                      }
                    ><%= @form_data["current_situation"] %></textarea>
                    <div class="f-hint">
                      {gettext("The more specific you are, the more precise the effort estimate.")}
                    </div>
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section" style="margin-bottom:0">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("06 — Expected result")}</div>
                      <div class="f-sec-title">{gettext("What do you want to achieve?")}</div>
                      <div class="f-sec-sub">
                        {gettext(
                          "Describe the ideal state. What should someone be able to do once this is solved?"
                        )}
                      </div>
                    </div>
                    <textarea
                      name="request[goal_description]"
                      class="form-textarea"
                      placeholder={
                        gettext(
                          "e.g. Reduce operational time from 4h to 15 minutes and eliminate manual data entry errors..."
                        )
                      }
                    ><%= @form_data["goal_description"] %></textarea>
                    <div class="f-hint">
                      {gettext("This result will guide the definition of acceptance criteria.")}
                    </div>
                  </div>
                </div>

                <div class="form-foot">
                  <button
                    type="button"
                    phx-click="go_step"
                    phx-value-step="1"
                    phx-target={@myself}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back")}
                  </button>
                  <button type="submit" class="btn btn-primary btn-sm">
                    {gettext("Next")} <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
              </form>
            <% end %>

            <%!-- Step 3 — Impact --%>
            <%= if @current_step == 3 do %>
              <form
                phx-change="validate"
                phx-submit="submit"
                phx-target={@myself}
                id="step-3-form"
                class="form-step-screen active"
              >
                <div class="form-scroll">
                  <div class="form-card-title">{gettext("Business value")}</div>
                  <div class="form-card-sub" style="margin-bottom:26px">
                    {gettext(
                      "Help us prioritise correctly. Which area improves and how much impact does it have?"
                    )}
                  </div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("07 — Impact area")}</div>
                      <div class="f-sec-title">
                        {gettext("Which area does this request benefit?")}
                      </div>
                    </div>
                    <div class="imp-grid">
                      <.imp_opt
                        area="costes"
                        selected={@form_data["impact_area"] == "costes"}
                        icon="hero-arrow-trending-down"
                        label={gettext("Reduces costs")}
                        target={@myself}
                      />
                      <.imp_opt
                        area="ingresos"
                        selected={@form_data["impact_area"] == "ingresos"}
                        icon="hero-arrow-trending-up"
                        label={gettext("Increases revenue")}
                        target={@myself}
                      />
                      <.imp_opt
                        area="eficiencia"
                        selected={@form_data["impact_area"] == "eficiencia"}
                        icon="hero-bolt"
                        label={gettext("Improves efficiency")}
                        target={@myself}
                      />
                      <.imp_opt
                        area="producto"
                        selected={@form_data["impact_area"] == "producto"}
                        icon="hero-star"
                        label={gettext("Improves product / UX")}
                        target={@myself}
                      />
                      <.imp_opt
                        area="otro"
                        selected={@form_data["impact_area"] == "otro"}
                        icon="hero-ellipsis-horizontal"
                        label={gettext("Other")}
                        target={@myself}
                      />
                    </div>
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("08 — Magnitude")}</div>
                      <div class="f-sec-title">{gettext("How big is that impact?")}</div>
                    </div>
                    <div class="seg">
                      <.seg_opt
                        level="alto"
                        selected={@form_data["impact_level"] == "alto"}
                        sel_class="sel-high"
                        badge_style="background:#ffedd5;color:#9a3412"
                        label={gettext("High")}
                        sub={gettext("Strategic impact")}
                        target={@myself}
                      />
                      <.seg_opt
                        level="medio"
                        selected={@form_data["impact_level"] == "medio"}
                        sel_class="sel-med"
                        badge_style="background:#dbeafe;color:#1e40af"
                        label={gettext("Medium")}
                        sub={gettext("Notable improvement")}
                        target={@myself}
                      />
                      <.seg_opt
                        level="bajo"
                        selected={@form_data["impact_level"] == "bajo"}
                        sel_class="sel-low"
                        badge_style="background:#dcfce7;color:#166534"
                        label={gettext("Low")}
                        sub={gettext("Incremental improvement")}
                        target={@myself}
                      />
                    </div>
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("09 — Deliverable and evidence")}</div>
                      <div class="f-sec-title">{gettext("What form should the solution take?")}</div>
                      <div class="f-sec-sub">
                        {gettext(
                          "Optional — helps the PM understand the scope and technical routing."
                        )}
                      </div>
                    </div>
                    <div class="ic-grid c3" style="margin-bottom:16px">
                      <.ico_card
                        field="goal_target"
                        value="interface_view"
                        selected={@form_data["goal_target"] == "interface_view"}
                        icon="hero-window"
                        label={gettext("Interface / View")}
                        sub={gettext("Screen or UI")}
                        target={@myself}
                      />
                      <.ico_card
                        field="goal_target"
                        value="report_file"
                        selected={@form_data["goal_target"] == "report_file"}
                        icon="hero-document-text"
                        label={gettext("File / Report")}
                        sub={gettext("Downloadable document")}
                        target={@myself}
                      />
                      <.ico_card
                        field="goal_target"
                        value="alert_message"
                        selected={@form_data["goal_target"] == "alert_message"}
                        icon="hero-bell"
                        label={gettext("Alert / Message")}
                        sub={gettext("Notification or email")}
                        target={@myself}
                      />
                    </div>

                    <label
                      class="upload-zone"
                      phx-drop-target={@uploads.files.ref}
                    >
                      <.icon name="hero-cloud-arrow-up" class="up-icon size-8" />
                      <div class="upload-title">
                        {gettext("Drag files or click to upload")}
                      </div>
                      <div class="upload-text">
                        {gettext("PNG, JPG, PDF, XLSX, DOCX · max. 15 MB")}
                      </div>
                      <.live_file_input upload={@uploads.files} class="hidden" />
                    </label>

                    <div class="file-list">
                      <%= for entry <- @uploads.files.entries do %>
                        <div class="file-chip">
                          <.icon name="hero-paper-clip" class="size-4" />
                          <span>{entry.client_name}</span>
                          <button
                            type="button"
                            phx-click="cancel_upload"
                            phx-value-ref={entry.ref}
                            phx-target={@myself}
                            aria-label={gettext("Remove")}
                          >
                            <.icon name="hero-x-mark" class="size-4" />
                          </button>
                        </div>
                        <%= for err <- upload_errors(@uploads.files, entry) do %>
                          <div class="f-errmsg show">
                            <.icon name="hero-exclamation-circle" class="size-4" />
                            {upload_error_to_string(err)}
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>

                  <div class="f-divider"></div>

                  <div class="f-section" style="margin-bottom:0">
                    <div class="f-sec-head">
                      <div class="f-sec-num">{gettext("PM Summary")}</div>
                      <div class="f-sec-title">
                        {gettext("This is how it will enter the pipeline")}
                      </div>
                    </div>
                    <div class="summary-grid">
                      <.sum_card label={gettext("Request")} value={@form_data["title"]} />
                      <.sum_card label={gettext("Type")} value={kind_label(@form_data["kind"])} />
                      <.sum_card
                        label={gettext("Priority")}
                        value={priority_label(@form_data["priority"])}
                      />
                      <.sum_card
                        label={gettext("Impact area")}
                        value={impact_label(@form_data["impact_area"])}
                      />
                      <.sum_card
                        label={gettext("Level")}
                        value={level_label(@form_data["impact_level"])}
                      />
                      <.sum_card label={gettext("Initial status")} value={gettext("PM Review")} />
                    </div>
                  </div>
                </div>

                <div class="form-foot">
                  <button
                    type="button"
                    phx-click="go_step"
                    phx-value-step="2"
                    phx-target={@myself}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back")}
                  </button>
                  <button
                    type="submit"
                    class="btn btn-accent btn-sm"
                    phx-disable-with={gettext("Creating...")}
                  >
                    <.icon name="hero-check" class="size-4" /> {gettext("Create request")}
                  </button>
                </div>
              </form>
            <% end %>

            <%!-- Success --%>
            <%= if @submitted do %>
              <div class="form-step-screen active">
                <div class="success-screen">
                  <div class="success-ic"><.icon name="hero-check" class="size-8" /></div>
                  <h3>{gettext("Request created!")}</h3>
                  <p>
                    {gettext(
                      "Your request has entered the pipeline. The PM will review the details and contact you soon."
                    )}
                  </p>
                  <button
                    type="button"
                    phx-click="close_success"
                    phx-target={@myself}
                    class="btn btn-primary btn-sm"
                  >
                    {gettext("Close")}
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # === Function components ===

  attr :field, :string, required: true
  attr :value, :string, required: true
  attr :selected, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :sub, :string, default: nil
  attr :compact, :boolean, default: false
  attr :target, :any, required: true

  defp ico_card(assigns) do
    ~H"""
    <button
      type="button"
      class={["ico", @selected && "sel"]}
      style={@compact && "padding:14px 10px"}
      phx-click="pick"
      phx-value-field={@field}
      phx-value-pick={@value}
      phx-target={@target}
    >
      <div class="ico-icon"><.icon name={@icon} class="size-5" /></div>
      <div class="ico-lbl">{@label}</div>
      <div :if={@sub} class="ico-sub">{@sub}</div>
    </button>
    """
  end

  attr :p, :string, required: true
  attr :selected, :boolean, default: false
  attr :label, :string, required: true
  attr :sub, :string, required: true
  attr :target, :any, required: true

  defp prio_opt(assigns) do
    ~H"""
    <button
      type="button"
      class={["pto", @selected && "sel"]}
      data-p={@p}
      phx-click="pick_priority"
      phx-value-priority={@p}
      phx-target={@target}
    >
      <div class="pto-dot"></div>
      <div class="pto-lbl">{@label}</div>
      <div class="pto-sub">{@sub}</div>
    </button>
    """
  end

  attr :area, :string, required: true
  attr :selected, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :target, :any, required: true

  defp imp_opt(assigns) do
    ~H"""
    <button
      type="button"
      class={["imp-opt", @selected && "sel"]}
      data-imp={@area}
      phx-click="pick_impact"
      phx-value-area={@area}
      phx-target={@target}
    >
      <.icon name={@icon} class={"imp-icon size-6 " <> @area} />
      <div class="imp-lbl">{@label}</div>
    </button>
    """
  end

  attr :level, :string, required: true
  attr :selected, :boolean, default: false
  attr :sel_class, :string, required: true
  attr :badge_style, :string, required: true
  attr :label, :string, required: true
  attr :sub, :string, required: true
  attr :target, :any, required: true

  defp seg_opt(assigns) do
    ~H"""
    <button
      type="button"
      class={["seg-opt", @selected && @sel_class]}
      data-nv={@level}
      phx-click="pick_level"
      phx-value-level={@level}
      phx-target={@target}
    >
      <span class="seg-badge" style={@badge_style}>{@label}</span>
      <div class="seg-lbl">{@label}</div>
      <div class="seg-sub">{@sub}</div>
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp sum_card(assigns) do
    assigns = assign(assigns, :value, blank_value(assigns.value))

    ~H"""
    <div class="sum-card">
      <div class="sum-label">{@label}</div>
      <div class="sum-value">{@value}</div>
    </div>
    """
  end

  defp blank_value(nil), do: "—"
  defp blank_value(""), do: "—"
  defp blank_value(v), do: v
end
