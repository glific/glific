defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  """

  alias Glific.{
    Dialogflow.Sessions,
    Messages.Message,
    Processor.Helper,
    Taggers,
    Taggers.Numeric,
    Taggers.Status
  }

  @doc """
  Load the relevant state into the gen_server state object that we need
  to process messages
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id) do
    %{
      numeric_map: Numeric.get_numeric_map(),
      dialogflow_session_id: Ecto.UUID.generate()
    }
    |> Map.merge(Taggers.get_tag_maps(organization_id))
  end

  @doc false
  @spec process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  def process_message({message, state}, body) do
    state = Map.put(state, :tagged, false)

    {message, state}
    |> numeric_tagger(body)
    |> keyword_tagger(body)
    |> dialogflow_tagger()
    |> new_contact_tagger()
  end

  @spec numeric_tagger({atom() | Message.t(), map()}, String.t()) :: {Message.t(), map()}
  defp numeric_tagger({message, state}, body) do
    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} ->
        {
          Helper.add_tag(message, state.numeric_tag_id, value),
          Map.put(state, :tagged, true)
        }

      _ ->
        {message, state}
    end
  end

  @spec keyword_tagger({atom() | Message.t(), map()}, String.t()) :: {Message.t(), map()}
  defp keyword_tagger({message, state}, body) do
    case Taggers.Keyword.tag_body(body, state.keyword_map) do
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

      {message, state |> Map.put(:tagged, true) |> Map.put(:newcontact, true)}
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
    # only do the query if we have a valid credentials file for dialogflow
    if FunWithFlags.enabled?(:dialogflow,
         for: %{organization_id: message.organization_id}
       ),
       do: Sessions.detect_intent(message, state.dialogflow_session_id)

    {message, state}
  end

  defp dialogflow_tagger({message, state}), do: {message, state}

  @spec add_status_tag(Message.t(), String.t(), map()) :: Message.t()
  defp add_status_tag(message, status, state),
    do: Helper.add_tag(message, state.status_map[status])
end
