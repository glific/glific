defmodule Glific.Processor.ConsumerAutomation do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new user tag with a welcome message
  """

  use GenStage

  alias Glific.{
    Messages,
    Messages.Message,
    Tags.Tag
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link(any) :: GenServer.on_start()
  def start_link(_), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc false
  def init(:ok) do
    state = %{
      producer: Glific.Processor.ConsumerTagger
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn %{type: type} -> type == :text end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc false
  def handle_info(_, state), do: {:noreply, [], state}

  @doc false
  def handle_events(messages, _from, state) do
    _ =
      messages
      |> Enum.filter(fn m -> Ecto.assoc_loaded?(m.tags) end)
      |> Enum.map(fn m ->
        Enum.map(m.tags, fn t -> process_tag(m, t) end)
      end)

    {:noreply, [], state}
  end

  @spec process_tag(Message.t(), Tag.t()) :: nil
  defp process_tag(message, tag) do
    if tag.label == "Welcome" do
      Messages.create_and_send_session_template(3, message.receiver_id)
    end

    nil
  end
end
