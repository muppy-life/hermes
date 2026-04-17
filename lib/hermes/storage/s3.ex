defmodule Hermes.Storage.S3 do
  @moduledoc """
  AWS S3 storage adapter.
  """

  def upload(key, binary, content_type) do
    bucket = config(:bucket)

    ExAws.S3.put_object(bucket, key, binary,
      content_type: content_type,
      acl: :public_read
    )
    |> ExAws.request(ex_aws_opts())
  end

  def delete(key) do
    bucket = config(:bucket)

    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request(ex_aws_opts())
  end

  def public_url(key) do
    host = config(:host)
    bucket = config(:bucket)
    "https://#{bucket}.#{host}/#{key}"
  end

  defp config(key), do: Application.fetch_env!(:hermes, :s3) |> Keyword.fetch!(key)
  defp ex_aws_opts, do: [region: config(:region)]
end
