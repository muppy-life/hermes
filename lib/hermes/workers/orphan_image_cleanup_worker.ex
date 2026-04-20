defmodule Hermes.Workers.OrphanImageCleanupWorker do
  @moduledoc """
  Periodically removes uploaded image files that have no matching DB record.
  Only runs when using the local storage adapter (dev). In production, S3
  orphans are rare (crash between upload and DB insert) and not worth the
  list-objects overhead.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query, warn: false

  require Logger

  @uploads_base "priv/static/uploads"

  @impl Oban.Worker
  def perform(_job) do
    if local_adapter?() do
      uploads_dir = Path.join([@uploads_base, to_string(env()), "requests"])

      case File.ls(uploads_dir) do
        {:error, :enoent} ->
          :ok

        {:ok, request_dirs} ->
          Enum.each(request_dirs, &cleanup_request_dir(uploads_dir, &1))
          :ok
      end
    else
      :ok
    end
  end

  defp cleanup_request_dir(uploads_dir, request_id_str) do
    dir = Path.join(uploads_dir, request_id_str)

    case File.ls(dir) do
      {:error, _} ->
        :ok

      {:ok, filenames} ->
        Enum.each(filenames, &maybe_delete_orphan(dir, request_id_str, &1))
        File.rmdir(dir)
    end
  end

  defp maybe_delete_orphan(dir, request_id_str, filename) do
    key = "hermes/#{env()}/requests/#{request_id_str}/#{filename}"

    unless Hermes.Repo.exists?(from(i in Hermes.Requests.RequestImage, where: i.key == ^key)) do
      Logger.info("Removing orphan image file: #{key}")
      File.rm(Path.join(dir, filename))
    end
  end

  defp env, do: Application.get_env(:hermes, :env, :prod)

  defp local_adapter? do
    Application.get_env(:hermes, :storage_adapter) == Hermes.Storage.Local
  end
end
