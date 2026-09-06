defmodule GlificWeb.API.V1.WebChannelMediaController do
  @moduledoc """
  Media upload for the web channel's browser contacts.

  Sits behind `GlificWeb.Plugs.WebChannelAuth`, which authenticates the request by the same
  `GlificWeb.WebChannel.Token` the socket uses and resolves `org_id` from it — never from the
  request body. Accepts a multipart file, uploads it via `Glific.Providers.Web.Upload`, and
  returns the hosted URL the browser then sends over the socket as a media message.
  """

  use GlificWeb, :controller

  alias Glific.{Messages, Providers.Web.Upload}
  alias Plug.Conn

  @allowed_types ~w(image audio video document)

  @doc """
  Upload a media file for the authenticated web-channel contact and return its hosted URL.
  """
  @spec upload(Conn.t(), map()) :: Conn.t()
  def upload(conn, %{"media" => %Plug.Upload{} = media, "type" => type})
      when type in @allowed_types do
    organization_id = conn.assigns.web_channel_organization_id

    with :ok <- validate_content_type(type, media.content_type),
         :ok <- validate_size(type, media.path) do
      case Upload.upload_file(organization_id, media.path, media.content_type) do
        {:ok, %{url: url, content_type: content_type}} ->
          json(conn, %{data: %{url: url, content_type: content_type}})

        {:error, :storage_unavailable} ->
          # A misconfiguration rather than a bad request, and one nothing can catch at
          # enablement time — the feature flag has no application-level hook (#5711).
          Glific.log_error(
            "Web channel media upload is unavailable for organization #{organization_id}: " <>
              "no Google Cloud Storage credential. Configure GCS before enabling the web " <>
              "channel, or every attachment will fail."
          )

          typed_error(conn, 503, "storage_unavailable", "Attachments are unavailable")

        {:error, reason} ->
          typed_error(conn, 422, "upload_failed", to_string(reason))
      end
    else
      {:error, status, code, message} -> typed_error(conn, status, code, message)
    end
  end

  def upload(conn, %{"type" => type}) when type not in @allowed_types,
    do: typed_error(conn, 415, "unsupported_type", "Unsupported media type")

  def upload(conn, _params),
    do: typed_error(conn, 422, "upload_failed", "A media file and type are required")

  @spec validate_content_type(String.t(), String.t() | nil) ::
          :ok | {:error, 415, String.t(), String.t()}
  defp validate_content_type(type, content_type) do
    if Messages.valid_media_content_type?(type, content_type),
      do: :ok,
      else: {:error, 415, "unsupported_type", "Unsupported media type"}
  end

  @spec validate_size(String.t(), String.t()) :: :ok | {:error, 413, String.t(), String.t()}
  defp validate_size(type, path) do
    # From the temp file on disk, never a client-supplied header — a client can claim any size.
    size_in_kb = File.stat!(path).size / 1024
    limit = Messages.media_size_limit(type)

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
