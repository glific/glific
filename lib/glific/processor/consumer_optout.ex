defmodule Glific.Processor.ConsumerOptout do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  alias Glific.{
    Contacts,
    Messages.Message,
    Processor.Helper,
    Repo,
    Tags.Tag
  }

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    Helper.start_link(opts, __MODULE__)
  end

  @doc false
  def init(opts) do
    Helper.init(opts, "Optout")
  end

  @doc false
  def handle_events(messages_tags, from, state) do
    Helper.handle_events(messages_tags, from, state, &process_tag/2)
  end

  # Process the optout tag. Send a confirmation to the sender and set the contact fields
  @spec process_tag(Message.t(), Tag.t()) :: any
  def process_tag(message, _tag) do
    # lets send the message first, so it goes out
    Helper.send_session_message_template(message, "optout")

    message =
      message
      |> Repo.preload([:sender])

    # We need to update the contact with optout_time and status
    Contacts.contact_opted_out(message.sender.phone, DateTime.utc_now())
  end
end
