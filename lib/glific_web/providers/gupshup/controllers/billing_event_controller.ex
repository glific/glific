defmodule GlificWeb.Providers.Gupshup.Controllers.BillingEventController do
  @moduledoc """
  Dedicated controller to handle billing events from Gupshup
  """

  use GlificWeb, :controller

  @doc """
  Default handle for all billing event callbacks
  """
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc """
  Message status when the message has been sent to gupshup
  """
  @spec conversations(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def conversations(conn, params), do: update_status(conn, params, :enqueued)

  @spec update_status(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp update_status(conn, params, status) do
    params
    |> receive_billing_event()
    |> Map.put(:organization_id, conn.assigns[:organization_id])

    handler(conn, params, "Status updated")
  end

  defp receive_billing_event(params) do
    references = get_in(params, ["payload", "references"])
    deductions = get_in(params, ["payload", "deductions"])
    bsp_message_id = references["gsId"]|| references["id"]
  end
end
