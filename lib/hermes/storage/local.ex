defmodule Hermes.Storage.Local do
  @moduledoc """
  Local filesystem storage adapter for dev/test. Saves files to priv/static/uploads.
  """

  @uploads_dir "priv/static/uploads"

  def upload(key, binary, _content_type) do
    path = local_path(key)
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, binary) do
      :ok -> {:ok, key}
      err -> err
    end
  end

  def delete(key) do
    case File.rm(local_path(key)) do
      :ok -> {:ok, key}
      {:error, :enoent} -> {:ok, key}
      err -> err
    end
  end

  def public_url(key), do: "/uploads/#{key}"

  defp local_path(key), do: Path.join(@uploads_dir, key)
end
