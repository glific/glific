defmodule Glific.GCS.ObjectMetadata do
  @moduledoc """
  Reads a GCS object's real size and content type without downloading it — the authoritative
  check run before persisting a web-channel media message, since the `size` declared when the
  upload URL was signed only bounds the honest case
  (`plans/web-channel-presigned-uploads.md` §3). The object metadata endpoint grants the same
  unauthenticated read access as the object's own hosted URL, so this never needs a token.
  """

  @endpoint "https://storage.googleapis.com/storage/v1/b"

  @doc """
  Fetch `object_name`'s size (bytes) and content type from `bucket`.
  """
  @spec fetch(String.t(), String.t()) ::
          {:ok, %{size: non_neg_integer(), content_type: String.t()}} | {:error, term()}
  def fetch(bucket, object_name) do
    url = "#{@endpoint}/#{bucket}/o/#{URI.encode(object_name, &URI.char_unreserved?/1)}"

    Tesla.client([Tesla.Middleware.JSON])
    |> Tesla.get(url)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} -> parse(body)
      {:ok, %Tesla.Env{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse(map()) :: {:ok, map()} | {:error, :invalid_response}
  defp parse(%{"size" => size, "contentType" => content_type}) when is_binary(size) do
    case Integer.parse(size) do
      {size_bytes, ""} -> {:ok, %{size: size_bytes, content_type: content_type}}
      _ -> {:error, :invalid_response}
    end
  end

  defp parse(_body), do: {:error, :invalid_response}
end
