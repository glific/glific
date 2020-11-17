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
  def handle_call({message, _process_state, from}, _, state) do
    send(from, :received_message_to_process)
    {:reply, message, state}
  end

  @doc false
  def handle_cast({_message, _process_state, from}, state) do
    send(from, :received_message_to_process)
    {:noreply, state}
  end
end
