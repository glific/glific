defmodule Glific.Processor.ConsumerText do
  use GenStage

  def start_link, do: start_link([])
  def start_link(_), do: GenStage.start_link(__MODULE__, :ok)

  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer
    }

    {:consumer,
     state,
     subscribe_to: [{state.producer,
                     selector: fn %{type: type} -> type == :text end}]}
  end

  def handle_info(_, state), do: {:noreply, nil, state}

  def handle_events(message, _from, state) do

  end
end
