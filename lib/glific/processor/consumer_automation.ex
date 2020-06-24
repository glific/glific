defmodule Glific.Processor.ConsumerAutomation do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.ConsumerTagger)
    GenStage.start_link(__MODULE__, [producer: producer], name: name)
  end

  @doc false
  def init(opts) do
    state = %{
      producer: opts[:producer]
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer, min_demand: @min_demand, max_demand: @max_demand}
     ]}
  end

  @doc false
  def handle_events(messages_tags, _from, state) do
    _ = Enum.map(messages_tags, fn [m, t] -> process_tag(m, t) end)
    {:noreply, [], state}
  end

  defp process_tag(message, _tag), do: message
end
