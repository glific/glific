defmodule Glific.Processor.ConsumerOptout do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Processor.Helper,
    Repo,
    Tags.Tag
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.ConsumerOptout)
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
        selector: fn [_, %{label: label}] -> label == "Optout" end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc false
  def handle_events(messages_tags, _from, state) do
    _ = Enum.map(messages_tags, fn [m, t] -> process_tag(m, t) end)
    {:noreply, [], state}
  end

  # Process the optout tag. Send a confirmation to the sender and set the contact fields
  @spec process_tag(Message.t(), Tag.t()) :: any
  defp process_tag(message, _) do
    # lets send the message first, so it goes out
    Helper.send_session_message_template(message, "optout")

    # We need to update the contact with optout_time and status
    query = from(c in Contact, where: c.id == ^message.sender_id)

    Repo.update_all(query,
      set: [status: "invalid", optout_time: DateTime.utc_now(), updated_at: DateTime.utc_now()]
    )
  end
end
