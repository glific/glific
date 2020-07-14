defmodule Glific.Processor.ConsumerNumeric do
  @moduledoc """
  We'll first create the data in the module and as we reason with it, we'll migrate to the database
  """

  use GenStage

  alias Glific.{
    Messages.Message,
    Processor.Helper,
    Repo,
    Tags.MessageTag,
    Tags.Tag
  }

  @automaton %{
    0 => %{label: "Numeric", value: 0, shortcode: "zero"},
    1 => %{label: "Numeric", value: 1, shortcode: "one"},
    2 => %{label: "Numeric", value: 2, shortcode: "two"},
    3 => %{label: "Numeric", value: 3, shortcode: "three"},
    4 => %{label: "Numeric", value: 4, shortcode: "four"},
    5 => %{label: "Numeric", value: 5, shortcode: "five"},
    6 => %{label: "Numeric", value: 6, shortcode: "six"},
    7 => %{label: "Numeric", value: 7, shortcode: "seven"},
    8 => %{label: "Numeric", value: 8, shortcode: "eight"},
    9 => %{label: "Numeric", value: 9, shortcode: "help"}
  }

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    Helper.start_link(opts, __MODULE__)
  end

  @doc false
  def init(opts) do
    Helper.init(opts, "Numeric NO")
  end

  @doc false
  def handle_events(messages_tags, from, state) do
    Helper.handle_events(messages_tags, from, state, &process_tag/2)
  end

  @doc """
  Process the numeric tag, get its value and see if it is a global keyword
  """
  @spec process_tag(Message.t(), Tag.t()) :: any
  def process_tag(message, tag) do
    {:ok, message_tag} = Repo.fetch_by(MessageTag, %{message_id: message.id, tag_id: tag.id})
    value = String.to_integer(message_tag.value)

    auto = Map.get(@automaton, value)

    if auto != nil,
      do: Helper.send_session_message_template(message, auto.shortcode)

    message
  end
end
