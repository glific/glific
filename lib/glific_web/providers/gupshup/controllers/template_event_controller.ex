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

    with %{"id" => bsp_id, "status" => status} = payload
         when is_binary(bsp_id) and is_binary(status) <- params["payload"],
         {:ok, _template} <-
           Templates.update_hsm_status(bsp_id, organization_id, status, payload["rejectedReason"]) do
      :ok
    else
      {:error, reason} ->
        Glific.log_error(
          "Gupshup template-event status update failed: #{Glific.SafeLog.safe_inspect(reason)}"
        )

      _invalid_payload ->
        :ok
    end

    handler(conn)
  end
end
