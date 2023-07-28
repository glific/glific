defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  """

  alias Glific.{
    Messages.Message,
    Processor.Helper,
    Taggers,
    Taggers.Status
  }

  @doc """
  Load the relevant state into the gen_server state object that we need
  to process messages
  """
  @spec load_state(non_neg_integer) :: map()
  def load_state(organization_id) do
    organization_id
    |> Taggers.get_tag_maps()
    |> Map.put(:dialogflow_session_id, Ecto.UUID.generate())
  end

  @doc false
  @spec process_message({Message.t(), map()}, String.t()) :: {Message.t(), map()}
  def process_message({message, state}, _body) do
    state = Map.put(state, :tagged, false)

    {message, state}
    |> new_contact_tagger()
  end

  @spec new_contact_tagger({atom() | Message.t(), map()}) :: {Message.t(), map()}
  defp new_contact_tagger({message, state}) do
    if Status.is_new_contact(message) do
      add_status_tag(message, "newcontact", state)
      {message, state |> Map.put(:tagged, true) |> Map.put(:newcontact, true)}
    else
      {message, state}
    end
  end

  _ = """
  Commenting out the next few functions as we eliminate work that we are not using

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
  """

  _ = ~c"""
  alias Glific.Dialogflow.Sessions

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
  """

  @spec add_status_tag(Message.t(), String.t(), map()) :: Message.t()
  defp add_status_tag(message, status, state),
    do: Helper.add_tag(message, state.status_map[status])
end
