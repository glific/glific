defmodule GlificWeb.API.V1.WebChannelController do
  @moduledoc """
  Public entry points for the web channel widget.

  These are unauthenticated by design: the widget calls them before anyone has logged in.
  There is no organization identifier in the request — `GlificWeb.SubdomainPlug` has already
  resolved one from the host, which is what lets a single widget build serve every
  organization.
  """

  use GlificWeb, :controller

  alias Glific.{Flags, Partners, WebChannel.Theme}

  @doc """
  Returns the branding the widget should paint itself with, before its first render.
  """
  @spec theme(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def theme(%Plug.Conn{assigns: %{organization_id: organization_id}} = conn, _params) do
    organization = Partners.organization(organization_id)

    if Flags.get_flag_enabled(:web_channel_enabled, organization) do
      json(conn, %{data: Theme.for_organization(organization)})
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: %{status: 404, message: "Web channel is not enabled."}})
    end
  end
end
