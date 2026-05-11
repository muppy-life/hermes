defmodule HermesWeb.RequestLive.UploadErrors do
  @moduledoc """
  Formats image-upload errors into user-facing flash messages.
  """

  use Gettext, backend: HermesWeb.Gettext

  require Logger

  def format(errors) do
    count = length(errors)
    {:error, first_reason} = hd(errors)
    detail = detail_for(first_reason)

    if count > 1 do
      gettext("%{count} images failed to upload. First error: %{detail}",
        count: count,
        detail: detail
      )
    else
      gettext("Image upload failed: %{detail}", detail: detail)
    end
  end

  def format_with_prefix(prefix, errors) do
    "#{prefix}: #{format(errors)}"
  end

  defp detail_for({:http_error, status, %{body: body}}) when is_binary(body) do
    "S3 #{status}: #{extract_s3_message(body)}"
  end

  defp detail_for(%Ecto.Changeset{} = cs) do
    Logger.error("Image upload changeset error: #{inspect(cs.errors)}")
    gettext("validation error")
  end

  defp detail_for(other) do
    Logger.error("Image upload unexpected error: #{inspect(other)}")
    gettext("unexpected error")
  end

  defp extract_s3_message(body) do
    case Regex.run(~r{<Message>([^<]+)</Message>}, body) do
      [_, msg] -> msg
      _ -> gettext("unknown error")
    end
  end
end
