defmodule Glific.Processor.ConsumerText do
  use GenStage

  alias Glific.Taggers.Numeric

  def start_link(_), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  @min_demand 0
  @max_demand 1

  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer,
      numeric_map: Numeric.get_numeric_map()
    }

    {:consumer,
     state,
     subscribe_to: [{state.producer,
                     selector: fn %{type: type} -> type == :text end,
                     min_demand: @min_demand,
                     max_demand: @max_demand
                    }]}
  end

  # public endpoint for adding a number and a value
  @spec add_numeric(String.t(), integer) :: :ok
  def add_numeric(key, value), do: GenServer.call(__MODULE__, {:add_numeric, {key, value}})

  def handle_call({:add_numeric, {key, value}}, _from, state) do
    new_numeric_map =  Map.put(state.numeric_map, key, value)

    {:reply, "Numeric Map Updated", [], Map.put(state, :numeric_map, new_numeric_map)}
  end

  def handle_info(_, state), do: {:noreply, nil, state}

  def handle_events(messages, _from, state) do
    Enum.map(messages, &process_message(&1, state.numeric_map))

    {:noreply, [], state}
  end

  defp process_message(message, numeric_map) do
    IO.inspect(message)
    case Numeric.tag_message(message, numeric_map) do
      {:ok, value} -> IO.puts("Text Consumer: #{value}")
      :error -> IO.puts("Text Consumer: Not numeric")
    end
  end

end
