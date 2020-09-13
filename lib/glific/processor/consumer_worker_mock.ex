defmodule Glific.Processor.ConsumerWorkerMock do
  @moduledoc """
  A mock for the consumer worker for poolboy
  """

  use GenServer

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts
    )
  end

  @doc false
  def init(state) do
    {:ok, state}
  end

  @doc false
  def handle_call(_message, _from, state) do
    send(self(), :received_message_to_process)
    {:reply, message, state}
  end

  @doc false
  def handle_cast(_message, state) do
    send(self(), :received_message_to_process)
    {:noreply, state}
  end
end
