defmodule Hermes.Storage.S3 do
  @moduledoc """
  AWS S3 storage adapter.
  """

  @signed_url_expires 3600

  def upload(key, binary, content_type) do
    bucket = config(:bucket)

    ExAws.S3.put_object(bucket, key, binary, content_type: content_type)
    |> ExAws.request(ex_aws_opts())
  end

  def delete(key) do
    bucket = config(:bucket)

    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request(ex_aws_opts())
  end

  def public_url(key) do
    bucket = config(:bucket)
    region = config(:region)

    {:ok, url} =
      ExAws.S3.presigned_url(ExAws.Config.new(:s3, region: region), :get, bucket, key,
        expires_in: @signed_url_expires
      )

    url
  end

  defp config(key), do: Application.fetch_env!(:hermes, :s3) |> Keyword.fetch!(key)
  defp ex_aws_opts, do: [region: config(:region)]
end
