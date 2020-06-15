defmodule Glific.Processor.Producer do
  @moduledoc """
  This producer is linked to the message receiving end and gets messages from
  the external world in the message structure
  """
  use GenStage

  def start_link(_) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:producer, nil, dispatcher: GenStage.BroadcastDispatcher}
  end

  # public endpoint for adding a new message
  def add(message), do: GenServer.cast(__MODULE__, {:add, message})

  # push a message to all consumers on adding
  def handle_cast({:add, message}, state), do: {:noreply, [message], state}

  # ignore all requests from consumers via demand call
  def handle_demand(_, state), do: {:noreply, [], state}
end
