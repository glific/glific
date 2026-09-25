defmodule GlificWeb.API.V1.WebChannelMediaController do
  @moduledoc """
  Signs a short-lived direct-to-GCS upload URL for the web channel's browser contacts.

  Sits behind `GlificWeb.Plugs.WebChannelAuth`, which authenticates the request by the same
  `GlificWeb.WebChannel.Token` the socket uses and resolves `org_id` from it — never from the
  request body. The browser then `PUT`s the file straight into the organization's own bucket
  with the returned URL; no file byte passes through Glific. `RoomChannel.handle_in/3`
  re-verifies the uploaded object's real size and content type before persisting it as a
  message — the declared `size` here only bounds the honest case.
  """

  use GlificWeb, :controller

  alias Glific.{GCS, GCS.SignedUrl, Messages, Providers.Web.Upload}
  alias Plug.Conn

  @allowed_types ~w(image audio video document)

  # Where every other Glific object already lives (waffle's default `storage_dir`), so web media
  # inherits the bucket's existing lifecycle rules and access grants.
  @object_prefix "uploads"
  @expires_in_seconds 300

  @doc """
  Sign a PUT URL for the authenticated web-channel contact's declared upload.
  """
  @spec upload_url(Conn.t(), map()) :: Conn.t()
  def upload_url(conn, %{"type" => type, "content_type" => content_type, "size" => size})
      when type in @allowed_types do
    organization_id = conn.assigns.web_channel_organization_id

    with :ok <- validate_content_type(type, content_type),
         :ok <- validate_size(type, size),
         {:ok, extension} <- Upload.extension_for(content_type),
         {:ok, bucket} <- fetch_bucket(organization_id),
         object_name = "#{@object_prefix}/#{Ecto.UUID.generate()}.#{extension}",
         {:ok, %{upload_url: signed_url, url: url}} <-
           SignedUrl.signed_put_url(
             organization_id,
             bucket,
             object_name,
             content_type,
             @expires_in_seconds
           ) do
      json(conn, %{
        data: %{
          upload_url: signed_url,
          url: url,
          content_type: content_type,
          expires_in: @expires_in_seconds
        }
      })
    else
      {:error, :gcs_not_configured} ->
        Glific.log_error(
          "Web channel upload-url is unavailable for organization #{organization_id}: " <>
            "no Google Cloud Storage credential. Configure GCS before enabling the web " <>
            "channel, or every attachment will fail."
        )

        typed_error(conn, 503, "storage_unavailable", "Attachments are unavailable")

      {:error, :signing_failed} ->
        Glific.log_error(
          "Web channel upload-url signing failed for organization #{organization_id}"
        )

        typed_error(conn, 500, "signing_failed", "Could not prepare an upload URL")

      {:error, status, code, message} ->
        typed_error(conn, status, code, message)

      {:error, reason} when is_binary(reason) ->
        typed_error(conn, 422, "upload_failed", reason)
    end
  end

  def upload_url(conn, %{"type" => type}) when type not in @allowed_types,
    do: typed_error(conn, 415, "unsupported_type", "Unsupported media type")

  def upload_url(conn, _params),
    do: typed_error(conn, 422, "upload_failed", "A type, content_type and size are required")

  @spec fetch_bucket(non_neg_integer()) :: {:ok, String.t()} | {:error, :gcs_not_configured}
  defp fetch_bucket(organization_id) do
    case GCS.bucket_name(organization_id) do
      nil -> {:error, :gcs_not_configured}
      bucket -> {:ok, bucket}
    end
  end

  @spec validate_content_type(String.t(), term()) :: :ok | {:error, 415, String.t(), String.t()}
  defp validate_content_type(type, content_type) do
    if Messages.valid_media_content_type?(type, content_type),
      do: :ok,
      else: {:error, 415, "unsupported_type", "Unsupported media type"}
  end

  @spec validate_size(String.t(), term()) :: :ok | {:error, 413 | 422, String.t(), String.t()}
  defp validate_size(_type, size) when not (is_integer(size) and size > 0),
    do: {:error, 422, "invalid_size", "size must be a positive integer, in bytes"}

  defp validate_size(type, size) do
    limit = Messages.media_size_limit(type)
    size_in_kb = size / 1024

    if limit && size_in_kb <= limit,
      do: :ok,
      else: {:error, 413, "file_too_large", "Maximum size limit is #{limit}KB"}
  end

  @spec typed_error(Conn.t(), non_neg_integer(), String.t(), String.t()) :: Conn.t()
  defp typed_error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{status: status, code: code, message: message}})
  end
end
