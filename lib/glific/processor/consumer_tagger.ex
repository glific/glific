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
    Processor.ConsumerFlow,
    Processor.Helper,
    Repo,
    Taggers,
    Taggers.Numeric,
    Taggers.Status,
    Tags.Tag
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.Producer)
    GenStage.start_link(__MODULE__, [producer: producer], name: name)
  end

  @doc false
  def init(opts) do
    state =
      %{
        producer: opts[:producer],
        numeric_map: Numeric.get_numeric_map(),
        numeric_tag_id: 0,
        flows: %{}
      }
      |> reload

    {
      :consumer,
      state,
      # dispatcher: GenStage.BroadcastDispatcher,
      subscribe_to: [
        {state.producer,
         selector: fn %{type: type} -> type == :text end,
         min_demand: @min_demand,
         max_demand: @max_demand}
      ]
    }
  end

  defp reload(%{numeric_tag_id: numeric_tag_id} = state) when numeric_tag_id == 0 do
    case Repo.fetch_by(Tag, %{shortcode: "numeric"}) do
      {:ok, tag} -> Map.put(state, :numeric_tag_id, tag.id)
      _ -> state
    end
    |> Map.merge(%{
      keyword_map: Taggers.Keyword.get_keyword_map(),
      status_map: Status.get_status_map()
    })
  end

  defp reload(state), do: state

  @doc false
  def handle_events(messages, _from, state) do
    Enum.each(messages, &process_message(&1, state))

    {:noreply, [], state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    message
    |> numeric_tagger(body, state)
    |> keyword_tagger(body, state)
    |> new_contact_tagger(state)
    |> Repo.preload(:tags)
    |> Communications.publish_data(:created_message_tag)
  end

  @spec numeric_tagger(atom() | Message.t(), String.t(), map()) :: Message.t()
  defp numeric_tagger(message, body, state) do
    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} -> Helper.add_tag(message, state.numeric_tag_id, value)
      _ -> message
    end
  end

  @spec keyword_tagger(atom() | Message.t(), String.t(), map()) :: Message.t()
  defp keyword_tagger(message, body, state) do
    case Taggers.Keyword.tag_body(body, state.keyword_map) do
      {:ok, value} -> Helper.add_tag(message, value, body)
      _ -> message
    end
  end

  @spec new_contact_tagger(Message.t(), map()) :: Message.t()
  defp new_contact_tagger(message, state) do
    if Status.is_new_contact(message.sender_id) do
      message
      |> add_status_tag("new-contact", state)
      # We make a cross module function call which is its own genserver
      # but should be fine for now
      |> ConsumerFlow.check_flows("newcontact", state)
    end

    message
  end

  @spec add_status_tag(Message.t(), String.t(), map()) :: Message.t()
  defp add_status_tag(message, status, state),
    do: Helper.add_tag(message, state.status_map[status])
end
