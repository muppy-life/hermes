defmodule Hermes.Storage do
  @moduledoc """
  S3-backed storage for request image uploads.
  Delegates to a local adapter in dev/test (configure via :storage_adapter).
  """

  def upload(key, binary, content_type), do: adapter().upload(key, binary, content_type)
  def delete(key), do: adapter().delete(key)
  def public_url(key), do: adapter().public_url(key)

  defp adapter do
    Application.get_env(:hermes, :storage_adapter, Hermes.Storage.S3)
  end
end
