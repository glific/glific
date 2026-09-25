defmodule Glific.GCS.ObjectMetadata do
  @moduledoc """
  Reads a GCS object's real size and content type without downloading it — the authoritative
  check run before persisting a web-channel media message, since the `size` declared when the
  upload URL was signed only bounds the honest case
  (`plans/web-channel-presigned-uploads.md` §3).

  Reads through a short-lived signed HEAD rather than the JSON API. An unauthenticated JSON read
  works only while the bucket is publicly readable, which is true of Glific's buckets today but
  is exactly what #5715 removes; and authenticating it with `Partners.get_goth_token/2` would put
  an OAuth round trip (and, in tests, a real network call) on the path of every media message.
  Signing is local, needs no token, and works on a private bucket.
  """

  alias Glific.GCS.SignedUrl

  require Logger

  @expires_in_seconds 60

  @doc """
  Fetch `object_name`'s size in bytes and content type from `bucket`, as `organization_id`.
  """
  @spec fetch(non_neg_integer(), String.t(), String.t()) ::
          {:ok, %{size: non_neg_integer(), content_type: String.t()}} | {:error, term()}
  def fetch(organization_id, bucket, object_name) do
    with {:ok, url} <-
           SignedUrl.signed_head_url(organization_id, bucket, object_name, @expires_in_seconds),
         {:ok, %Tesla.Env{status: 200} = env} <- Tesla.head(url) do
      parse(env)
    else
      {:ok, %Tesla.Env{status: status}} ->
        log_failure(organization_id, bucket, object_name, "HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        log_failure(organization_id, bucket, object_name, Glific.SafeLog.safe_inspect(reason))
        {:error, reason}
    end
  end

  # Without this the caller cannot tell a missing object from a permissions failure: every
  # outcome collapses to one rejected message and no trace of why it was rejected.
  @spec log_failure(non_neg_integer(), String.t(), String.t(), String.t()) :: :ok
  defp log_failure(organization_id, bucket, object_name, reason) do
    Logger.error(
      "Could not read web channel media metadata for organization #{organization_id}: " <>
        "#{reason} for gs://#{bucket}/#{object_name}"
    )

    :ok
  end

  @spec parse(Tesla.Env.t()) :: {:ok, map()} | {:error, :invalid_response}
  defp parse(env) do
    with size when is_binary(size) <- Tesla.get_header(env, "content-length"),
         {size_bytes, ""} <- Integer.parse(size) do
      {:ok, %{size: size_bytes, content_type: Tesla.get_header(env, "content-type")}}
    else
      _ -> {:error, :invalid_response}
    end
  end
end
