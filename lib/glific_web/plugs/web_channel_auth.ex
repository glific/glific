defmodule GlificWeb.Plugs.WebChannelAuth do
  @moduledoc """
  Authenticates a web channel media request by its `Authorization: Bearer <token>` header,
  verified against the secret of the organization the request host belongs to, and
  gates it on the feature flag — the two checks every other web channel surface makes, behind
  one plug so a route added to this pipeline inherits both rather than re-implementing them.
  """
  use GlificWeb, :controller

  alias Glific.{Contacts, Repo}
  alias GlificWeb.WebChannel.{Flag, Token}
  alias Plug.Conn

  @doc false
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), Plug.opts()) :: Conn.t()
  def call(conn, _opts) do
    with ["Bearer " <> token] <- Conn.get_req_header(conn, "authorization"),
         organization_id when is_integer(organization_id) <- conn.assigns[:organization_id],
         {:ok, claims} <- Token.verify(organization_id, token) do
      authorize_flag(conn, organization_id, claims)
    else
      _ -> unauthorized(conn)
    end
  end

  @spec authorize_flag(Conn.t(), non_neg_integer(), Token.claims()) :: Conn.t()
  defp authorize_flag(conn, organization_id, claims) do
    if Flag.web_channel_enabled?(organization_id) do
      Repo.put_process_state(organization_id)

      case Contacts.fetch_by_identity(:web, claims.sub) do
        {:ok, contact} ->
          conn
          |> assign(:web_channel_contact_id, contact.id)
          |> assign(:web_channel_organization_id, organization_id)

        {:error, _reason} ->
          unauthorized(conn)
      end
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
