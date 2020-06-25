defmodule Glific.Processor.ConsumerHelp do
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
    Helper.init(opts, "Help")
  end

  @doc false
  def handle_events(messages_tags, from, state) do
    Helper.handle_events(messages_tags, from, state, &process_tag/2)
  end

  @doc """
  Process the help tag
  """
  @spec process_tag(Message.t(), Tag.t()) :: any
  def process_tag(message, _) do
    Helper.send_session_message_template(message, "help")
  end
end
