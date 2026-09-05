defmodule Glific.AI.Tools.Triggers do
  @moduledoc """
  Reads the scheduled triggers that start flows: what each one starts, how often,
  and when it is next due.
  """

  alias Glific.Triggers

  @behaviour Glific.AI.Tool

  @doc "The trigger lookups this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "list_triggers",
        description: """
        Lists the scheduled triggers that start flows, with the flow each one
        starts and when it next fires. Use this to explain why a flow started on
        its own, or why an expected one did not.

        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      }
    ]
  end

  @doc "Reads the scheduled triggers that start flows."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("list_triggers", args) do
    triggers =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> Triggers.list_triggers()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          flow_id: &1.flow_id,
          is_active: &1.is_active,
          is_repeating: &1.is_repeating,
          frequency: &1.frequency,
          start_at: &1.start_at,
          next_trigger_at: &1.next_trigger_at,
          last_trigger_at: &1.last_trigger_at
        }
      )

    {:ok, triggers}
  end
end
