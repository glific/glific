defmodule GlificWeb.API.V1.WebChannelContactController do
  @moduledoc """
  Contact provisioning for the web channel, authenticated by a JWT the NGO's own backend signs with
  its login secret (see `GlificWeb.WebChannel.LoginToken`).

  The endpoint is gated by the web channel, resolves the contact through
  `Glific.Contacts.Identities.resolve_or_create/3` (so repeating a call returns the same contact),
  and answers an invalid token with one generic 401. It signs nobody in: the NGO's token itself
  authenticates the WebSocket connection.
  """

  use GlificWeb, :controller

  alias Glific.{Contacts.Contact, Contacts.Identities, SafeLog}
  alias GlificWeb.WebChannel.{Flag, LoginToken}
  alias Plug.Conn

  @invalid_token_message "Invalid token"

  @doc """
  Creates, or returns, the contact for an NGO-signed token without signing anyone in.
  """
  @spec provision_contact(Conn.t(), map()) :: Conn.t()
  def provision_contact(conn, %{"token" => token}) when is_binary(token) and token != "" do
    with_valid_token(conn, token, fn contact -> json(conn, %{data: %{contact_id: contact.id}}) end)
  end

  def provision_contact(conn, _params), do: invalid_token_error(conn)

  @spec with_valid_token(Conn.t(), String.t(), (Contact.t() -> Conn.t())) :: Conn.t()
  defp with_valid_token(conn, token, on_success) do
    organization_id = conn.assigns[:organization_id]

    if Flag.web_channel_enabled?(organization_id) do
      with {:ok, claims} <- LoginToken.verify(organization_id, token),
           {:ok, contact} <- Identities.resolve_or_create(:web, claims.sub, claims) do
        on_success.(contact)
      else
        {:error, :invalid} -> invalid_token_error(conn)
        {:error, error} -> resolve_error(conn, error)
      end
    else
      conn
      |> put_status(404)
      |> json(%{
        error: %{status: 404, message: "Web channel is not enabled for this organization"}
      })
    end
  end

  @spec resolve_error(Conn.t(), any()) :: Conn.t()
  defp resolve_error(conn, error) do
    Glific.log_error("Could not resolve a web channel contact: " <> SafeLog.safe_inspect(error))

    conn
    |> put_status(500)
    |> json(%{error: %{status: 500, message: "Could not complete the request"}})
  end

  @spec invalid_token_error(Conn.t()) :: Conn.t()
  defp invalid_token_error(conn) do
    conn
    |> put_status(401)
    |> json(%{error: %{status: 401, message: @invalid_token_message}})
  end
end
