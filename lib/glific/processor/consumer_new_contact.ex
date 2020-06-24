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

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    Helper.start_link(opts, __MODULE__)
  end

  @doc false
  def init(opts) do
    Helper.init(opts, "New Contact")
  end

  @doc false
  def handle_events(messages_tags, from, state) do
    Helper.handle_events(messages_tags, from, state, &process_tag/2)
  end

  # Process the new contact tag
  @spec process_tag(Message.t(), Tag.t()) :: any
  defp process_tag(message, _) do
    # lets send the message first, so it goes out
    Helper.send_session_message_template(message, "new contact")
  end
end
