defmodule Glific.AI.Tools.Triggers do
  @moduledoc """
  Reads the scheduled triggers that start flows, and the log of when each one
  actually fired.

  A trigger that looks correctly configured but has no recent log entry is the
  usual answer to *"why did the reminder not go out"*.
  """

  alias Glific.{AI.History, Triggers, Triggers.TriggerLog}

  @behaviour Glific.AI.Tool

  @per_trigger 20

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

        Add `include: ["logs"]` to see when each one actually fired: a trigger
        that is active but has no recent firing never ran.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"],
          include: [
            type: {:list, {:in, ["logs"]}},
            default: [],
            doc: ~s(Add "logs" to see when each trigger actually fired)
          ]
        ]
      }
    ]
  end

  @doc "Reads the scheduled triggers, and optionally when each one actually fired."
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

    {:ok, with_logs(triggers, args[:include])}
  end

  @spec with_logs([map()], [String.t()]) :: [map()]
  defp with_logs(triggers, include) do
    if "logs" in include do
      logs = firings(Enum.map(triggers, & &1.id))
      Enum.map(triggers, &Map.put(&1, :fired_at, Map.get(logs, &1.id, [])))
    else
      triggers
    end
  end

  @spec firings([non_neg_integer()]) :: map()
  defp firings(trigger_ids) do
    History.newest_per_parent(
      TriggerLog,
      :trigger_id,
      [:started_at],
      [desc: :started_at, desc: :id],
      trigger_ids,
      @per_trigger
    )
  end
end
