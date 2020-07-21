defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  alias Glific.{
    Communications,
    Flows.Flow,
    Flows.FlowContext,
    Messages.Message,
    Processor.Helper,
    Repo,
    Taggers,
    Taggers.Numeric,
    Taggers.Status,
    Tags,
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
      |> reload_flows

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
    case Repo.fetch_by(Tag, %{label: "Numeric"}) do
      {:ok, tag} -> Map.put(state, :numeric_tag_id, tag.id)
      _ -> state
    end
    |> Map.merge(%{
      keyword_map: Taggers.Keyword.get_keyword_map(),
      status_map: Status.get_status_map()
    })
  end

  defp reload(state), do: state

  defp reload_flows(%{flows: flow} = state) when flow == %{} do
    Map.put(
      state,
      :flows,
      Flow.get_and_cache_flows()
    )
  end

  defp reload_flows(state), do: state

  @doc false
  def handle_events(messages, _from, state) do
    _ = Enum.map(messages, &process_message(&1, state))

    {:noreply, [], state}
  end

  @spec process_message(atom() | Message.t(), map()) :: Message.t()
  defp process_message(message, state) do
    body = Glific.string_clean(message.body)

    message
    |> add_status_tag("Unread", state)
    |> add_not_reply_tag(state)
    |> numeric_tagger(body, state)
    |> keyword_tagger(body, state)
    # we do this before, so it will not pick up the potential flow
    # started by new conatct tagger
    |> check_flows(body, state)
    |> new_contact_tagger(state)
    |> Repo.preload(:tags)
    |> Communications.publish_data(:created_message_tag)
  end

  @spec check_flows(atom() | Message.t(), String.t(), map()) :: Message.t()
  defp check_flows(message, body, state)
       when body in [
              "help",
              "language",
              "preference",
              "new contact",
              "newcontact",
              "registration"
            ] do
    message = Repo.preload(message, :contact)
    FlowContext.init_context(Map.get(state.flows, body), message.contact)
    message
  end

  defp check_flows(message, _body, state) do
    context = FlowContext.active_context(message.contact_id)

    if context,
      do:
        context
        |> FlowContext.load_context(state.flows[context.flow_id])
        |> FlowContext.step_forward(message.body)

    # we can potentially save the {contact_id, context} map here in the flow state,
    # to avoid hitting the DB again. We'll do this after we get this working
    message
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
      |> add_status_tag("New Contact", state)
      |> check_flows("new contact", state)
    end

    message
  end

  @spec add_status_tag(Message.t(), String.t(), map()) :: Message.t()
  defp add_status_tag(message, status, state),
    do: Helper.add_tag(message, state.status_map[status])

  @spec add_not_reply_tag(Message.t(), map()) :: Message.t()
  defp add_not_reply_tag(message, state) do
    Tags.remove_tag_from_all_message(message.contact_id, "Not Replied")
    add_status_tag(message, "Not Replied", state)
  end
end
