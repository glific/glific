defmodule GlificWeb.API.V1.WebChannelController do
  @moduledoc """
  Public entry points for the web channel widget.

  These are unauthenticated by design: the widget calls them before anyone has logged in.
  There is no organization identifier in the request — `GlificWeb.SubdomainPlug` has already
  resolved one from the host, which is what lets a single widget build serve every
  organization.
  """

  use GlificWeb, :controller

  alias Glific.{Partners, WebChannel.Branding}
  alias GlificWeb.WebChannel.Flag

  @doc """
  Returns the branding the widget should paint itself with, before its first render.

  200 either way. An organisation with the channel switched off still has a name and a WhatsApp
  number to send a contact to, and a 404 would leave the widget guessing at both — every other
  web channel endpoint refuses, but this one is what tells the visitor why.
  """
  @spec branding(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def branding(%Plug.Conn{assigns: %{organization_id: organization_id}} = conn, _params) do
    # organization/1 returns {:error, reason} on a cache or lookup failure, and everything
    # downstream reads the organization — so an unlucky lookup would raise on a public endpoint.
    case Partners.organization(organization_id) do
      {:error, _reason} ->
        not_found(conn)

      organization ->
        if Flag.web_channel_enabled?(organization),
          do: json(conn, %{data: Branding.for_organization(organization)}),
          else: json(conn, %{data: Branding.disabled_for_organization(organization)})
    end
  end

  @spec not_found(Plug.Conn.t()) :: Plug.Conn.t()
  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{status: 404, message: "Organization not found."}})
  end
end
