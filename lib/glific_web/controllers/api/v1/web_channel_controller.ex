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
  """
  @spec branding(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def branding(%Plug.Conn{assigns: %{organization_id: organization_id}} = conn, _params) do
    # organization/1 returns {:error, reason} on a cache or lookup failure, and everything
    # downstream reads organization.id — so an unlucky lookup would raise on a public endpoint.
    case Partners.organization(organization_id) do
      {:error, _reason} ->
        not_enabled(conn)

      organization ->
        if Flag.web_channel_enabled?(organization),
          do: json(conn, %{data: Branding.for_organization(organization)}),
          else: not_enabled(conn)
    end
  end

  @spec not_enabled(Plug.Conn.t()) :: Plug.Conn.t()
  defp not_enabled(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{status: 404, message: "Web channel is not enabled."}})
  end
end
