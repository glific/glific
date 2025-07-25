defmodule GlificWeb.Providers.Gupshup.Controllers.BillingEventController do
  @moduledoc """
  Dedicated controller to handle billing events from Gupshup
  """

  use GlificWeb, :controller

  alias Glific.{
    MessageConversations,
    Providers.Gupshup
  }

  @doc """
  Default handle for all billing event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, _params) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Message status when the message has been sent to gupshup
  """
  @spec conversations(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def conversations(conn, params), do: handle_billing_event(conn, params)

  @doc """
  Callback for billing event
  """
  @spec handle_billing_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle_billing_event(conn, params) do
    # Since we only get non-nil conversationId on free-entry messages, we only have to
    # add entries where conversationId is not nil.
    with {:ok, message_conversation} <- Gupshup.Message.receive_billing_event(params),
         false <- is_nil(message_conversation.conversation_id) do
      message_conversation
      |> Map.put(:organization_id, conn.assigns[:organization_id])
      |> MessageConversations.create_message_conversation()
    end

    handler(conn, params)
  end
end
