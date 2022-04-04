defmodule GlificWeb.Providers.Gupshup.Enterprise.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like read, delivered etc..
  """
  use GlificWeb, :controller

  alias Glific.Communications

  @message_event_type %{
    "DELIVERED" => :delivered,
    "SENT" => :sent,
    "READ" => :read
  }
  @doc """
  Default handle for all message event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, %{"response" => response} = _params) do
    response
    |> Jason.decode!()
    |> Enum.each(&update_status(&1, &1["eventType"]))

    json(conn, nil)
  end

  # Updates the provider message status based on provider message id
  @spec update_status(map(), String.t()) :: any()
  defp update_status(params, status) do
    IO.inspect(params)
    status = Map.get(@message_event_type, status)
    bsp_message_id = Map.get(params, "externalId")
    Communications.Message.update_bsp_status(bsp_message_id, status, params)
  end
end
