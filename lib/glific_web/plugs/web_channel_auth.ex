defmodule GlificWeb.Plugs.WebChannelAuth do
  @moduledoc """
  Authenticates a web channel media request by its `Authorization: Bearer <token>` header and
  gates it on the feature flag — the two checks every other web channel surface makes, behind
  one plug so a route added to this pipeline inherits both rather than re-implementing them.
  """
  use GlificWeb, :controller

  alias Glific.Repo
  alias GlificWeb.WebChannel.{Flag, Token}
  alias Plug.Conn

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(conn, _opts) do
    with ["Bearer " <> token] <- Conn.get_req_header(conn, "authorization"),
         {:ok, payload} <- Token.verify_contact_token(token) do
      authorize_flag(conn, payload)
    else
      _ -> unauthorized(conn)
    end
  end

  @spec authorize_flag(Conn.t(), Token.payload()) :: Conn.t()
  defp authorize_flag(conn, payload) do
    if Flag.enabled?(payload.org_id) do
      Repo.put_process_state(payload.org_id)

      conn
      |> assign(:web_channel_contact_id, payload.contact_id)
      |> assign(:web_channel_organization_id, payload.org_id)
    else
      # Matches the auth controller's response for a disabled org. Carries `code` like the
      # upload controller's errors do, since the widget keys its copy on that and not on prose.
      conn
      |> put_status(404)
      |> json(%{
        error: %{
          status: 404,
          code: "web_channel_disabled",
          message: "Web channel is not enabled for this organization"
        }
      })
      |> halt()
    end
  end

  @spec unauthorized(Conn.t()) :: Conn.t()
  defp unauthorized(conn) do
    conn
    |> put_status(401)
    |> json(%{error: %{status: 401, code: "unauthorized", message: "Unauthorized"}})
    |> halt()
  end
end
