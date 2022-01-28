defmodule Glific.Triggers do
  @moduledoc """
  The trigger manager for all the trigger system that starts flows
  within Glific
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Flows,
    Groups,
    Repo,
    Triggers.Helper,
    Triggers.Trigger
  }

  @max_trigger_limit 1000

  @doc """
  Periodic call to execute the triggers outstanding for the day
  """
  @spec execute_triggers(non_neg_integer(), DateTime.t()) :: [Trigger.t()]
  def execute_triggers(organization_id, now \\ DateTime.utc_now()) do
    # triggers are executed at most once per day
    now = Timex.shift(now, minutes: 1)

    Trigger
    |> where([t], t.organization_id == ^organization_id and t.is_active == true)
    |> where(
      [t],
      is_nil(t.last_trigger_at) or
        fragment(
          "date_trunc('day', ?) != ?",
          t.last_trigger_at,
          ^Timex.beginning_of_day(now)
        )
    )
    |> where([t], t.next_trigger_at < ^now)
    |> select([t], t.id)
    |> limit(@max_trigger_limit)
    |> Repo.all()
    |> Enum.map(&execute_trigger(&1, now))
  end

  @spec execute_trigger(non_neg_integer, DateTime.t()) :: nil
  defp execute_trigger(id, now) do
    # we fetch the trigger and immediately update the execution value
    # to avoid other process, unlikely to happen, but might
    trigger = Repo.get!(Trigger, id)

    if is_nil(trigger.last_trigger_at) or
         Date.diff(DateTime.to_date(trigger.last_trigger_at), DateTime.to_date(now)) < 0 do
      Logger.info("executing trigger: #{trigger.name} for org_id: #{trigger.organization_id}")

      trigger
      |> update_next()
      |> start_flow()
    end

    nil
  end

  @spec update_next(Trigger.t()) :: Trigger.t()
  defp update_next(%Trigger{is_repeating: false} = trigger) do
    Logger.info(
      "updating trigger: #{trigger.name} of org_id: #{trigger.organization_id} as inactive"
    )

    {:ok, trigger} =
      Trigger.update_trigger(
        trigger,
        %{
          is_active: false,
          start_at: trigger.start_at,
          flow_id: trigger.flow_id,
          organization_id: trigger.organization_id,
          name: trigger.name
        }
      )

    trigger
  end

  defp update_next(trigger) do
    next_trigger_at = Helper.compute_next(trigger)

    Logger.info(
      "updating next trigger time for trigger: #{trigger.name} of org_id: #{trigger.organization_id} with time #{next_trigger_at}"
    )

    {next_trigger_at, is_active} =
      if Date.compare(DateTime.to_date(next_trigger_at), trigger.end_date) == :lt,
        do: {next_trigger_at, true},
        else: {nil, false}

    attrs = %{
      # we keep the time component constant
      start_at: trigger.start_at,
      last_trigger_at: trigger.next_trigger_at,
      next_trigger_at: next_trigger_at,
      flow_id: trigger.flow_id,
      organization_id: trigger.organization_id,
      is_active: is_active,
      name: trigger.name
    }

    {:ok, trigger} = Trigger.update_trigger(trigger, attrs)

    with true <- trigger.is_active,
         false <- is_nil(trigger.next_trigger_at),
         :gt <- DateTime.compare(DateTime.utc_now(), trigger.next_trigger_at) do
      update_next(trigger)
    else
      _ ->
        trigger
    end
  end

  @spec start_flow(Trigger.t()) :: any
  defp start_flow(trigger) do
    if Glific.Clients.trigger_condition(trigger),
      do: do_start_flow(trigger)
  end

  @spec do_start_flow(Trigger.t()) :: any
  defp do_start_flow(trigger) do
    flow = Flows.get_flow!(trigger.flow_id)

    Logger.info(
      "Starting flow: #{flow.name} for trigger: #{trigger.name} of org_id: #{trigger.organization_id} with time #{trigger.next_trigger_at}"
    )

    if !is_nil(trigger.group_id) do
      group = Groups.get_group!(trigger.group_id)
      Flows.start_group_flow(flow, group)
    end
  end
end
