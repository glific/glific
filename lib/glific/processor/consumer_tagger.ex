defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  alias Glific.{
    Communications,
    Messages.Message,
    Repo,
    Taggers,
    Taggers.Keyword,
    Taggers.Numeric,
    Taggers.Status,
    Tags,
    Tags.MessageTag,
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
      producer: Glific.Processor.Producer,
      keyword_map: Keyword.get_keyword_map(),
      status_map: Status.get_status_map(),
      numeric_map: Numeric.get_numeric_map(),
      numeric_tag_id: 0
    }

    state =
      case Repo.fetch_by(Tag, %{label: "Numeric"}) do
        {:ok, tag} -> Map.put(state, :numeric_tag_id, tag.id)
        _ -> state
      end

    # Once we switch keyword to the DB, we will merge the map obtained from
    # the DB here

    {:producer_consumer, state,
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
    messages_with_tags = Enum.map(messages, &process_message(&1, state))

    {:noreply, messages_with_tags, state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Taggers.string_clean(message.body)
    add_unread_tag(message, state)
    new_contact_tagger(message, state)
    numeric = numeric_tagger(message, body, state)
    keyword = keyword_tagger(message, body, state)

    if numeric or keyword, do: Repo.preload(message, [:tags]), else: message
  end

  @spec numeric_tagger(atom() | Message.t(), String.t(), map()) :: boolean
  defp numeric_tagger(message, body, state) do
    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} ->
        _ = add_numeric_tag(message, value, state)
        true

      _ ->
        false
    end
  end

  @spec keyword_tagger(atom() | Message.t(), String.t(), map()) :: boolean
  defp keyword_tagger(message, body, state) do
    case Keyword.tag_body(body, state.keyword_map) do
      {:ok, value} ->
        add_keyword_tag(message, value, state)
        true

      _ ->
        false
    end
  end

  @spec new_contact_tagger(Message.t(), map()) :: boolean
  defp new_contact_tagger(message, state) do
    case Status.is_new_contact(message.sender_id) do
      true ->
        add_new_user_tag(message, state)
        true

      _ ->
        false
    end
  end

  defp add_unread_tag(message, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.status_map["Unread"]
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)
  end

  defp add_new_user_tag(message, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.status_map["New User"]
    })
    |> Communications.publish_data(:created_message_tag)
  end

  @spec add_numeric_tag(Message.t(), String.t(), atom() | map()) :: MessageTag.t()
  defp add_numeric_tag(message, value, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.numeric_tag_id,
      value: value
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)
  end

  @spec add_keyword_tag(Message.t(), String.t(), atom() | map()) :: MessageTag.t()
  defp add_keyword_tag(message, value, _state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: String.to_integer(value)
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)
  end
end
