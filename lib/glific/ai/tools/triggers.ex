defmodule Glific.AI.Tools.Triggers do
  @moduledoc """
  Reads the scheduled triggers that start flows, and the log of when each one
  actually fired.

  A trigger that looks correctly configured but has no recent log entry is the
  usual answer to *"why did the reminder not go out"*.
  """

  import Ecto.Query

  alias Glific.{Repo, Triggers, Triggers.TriggerLog}

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
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
      },
      %{
        name: "trigger_logs",
        description: """
        Lists when triggers actually fired, newest first. Compare this with
        list_triggers: a trigger that is active but absent here never ran.
        """,
        parameters: [
          trigger_id: [type: :pos_integer, doc: "Only firings of this trigger"],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
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

  def run("trigger_logs", args) do
    logs =
      TriggerLog
      |> maybe_for_trigger(args[:trigger_id])
      |> order_by([l], desc: l.started_at)
      |> limit(^min(args[:limit], 100))
      |> select([l], %{trigger_id: l.trigger_id, started_at: l.started_at})
      |> Repo.all()

    {:ok, logs}
  end

  @spec maybe_for_trigger(Ecto.Queryable.t(), non_neg_integer() | nil) :: Ecto.Queryable.t()
  defp maybe_for_trigger(query, nil), do: query
  defp maybe_for_trigger(query, id), do: where(query, [l], l.trigger_id == ^id)
end
