defmodule GlificWeb.Providers.Gupshup.Controllers.BillingEventController do
  @moduledoc """
  Dedicated controller to handle billing events from Gupshup
  """

  use GlificWeb, :controller
  alias Glific.MessageConversations

  @doc """
  Default handle for all billing event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, _params) do
    json(conn, nil)
  end

  @doc """
  Message status when the message has been sent to gupshup
  """
  @spec conversations(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def conversations(conn, params), do: handle_billing_event(conn, params)

  @spec handle_billing_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp handle_billing_event(conn, params) do
    organization_id = conn.assigns[:organization_id]

    MessageConversations.receive_billing_event(params, organization_id)
    handler(conn, params)
  end
end
