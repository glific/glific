defmodule Glific.Processor.Producer do
  @moduledoc """
  This producer is linked to the message receiving end and gets messages from
  the external world in the message structure
  """
  use GenStage

  alias Glific.Messages.Message

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, :ok, name: name)
  end

  @doc false
  def init(:ok) do
    {:producer, nil, dispatcher: GenStage.BroadcastDispatcher}
  end

  @doc """
  public endpoint for adding a new message or a set of messages
  """
  @spec add([Message.t()]) :: :ok
  def add(messages) when is_list(messages), do: GenServer.cast(__MODULE__, {:add, messages})

  @spec add(Message.t()) :: :ok
  def add(message), do: GenServer.cast(__MODULE__, {:add, [message]})

  @doc """
  push a message to all consumers on adding
  """
  @spec handle_cast({:add, [Message.t()]}, map()) :: {:noreply, [Message.t()], map()}
  def handle_cast({:add, messages}, state), do: {:noreply, messages, state}

  @doc """
  ignore all requests from consumers via demand call
  """
  @spec handle_demand(integer, any) :: {:noreply, [], map()}
  def handle_demand(_, state), do: {:noreply, [], state}
end
