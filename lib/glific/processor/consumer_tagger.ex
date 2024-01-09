defmodule Glific.Processor.ConsumerTagger do
  @moduledoc """
  Process all messages of type consumer and run them thru the various in-built taggers.
  """

  alias Glific.{
    Messages.Message,
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
    if Status.new_contact?(message) do
      {message, state |> Map.put(:tagged, true) |> Map.put(:newcontact, true)}
    else
      {message, state}
    end
  end
end
