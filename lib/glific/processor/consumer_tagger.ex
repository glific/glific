defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  At a later stage, we will also do translation and dialogflow queries as an offshoot
  from this GenStage
  """

  use GenStage

  alias Glific.{
    Dialogflow.Sessions,
    Messages.Message,
    Partners,
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
        numeric_tag_id: %{},
        keyword_map: %{},
        status_map: %{},
        flows: %{},
        dialogflow_session_id: Ecto.UUID.generate(),
        tagged: false
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

  defp reload(%{numeric_tag_id: numeric_tag_id} = state) when numeric_tag_id == %{} do
    Partners.list_organizations()
    |> Enum.reduce(state, fn organization, state_acc ->
      attrs = %{organization_id: organization.id}

      case Repo.fetch_by(
             Tag,
             %{shortcode: "numeric", organization_id: organization.id}
           ) do
        {:ok, tag} -> put_in(state_acc.numeric_tag_id[organization.id], tag.id)
        _ -> state_acc
      end
      |> put_in([:keyword_map, organization.id], Taggers.Keyword.get_keyword_map(attrs))
      |> put_in([:status_map, organization.id], Status.get_status_map(attrs))
    end)
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

    {message, Map.merge(state, %{tagged: false, organization_id: message.organization_id})}
    |> numeric_tagger(body)
    |> keyword_tagger(body)
    |> dialogflow_tagger()
    |> new_contact_tagger()
    # get the first element which is the message
    |> elem(0)
    |> Repo.preload(:tags)
  end

  @spec numeric_tagger({atom() | Message.t(), map()}, String.t()) :: {Message.t(), map()}
  defp numeric_tagger({message, state}, body) do
    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} ->
        {
          Helper.add_tag(message, state.numeric_tag_id[state.organization_id], value),
          Map.put(state, :tagged, true)
        }

      _ ->
        {message, state}
    end
  end

  @spec keyword_tagger({atom() | Message.t(), map()}, String.t()) :: {Message.t(), map()}
  defp keyword_tagger({message, state}, body) do
    case Taggers.Keyword.tag_body(body, state.keyword_map[state.organization_id]) do
      {:ok, value} ->
        {
          Helper.add_tag(message, value, body),
          Map.put(state, :tagged, true)
        }

      _ ->
        {message, state}
    end
  end

  @spec new_contact_tagger({atom() | Message.t(), map()}) :: {Message.t(), map()}
  defp new_contact_tagger({message, state}) do
    if Status.is_new_contact(message.sender_id) do
      message
      |> add_status_tag("newcontact", state)
      # We make a cross module function call which is its own genserver
      # but should be fine for now
      |> ConsumerFlow.check_flows("newcontact", state)

      {message, Map.put(state, :tagged, true)}
    else
      {message, state}
    end
  end

  @spec dialogflow_tagger({Message.t(), map()}) :: {Message.t(), map()}
  # dialog flow only accepts messages less than 255 characters for intent
  defp dialogflow_tagger({%{body: body} = message, %{tagged: false} = state})
       when byte_size(body) > 255,
       do: {message, state}

  defp dialogflow_tagger({message, %{tagged: false} = state}) do
    # Since conatct and language are the required filed, we can skip some pattern checks.
    message = Repo.preload(message, contact: [:language])

    # only do the query if we have a valid credentials file for dialogflow
    if FunWithFlags.enabled?(:dialogflow) do
      {:ok, response} =
        Sessions.detect_intent(
          message.body,
          state.dialogflow_session_id,
          message.contact.language.locale
        )

      Helper.add_dialogflow_tag(message, response["queryResult"])
    end

    {message, state}
  end

  defp dialogflow_tagger({message, state}), do: {message, state}

  @spec add_status_tag(Message.t(), String.t(), map()) :: Message.t()
  defp add_status_tag(message, status, state),
    do: Helper.add_tag(message, state.status_map[state.organization_id][status])
end
