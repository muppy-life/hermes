defmodule Hermes.Storage.S3 do
  @moduledoc """
  AWS S3 storage adapter.
  """

  require Logger

  @signed_url_expires 3600

  def upload(key, binary, content_type) do
    bucket = config(:bucket)
    size = byte_size(binary)

    Logger.info(
      "S3.upload start bucket=#{bucket} key=#{key} content_type=#{inspect(content_type)} size=#{size}"
    )

    result =
      ExAws.S3.put_object(bucket, key, binary, content_type: content_type, acl: :private)
      |> ExAws.request(ex_aws_opts())

    case result do
      {:ok, _} ->
        Logger.info("S3.upload ok key=#{key}")

      {:error, reason} ->
        Logger.error("S3.upload failed bucket=#{bucket} key=#{key} reason=#{inspect(reason)}")
    end

    result
  end

  def delete(key) do
    bucket = config(:bucket)

    Logger.info("S3.delete start bucket=#{bucket} key=#{key}")

    result =
      ExAws.S3.delete_object(bucket, key)
      |> ExAws.request(ex_aws_opts())

    case result do
      {:ok, _} ->
        Logger.info("S3.delete ok key=#{key}")

      {:error, reason} ->
        Logger.error("S3.delete failed bucket=#{bucket} key=#{key} reason=#{inspect(reason)}")
    end

    result
  end

  def public_url(key) do
    bucket = config(:bucket)

    {:ok, url} =
      ExAws.S3.presigned_url(ExAws.Config.new(:s3, ex_aws_opts()), :get, bucket, key,
        expires_in: @signed_url_expires
      )

    url
  end

  defp config(key), do: Application.fetch_env!(:hermes, :s3) |> Keyword.fetch!(key)

  defp ex_aws_opts do
    %URI{scheme: scheme, host: host_only, port: port} = parse_host(config(:host))

    [
      region: config(:region),
      scheme: "#{scheme}://",
      host: host_only,
      access_key_id: config(:access_key_id),
      secret_access_key: config(:secret_access_key)
    ]
    |> maybe_put(:port, port)
  end

  defp parse_host(host) do
    uri = URI.parse(host)

    if uri.scheme && uri.host do
      uri
    else
      %URI{scheme: "https", host: host, port: nil}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
