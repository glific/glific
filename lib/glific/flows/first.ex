defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  alias Glific.{
    Contacts,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowRevision,
    Repo
  }

  import Ecto.Query, warn: false

  @doc """
  iex module for us to interact with our actions and events
  """
  @spec init(String.t()) :: Flow.t()
  def init(shortcode) do
    query =
      from fr in FlowRevision,
        join: f in assoc(fr, :flow),
        where: fr.revision_number == 0 and fr.flow_id == f.id and f.shortcode == ^shortcode,
        select: [fr.flow_id, fr.definition]

    [flow_id, description] = Repo.one(query)

    description
    |> remove_definition()
    # lets get rid of stuff we msdon't use
    |> Map.delete("_ui")
    |> Flow.process(flow_id)
  end

  # in some cases floweditor wraps the json under a "definition" key
  defp remove_definition(json),
    do: elem(Map.pop(json, "definition", json), 0)

  @doc """
  A simple runner function to step the flow through multiple arguments. Should stop
  when we are either done, or return an error
  """
  @spec run :: map()
  def run do
    %{
      1 => Flow.context(init("help"), Contacts.get_contact!(1)),
      2 => Flow.context(init("language"), Contacts.get_contact!(2)),
      3 => Flow.context(init("preferences"), Contacts.get_contact!(3))
    }
  end

  @doc """
  Simulate sending one message to a specific contact id, which will trigger a context reload
  """
  @spec one_message(map(), integer, String.t()) ::
          {:ok, map()} | {:error, String.t()} | {:halt, [String.t()]}
  def one_message(state, contact_id, msg) do
    # if contact does not exist in state, we should return error
    context =
      state[contact_id]
      |> Map.put(:node, state[contact_id].node_map)

    case FlowContext.execute(context, [msg]) do
      {:ok, context, []} -> {:ok, Map.put(state, contact_id, context)}
      {:error, error} -> {:error, error}
      {:ok, _context, messages} -> {:halt, messages}
    end
  end
end
