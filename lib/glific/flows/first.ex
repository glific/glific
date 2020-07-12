defmodule Glific.Flows.First do
  @moduledoc """
  Random experiments on how to process flows emitted
  by nyaruka floweditor
  """

  alias Glific.{
    Contacts,
    Flows.Flow,
    Flows.FlowContext
  }

  import Ecto.Query, warn: false

  @doc """
  A simple runner function to step the flow through multiple arguments. Should stop
  when we are either done, or return an error
  """
  @spec run :: map()
  def run do
    %{
      1 => Flow.context(Flow.load_flow("help"), Contacts.get_contact!(1)),
      2 => Flow.context(Flow.load_flow("language"), Contacts.get_contact!(2)),
      3 => Flow.context(Flow.load_flow("preferences"), Contacts.get_contact!(3))
    }
  end

  @doc """
  Simulate sending one message to a specific contact id, which will trigger a context reload
  """
  @spec one_message(map(), integer, String.t()) ::
          {:ok, map()} | {:error, String.t()} | {:halt, [String.t()]}
  def one_message(state, contact_id, msg) do
    # if contact does not exist in state, we should return error
    context = state[contact_id]

    case FlowContext.execute(context, [msg]) do
      {:ok, context, []} -> {:ok, Map.put(state, contact_id, context)}
      {:error, error} -> {:error, error}
      {:ok, _context, messages} -> {:halt, messages}
    end
  end
end
