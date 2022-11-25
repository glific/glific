defmodule GlificWeb.Providers.Airtel.Controllers.BillingEventController do
  @moduledoc """
  Dedicated controller to handle billing events from Airtel
  """

  use GlificWeb, :controller

  alias Glific.{
    MessageConversations,
    Providers.Airtel
  }

  @doc """
  Default handle for all billing event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, _params) do
    json(conn, nil)
  end

  @doc """
  Message status when the message has been sent to Airtel
  """
  @spec conversations(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def conversations(conn, params), do: handle_billing_event(conn, params)

  @doc """
  Callback for billing event
  """
  @spec handle_billing_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle_billing_event(conn, params) do
    with {:ok, message_conversation} <- Airtel.Message.receive_billing_event(params) do
      message_conversation
      |> Map.put(:organization_id, conn.assigns[:organization_id])
      |> MessageConversations.create_message_conversation()
    end

    handler(conn, params)
  end
end
