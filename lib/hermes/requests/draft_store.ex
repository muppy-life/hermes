defmodule Hermes.Requests.DraftStore do
  @moduledoc """
  ETS-based storage for request creation drafts.
  Stores form data temporarily to prevent data loss on page reloads.
  """

  use GenServer

  @table_name :request_drafts

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get a draft for the given user ID.
  Returns nil if no draft exists.
  """
  def get(user_id) do
    case :ets.lookup(@table_name, user_id) do
      [{^user_id, draft}] -> draft
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Save a draft for the given user ID.
  """
  def save(user_id, step, form_data) do
    draft = %{
      step: step,
      form_data: form_data,
      updated_at: DateTime.utc_now()
    }

    :ets.insert(@table_name, {user_id, draft})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Delete a draft for the given user ID.
  """
  def delete(user_id) do
    :ets.delete(@table_name, user_id)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # Server Callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    {:ok, table}
  end
end
