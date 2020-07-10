defmodule Glific.Processor.ConsumerSequence do
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
    "start" => %{label: "Sequence", value: 0, shortcode: "start", prev: "menu", next: "0"},
    "0" => %{label: "Sequence", value: 1, shortcode: "zero", prev: "start", next: "1"},
    "1" => %{label: "Sequence", value: 1, shortcode: "one", prev: "0", next: "2"},
    "2" => %{label: "Sequence", value: 2, shortcode: "two", prev: "1", next: "3"},
    "3" => %{label: "Sequence", value: 3, shortcode: "three", prev: "2", next: "4"},
    "4" => %{label: "Sequence", value: 4, shortcode: "four", prev: "3", next: "5"},
    "5" => %{label: "Sequence", value: 5, shortcode: "five", prev: "4", next: "6"},
    "6" => %{label: "Sequence", value: 6, shortcode: "six", prev: "5", next: "7"},
    "7" => %{label: "Sequence", value: 7, shortcode: "seven", prev: "6", next: "8"},
    "8" => %{label: "Sequence", value: 8, shortcode: "eight", prev: "7", next: "9"},
    "9" => %{label: "Sequence", value: 9, shortcode: "menu", prev: "8", next: "start"}
  }

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    Helper.start_link(opts, __MODULE__)
  end

  @doc false
  def init(opts) do
    Helper.init(opts, "Sequence")
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

    case message_tag.value do
      "start" -> process_start(message, tag)
      "prev" -> process_prev(message, tag)
      "next" -> process_next(message, tag)
      "menu" -> process_menu(message)
      _ -> message
    end
  end

  defp process_start(message, tag) do
    Helper.send_session_message_template_with_tag(message, tag, "id: start", "start")
    process_menu(message)
  end

  defp process_menu(message),
    do: Helper.send_session_message_template(message, "menu")

  defp last_message_sent(contact_id) do
    sql = """
    SELECT substring(mt.value from 5)
    FROM messages m
    LEFT JOIN messages_tags mt ON m.id = mt.message_id
    LEFT JOIN tags t ON t.id = mt.tag_id
    WHERE m.contact_id = #{contact_id}
    AND m.flow = 'outbound'
    AND t.label = 'Sequence'
    AND substring(mt.value from 1 for 4) = 'id: '
    ORDER BY m.inserted_at DESC
    LIMIT 1
    """

    {:ok, results} = Repo.query(sql)

    if results.num_rows == 1 do
      [[result]] = results.rows
      result
    else
      ""
    end
  end

  defp process_next(message, tag),
    do: process_either(message, tag, :next)

  defp process_prev(message, tag),
    do: process_either(message, tag, :prev)

  defp process_either(message, tag, direction) do
    # we first need to find out the last message we sent and the index
    value = last_message_sent(message.contact_id)
    entry = Map.get(@automaton, value)

    if entry != nil do
      direction_value =
        if direction == :next,
          do: entry.next,
          else: entry.prev

      Helper.send_session_message_template_with_tag(
        message,
        tag,
        "id: " <> direction_value,
        @automaton[direction_value][:shortcode]
      )
    end
  end
end
