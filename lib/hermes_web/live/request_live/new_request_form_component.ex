defmodule HermesWeb.RequestLive.NewRequestFormComponent do
  use HermesWeb, :live_component

  require Logger

  alias Hermes.Accounts
  alias Hermes.Requests

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:current_step, fn -> 1 end)
     |> assign_new(:form_data, fn -> default_form_data() end)
     |> assign_new(:submitted, fn -> false end)}
  end

  defp default_form_data do
    %{
      "title" => "",
      "description" => "",
      "priority" => 2,
      "deadline" => ""
    }
  end

  @impl true
  def handle_event("select_priority", %{"priority" => priority}, socket) do
    priority_int =
      case priority do
        "3" -> 3
        "2" -> 2
        "1" -> 1
        _ -> 2
      end

    {:noreply,
     assign(socket, :form_data, Map.put(socket.assigns.form_data, "priority", priority_int))}
  end

  def handle_event("go_step", %{"step" => step, "request" => params}, socket) do
    form_data = Map.merge(socket.assigns.form_data, params)

    case validate_step(socket.assigns.current_step, form_data) do
      :ok ->
        {:noreply,
         socket
         |> assign(:form_data, form_data)
         |> assign(:current_step, String.to_integer(step))}

      {:error, msg} ->
        send(self(), {:new_request_flash, :error, msg})

        {:noreply, assign(socket, :form_data, form_data)}
    end
  end

  def handle_event("go_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, :current_step, String.to_integer(step))}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), :hide_new_request)
    {:noreply, socket}
  end

  def handle_event("submit", %{"request" => params}, socket) do
    do_submit(Map.merge(socket.assigns.form_data, params), socket)
  end

  def handle_event("submit", _params, socket) do
    do_submit(socket.assigns.form_data, socket)
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
      |> Map.put("created_by_id", current_user.id)
      |> Map.put("requesting_team_id", current_user.team_id)
      |> Map.put("assigned_to_team_id", dev_team && dev_team.id)
      |> Map.put("status", "new")
      |> normalize_deadline()

    case Requests.create_request(final_params, current_user.id) do
      {:ok, request} ->
        send(self(), {:new_request_created, request})

        {:noreply,
         socket
         |> assign(:submitted, true)
         |> assign(:current_step, 4)}

      {:error, %Ecto.Changeset{} = changeset} ->
        send(self(), {:new_request_flash, :error, format_errors(changeset)})

        {:noreply, assign(socket, :current_step, 1)}
    end
  end

  defp normalize_deadline(%{"deadline" => ""} = params), do: Map.delete(params, "deadline")
  defp normalize_deadline(%{"deadline" => nil} = params), do: Map.delete(params, "deadline")
  defp normalize_deadline(params), do: params

  defp validate_step(1, form_data) do
    cond do
      blank?(form_data["title"]) -> {:error, gettext("Title is required")}
      blank?(form_data["description"]) -> {:error, gettext("Description is required")}
      true -> :ok
    end
  end

  defp validate_step(_, _), do: :ok

  defp blank?(nil), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp priority_label(1), do: gettext("Low")
  defp priority_label(2), do: gettext("Normal")
  defp priority_label(3), do: gettext("Important")
  defp priority_label(_), do: gettext("Normal")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="new-request-overlay">
      <div id="form-overlay" class="open">
        <div id="form-inner">
          <aside id="form-sidebar">
            <div class="fbrand">{gettext("New request")}</div>

            <div class={["fstep", @current_step >= 1 && "active", @current_step > 1 && "done"]}>
              <div class="fstep-n"><span class="fstep-num">1</span></div>
              <div class="fstep-l">{gettext("Information")}</div>
            </div>
            <div class={["fstep", @current_step >= 2 && "active", @current_step > 2 && "done"]}>
              <div class="fstep-n"><span class="fstep-num">2</span></div>
              <div class="fstep-l">{gettext("Details")}</div>
            </div>
            <div class={["fstep", @current_step >= 3 && "active", @current_step > 3 && "done"]}>
              <div class="fstep-n"><span class="fstep-num">3</span></div>
              <div class="fstep-l">{gettext("Review")}</div>
            </div>

            <div style="flex:1"></div>

            <button type="button" phx-click="cancel" phx-target={@myself} class="fcancel">
              {gettext("Cancel")}
            </button>
          </aside>

          <div id="form-content">
            <%= if @current_step == 1 do %>
              <form
                phx-submit="go_step"
                phx-target={@myself}
                id="step-1-form"
                class="form-step-screen"
              >
                <input type="hidden" name="step" value="2" />
                <div class="form-scroll">
                  <div class="form-h">{gettext("Basic information")}</div>
                  <div class="form-sub">{gettext("Tell us what you need")}</div>

                  <div class="form-field">
                    <label class="form-label">
                      {gettext("Title")}<span class="req">*</span>
                    </label>
                    <input
                      type="text"
                      name="request[title]"
                      class="form-input"
                      placeholder={gettext("e.g. Redesign pricing landing")}
                      value={@form_data["title"]}
                      required
                    />
                  </div>

                  <div class="form-field">
                    <label class="form-label">
                      {gettext("Description")}<span class="req">*</span>
                    </label>
                    <textarea
                      name="request[description]"
                      class="form-textarea"
                      placeholder={gettext("Describe context, objective and expected outcome")}
                      required
                    ><%= @form_data["description"] %></textarea>
                  </div>

                  <div class="form-field">
                    <label class="form-label">{gettext("Requester")}</label>
                    <div class="form-static">{@current_user.email}</div>
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
                    {gettext("Continue")} <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
              </form>
            <% end %>

            <%= if @current_step == 2 do %>
              <form
                phx-submit="go_step"
                phx-target={@myself}
                id="step-2-form"
                class="form-step-screen"
              >
                <input type="hidden" name="step" value="3" />
                <div class="form-scroll">
                  <div class="form-h">{gettext("Details and priority")}</div>
                  <div class="form-sub">{gettext("Help us prioritise")}</div>

                  <div class="form-field">
                    <label class="form-label">
                      {gettext("Priority")}<span class="req">*</span>
                    </label>
                    <input type="hidden" name="request[priority]" value={@form_data["priority"]} />
                    <div class="prio-grid">
                      <button
                        type="button"
                        class={["prio-opt", @form_data["priority"] == 3 && "selected"]}
                        phx-click="select_priority"
                        phx-value-priority="3"
                        phx-target={@myself}
                      >
                        <.icon name="hero-fire" class="size-5" />
                        <div class="prio-opt-l">{gettext("Important")}</div>
                      </button>
                      <button
                        type="button"
                        class={["prio-opt", @form_data["priority"] == 2 && "selected"]}
                        phx-click="select_priority"
                        phx-value-priority="2"
                        phx-target={@myself}
                      >
                        <.icon name="hero-equals" class="size-5" />
                        <div class="prio-opt-l">{gettext("Normal")}</div>
                      </button>
                      <button
                        type="button"
                        class={["prio-opt", @form_data["priority"] == 1 && "selected"]}
                        phx-click="select_priority"
                        phx-value-priority="1"
                        phx-target={@myself}
                      >
                        <.icon name="hero-arrow-down" class="size-5" />
                        <div class="prio-opt-l">{gettext("Low")}</div>
                      </button>
                    </div>
                  </div>

                  <div class="form-field">
                    <label class="form-label">{gettext("Deadline")}</label>
                    <input
                      type="date"
                      name="request[deadline]"
                      class="form-input"
                      value={@form_data["deadline"]}
                    />
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
                    {gettext("Continue")} <.icon name="hero-arrow-right" class="size-4" />
                  </button>
                </div>
              </form>
            <% end %>

            <%= if @current_step == 3 do %>
              <form phx-submit="submit" phx-target={@myself} id="step-3-form" class="form-step-screen">
                <div class="form-scroll">
                  <div class="form-h">{gettext("Review")}</div>
                  <div class="form-sub">{gettext("Verify before submitting")}</div>

                  <div class="review-block">
                    <div class="review-l">{gettext("Title")}</div>
                    <div class="review-v">{@form_data["title"]}</div>
                  </div>

                  <div class="review-block">
                    <div class="review-l">{gettext("Description")}</div>
                    <div class="review-v whitespace-pre-wrap">{@form_data["description"]}</div>
                  </div>

                  <div class="review-block">
                    <div class="review-l">{gettext("Requester")}</div>
                    <div class="review-v">{@current_user.email}</div>
                  </div>

                  <div class="review-block">
                    <div class="review-l">{gettext("Priority")}</div>
                    <div class="review-v">{priority_label(@form_data["priority"])}</div>
                  </div>

                  <%= if @form_data["deadline"] && @form_data["deadline"] != "" do %>
                    <div class="review-block">
                      <div class="review-l">{gettext("Deadline")}</div>
                      <div class="review-v">{@form_data["deadline"]}</div>
                    </div>
                  <% end %>
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
                    class="btn btn-primary btn-sm"
                    phx-disable-with={gettext("Submitting...")}
                  >
                    <.icon name="hero-paper-airplane" class="size-4" /> {gettext("Submit request")}
                  </button>
                </div>
              </form>
            <% end %>

            <%= if @submitted do %>
              <div class="form-step-screen">
                <div class="success-screen">
                  <div class="success-ic"><.icon name="hero-check" class="size-8" /></div>
                  <h3>{gettext("Request submitted")}</h3>
                  <p>{gettext("Your request has been recorded successfully")}</p>
                  <button
                    type="button"
                    phx-click="close_success"
                    phx-target={@myself}
                    class="btn btn-primary btn-sm mt-4"
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
end
