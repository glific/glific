defmodule GlificWeb.Providers.Maytapi.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like sent, delivered etc..
  """
  use GlificWeb, :controller

  alias Glific.Communications

  @message_event_type %{
    "delivered" => :delivered,
    "sent" => :sent,
    "read" => :read
  }

  @doc """
  Default handle for all message event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, %{"data" => response} = _params) do
    response
    |> Enum.each(&update_status(&1, &1["ackType"]))

    json(conn, nil)
  end

  # Updates the provider message status based on provider message id
  @spec update_status(map(), String.t()) :: any()
  defp update_status(params, status) do
    status = Map.get(@message_event_type, status)
    bsp_message_id = Map.get(params, "msgId")
    Communications.GroupMessage.update_bsp_status(bsp_message_id, status)
  end
end
