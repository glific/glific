defmodule GlificWeb.Providers.Gupshup.Controllers.TemplateEventController do
  @moduledoc """
  Dedicated controller to handle template status events pushed by Gupshup,
  i.e. real-time HSM approval / rejection updates from Meta.
  """
  use GlificWeb, :controller

  alias Glific.Templates

  @doc """
  Default handle for all template event callbacks
  """
  @spec handler(Plug.Conn.t()) :: Plug.Conn.t()
  def handler(conn) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Applies a template status update (approved / rejected) to the matching HSM
  template, identified by its `bsp_id`.
  """
  @spec status_update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status_update(conn, params) do
    organization_id = conn.assigns[:organization_id]
    payload = params["payload"] || %{}

    with bsp_id when is_binary(bsp_id) <- payload["id"],
         status when is_binary(status) <- payload["status"] do
      Templates.update_hsm_status(bsp_id, organization_id, status, payload["rejectedReason"])
    end

    handler(conn)
  end
end
