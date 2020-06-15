defmodule Glific.Processor.ConsumerText do
  use GenStage

  alias Glific.Taggers.Numeric

  def start_link(_), do: GenStage.start_link(__MODULE__, :ok)

  @min_demand 0
  @max_demand 1

  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer
    }

    {:consumer,
     state,
     subscribe_to: [{state.producer,
                     selector: fn %{type: type} -> type == :text end,
                     min_demand: @min_demand,
                     max_demand: @max_demand
                    }]}
  end

  def handle_info(_, state), do: {:noreply, nil, state}

  def handle_events(messages, _from, state) do
    [message | _] =  messages
    IO.inspect(message)
    case Numeric.tag_message(message) do
      {:ok, value} -> IO.inspect(value)
      :error -> nil
    end

    {:noreply, [], state}
  end
end
