defmodule GlificWeb.API.V1.WebChannelMediaController do
  @moduledoc """
  Media upload for the web channel's browser contacts.

  A web-channel end user is authenticated by a `GlificWeb.WebChannel.Token` (the same token
  it uses to open the socket), not a staff Pow session — so it cannot use the `:staff`-gated
  `uploadMedia` GraphQL mutation. This endpoint accepts a multipart file, uploads it via
  `Glific.Providers.Web.Upload` (GCS, or a dev-only local-disk fallback), and returns the
  hosted URL the browser then sends over the socket as a media message.

  The `org_id` comes from the verified token — the authoritative tenant source — never from
  the request body.
  """

  use GlificWeb, :controller

  alias Glific.Providers.Web.Upload
  alias Glific.Repo
  alias GlificWeb.WebChannel.Token
  alias Plug.Conn

  @doc """
  Upload a media file for the authenticated web-channel contact and return its hosted URL.
  """
  @spec upload(Conn.t(), map()) :: Conn.t()
  def upload(conn, %{"media" => %Plug.Upload{} = media, "extension" => extension}) do
    case authenticate(conn) do
      {:ok, %{org_id: org_id}} ->
        Repo.put_process_state(org_id)

        case Upload.upload_file(org_id, media.path, extension, media.content_type) do
          {:ok, %{url: url, content_type: content_type}} ->
            json(conn, %{data: %{url: url, content_type: content_type}})

          {:error, reason} ->
            conn |> put_status(422) |> json(%{error: %{message: to_string(reason)}})
        end

      {:error, :unauthorized} ->
        conn |> put_status(401) |> json(%{error: %{message: "Unauthorized"}})
    end
  end

  def upload(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: %{message: "A media file and extension are required"}})
  end

  @spec authenticate(Conn.t()) ::
          {:ok, %{contact_id: non_neg_integer(), org_id: non_neg_integer()}}
          | {:error, :unauthorized}
  defp authenticate(conn) do
    with ["Bearer " <> token] <- Conn.get_req_header(conn, "authorization"),
         {:ok, payload} <- Token.verify_contact_token(token) do
      {:ok, payload}
    else
      _ -> {:error, :unauthorized}
    end
  end
end
