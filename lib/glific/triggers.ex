defmodule Glific.Triggers do
  @moduledoc """
  The trigger manager for all the trigger system that starts flows
  within Glific
  """
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
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
  @spec execute_triggers(DateTime.t()) :: [Trigger.t()]
  def execute_triggers(now \\ DateTime.utc_now()) do
    # triggers are executed at most once per day
    %Trigger{}
    |> where([t], t.is_active == true)
    |> where([t], fragment("date_trunc('day', t.last_trigger_at) != CURRENT_DATE"))
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

    if Date.diff(DateTime.to_date(trigger.last_trigger_at), DateTime.to_date(now)) < 0 do
      trigger
      |> update_next()
      |> start_flow()
    end

    nil
  end

  @spec update_next(Trigger.t()) :: Trigger.t()
  defp update_next(%Trigger{is_repeating: false} = trigger) do
    {:ok, trigger} =
      Trigger.update_trigger(
        trigger,
        %{is_active: false}
      )

    trigger
  end

  defp update_next(trigger) do
    next_trigger_at = Helper.compute_next(trigger)

    {next_trigger_at, is_active} =
      if DateTime.compare(next_trigger_at, trigger.end_at) == :gt,
        do: {nil, false},
        else: {next_trigger_at, true}

    attrs = %{
      # we keep the time component constant
      last_trigger_at: trigger.next_trigger_at,
      next_trigger_at: next_trigger_at,
      is_active: is_active
    }

    {:ok, trigger} = Trigger.update_trigger(trigger, attrs)
    trigger
  end

  @spec start_flow(Trigger.t()) :: nil
  defp start_flow(trigger) do
    flow = Flows.get_flow!(trigger.flow_id)

    if !is_nil(trigger.contact_id) do
      contact = Contacts.get_contact!(trigger.contact_id)
      Flows.start_contact_flow(flow, contact)
    end

    if !is_nil(trigger.group_id) do
      group = Groups.get_group!(trigger.group_id)
      Flows.start_group_flow(flow, group)
    end

    nil
  end
end
