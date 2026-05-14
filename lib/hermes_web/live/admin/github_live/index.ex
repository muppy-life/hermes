defmodule HermesWeb.Admin.GithubLive.Index do
  @moduledoc """
  Admin page for managing GitHub Projects v2 status mappings.

  Each row represents one option of the project's Status field paired with
  the Hermes request status it should drive. The "Sync from GitHub" button
  pulls the current option list so admins only need to assign Hermes
  statuses for new options.
  """

  use HermesWeb, :live_view

  alias Hermes.Requests
  alias Hermes.Requests.GitHubStatusMapping

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GitHub Status Mappings")
     |> assign(:hermes_statuses, GitHubStatusMapping.hermes_statuses())
     |> assign(:pending_options, [])
     |> assign(:sync_error, nil)
     |> load_mappings()}
  end

  @impl true
  def handle_event("sync", _params, socket) do
    case Requests.sync_status_mappings_from_github() do
      {:ok, %{existing: existing, pending_options: pending}} ->
        {:noreply,
         socket
         |> assign(:mappings, existing)
         |> assign(:pending_options, pending)
         |> assign(:sync_error, nil)
         |> put_flash(
           :info,
           "Synced #{length(existing)} existing, #{length(pending)} new options pending"
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:sync_error, inspect(reason))
         |> put_flash(:error, "Sync failed")}
    end
  end

  def handle_event("create_mapping", %{"mapping" => params}, socket) do
    case Requests.upsert_status_mapping(params) do
      {:ok, _mapping} ->
        {:noreply,
         socket
         |> assign(:pending_options, drop_option(socket.assigns.pending_options, params))
         |> load_mappings()
         |> put_flash(:info, "Mapping saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Save failed: #{format_errors(changeset)}")}
    end
  end

  def handle_event("update_mapping", %{"mapping_id" => id, "hermes_status" => status}, socket) do
    mapping = Requests.get_status_mapping!(id)

    case Requests.upsert_status_mapping(%{
           "github_option_id" => mapping.github_option_id,
           "github_option_name" => mapping.github_option_name,
           "hermes_status" => status
         }) do
      {:ok, _} ->
        {:noreply, put_flash(load_mappings(socket), :info, "Mapping updated")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Save failed: #{format_errors(changeset)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    mapping = Requests.get_status_mapping!(id)
    {:ok, _} = Requests.delete_status_mapping(mapping)
    {:noreply, load_mappings(socket)}
  end

  defp load_mappings(socket) do
    assign(socket, :mappings, Requests.list_status_mappings())
  end

  defp drop_option(options, %{"github_option_id" => id}) do
    Enum.reject(options, &(&1.id == id))
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end
end
