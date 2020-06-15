defmodule Glific.Processor.ConsumerText do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  alias Glific.Taggers.Numeric

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(_), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc false
  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer,
      numeric_map: Numeric.get_numeric_map()
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn %{type: type} -> type == :text end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc """
  public endpoint for adding a number and a value
  """
  @spec add_numeric(String.t(), integer) :: :ok
  def add_numeric(key, value), do: GenServer.call(__MODULE__, {:add_numeric, {key, value}})

  @doc false
  def handle_call({:add_numeric, {key, value}}, _from, state) do
    new_numeric_map = Map.put(state.numeric_map, key, value)

    {:reply, "Numeric Map Updated", [], Map.put(state, :numeric_map, new_numeric_map)}
  end

  @doc false
  def handle_info(_, state), do: {:noreply, [], state}

  @doc false
  def handle_events(messages, _from, state) do
    _ = Enum.map(messages, &process_message(&1, state.numeric_map))

    {:noreply, [], state}
  end

  @spec process_message(atom() | map(), %{binary() => integer()}) :: nil
  defp process_message(message, numeric_map) do
    case Numeric.tag_message(message, numeric_map) do
      {:ok, value} -> IO.puts("Text Consumer: #{value}")
      :error -> IO.puts("Text Consumer: Not numeric")
    end

    nil
  end
end
