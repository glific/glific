defmodule Glific.Processor.ConsumerNewContact do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  alias Glific.{
    Messages.Message,
    Processor.Helper,
    Tags.Tag
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.ConsumerNewContact)
    GenStage.start_link(__MODULE__, [producer: producer], name: name)
  end

  @doc false
  def init(opts) do
    state = %{
      producer: opts[:producer]
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn [_, %{label: label}] -> label == "New Contact" end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc false
  def handle_events(messages_tags, _from, state) do
    _ = Enum.map(messages_tags, fn [m, t] -> process_tag(m, t) end)
    {:noreply, [], state}
  end

  # Process the new contact tag
  @spec process_tag(Message.t(), Tag.t()) :: any
  defp process_tag(message, _) do
    # lets send the message first, so it goes out
    Helper.send_session_message_template(message, "new contact")
  end
end
