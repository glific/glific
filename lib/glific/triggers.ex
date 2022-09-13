defmodule Glific.Triggers do
  @moduledoc """
  The trigger manager for all the trigger system that starts flows
  within Glific
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    AccessControl,
    AccessControl.TriggerRole,
    Flows,
    Flows.Flow,
    Groups,
    Partners,
    Repo,
    Triggers,
    Triggers.Helper,
    Triggers.Trigger
  }

  @max_trigger_limit 1000

  @doc """
  Periodic call to execute the triggers outstanding for the day
  """
  @spec execute_triggers(non_neg_integer(), DateTime.t()) :: [Trigger.t()]
  def execute_triggers(organization_id, now \\ DateTime.utc_now()) do
    # triggers can be executed multiple times a day based on frequency
    now = Timex.shift(now, minutes: 1)

    Trigger
    |> where([t], t.organization_id == ^organization_id and t.is_active == true)
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

    cond do
      is_nil(trigger.last_trigger_at) or
          Date.diff(DateTime.to_date(trigger.last_trigger_at), DateTime.to_date(now)) < 0 ->
        do_execute_trigger(trigger)

      trigger.frequency == ["hourly"] and trigger.last_trigger_at.hour < now.hour ->
        do_execute_trigger(trigger)
    end

    nil
  end

  defp do_execute_trigger(trigger) do
    Logger.info("executing trigger: #{trigger.name} for org_id: #{trigger.organization_id}")

    trigger
    |> update_next()
    |> start_flow()
  end

  @spec update_next(Trigger.t()) :: Trigger.t()
  defp update_next(%Trigger{is_repeating: false} = trigger) do
    Logger.info(
      "updating trigger: #{trigger.name} of org_id: #{trigger.organization_id} as inactive"
    )

    {:ok, trigger} =
      Triggers.update_trigger(
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

    {:ok, trigger} = Triggers.update_trigger(trigger, attrs)

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

  @doc """
  Creates a trigger.

  ## Examples

      iex> create_trigger(%{field: value})
      {:ok, %Trigger{}}

      iex> create_trigger(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_trigger(map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger(attrs) do
    with {:ok, valid_attrs} <- validate_new_trigger(attrs),
         {:ok, trigger} <-
           %Trigger{}
           |> Trigger.changeset(valid_attrs)
           |> Repo.insert() do
      if Map.has_key?(attrs, :add_role_ids),
        do: update_trigger_roles(attrs, trigger),
        else: {:ok, trigger}
    end
  end

  @spec validate_new_trigger(map()) :: {:ok, map()} | {:error, map()}
  defp validate_new_trigger(attrs) do
    attrs
    |> Map.put_new(:start_at, nil)
    |> fix_attrs()
    |> validate_frequency
  end

  defp validate_frequency(%{frequency: frequency} = attrs)
       when frequency in [["daily"], ["none"]] do
    {:ok, Map.merge(attrs, %{days: [], hours: []})}
  end

  defp validate_frequency(%{frequency: ["hourly"], hours: hours} = attrs) when hours != [] do
    valid_hours = Enum.reduce(0..23, [], fn hour, acc -> acc ++ [hour] end)

    Enum.all?(hours, fn hour -> hour in valid_hours end)
    |> case do
      true -> {:ok, Map.put(attrs, :days, [])}
      false -> {:error, "Cannot create Trigger with invalid hours"}
    end
  end

  defp validate_frequency(%{frequency: ["weekly"], days: days} = attrs) when days != [] do
    valid_days = Enum.reduce(1..7, [], fn day, acc -> acc ++ [day] end)

    Enum.all?(days, fn day -> day in valid_days end)
    |> case do
      true -> {:ok, Map.put(attrs, :hours, [])}
      false -> {:error, "Cannot create Trigger with invalid days"}
    end
  end

  defp validate_frequency(%{frequency: ["monthly"], days: days} = attrs) when days != [] do
    valid_days = Enum.reduce(1..31, [], fn day, acc -> acc ++ [day] end)

    Enum.all?(days, fn day -> day in valid_days end)
    |> case do
      true -> {:ok, Map.put(attrs, :hours, [])}
      false -> {:error, "Cannot create Trigger with invalid days"}
    end
  end

  defp validate_frequency(_attrs),
    do: {:error, "Cannot create Trigger with invalid days or hours"}

  @spec update_trigger_roles(map(), Trigger.t()) :: {:ok, Trigger.t()}
  defp update_trigger_roles(attrs, trigger) do
    %{access_controls: access_controls} =
      attrs
      |> Map.put(:trigger_id, trigger.id)
      |> TriggerRole.update_trigger_roles()

    trigger
    |> Map.put(:roles, access_controls)
    |> then(&{:ok, &1})
  end

  @doc """
  Updates a trigger.

  ## Examples

      iex> update_trigger(trigger, %{field: new_value})
      {:ok, %Trigger{}}

      iex> update_trigger(trigger, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_trigger(Trigger.t(), map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger(%Trigger{} = trigger, attrs) do
    with {:ok, updated_trigger} <-
           trigger
           |> Trigger.changeset(fix_attrs(Map.put_new(attrs, :start_at, nil)))
           |> Repo.update() do
      if Map.has_key?(attrs, :add_role_ids),
        do: update_trigger_roles(attrs, updated_trigger),
        else: {:ok, updated_trigger}
    end
  end

  @doc """
  Gets a single trigger.

  Raises `Ecto.NoResultsError` if the Trigger does not exist.

  ## Examples

      iex> get_trigger!(123)
      %Trigger{}

      iex> get_trigger!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_trigger!(integer) :: Trigger.t()
  def get_trigger!(id), do: Repo.get!(Trigger, id)

  @doc """
  Returns the list of triggers filtered by args

  ## Examples

      iex> list_triggers()
      [%Trigger{}, ...]

  """
  @spec list_triggers(map()) :: [Trigger.t()]
  def list_triggers(args) do
    Repo.list_filter_query(args, Trigger, &Repo.opts_with_name/2, &filter_with/2)
    |> AccessControl.check_access(:trigger)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:flow, flow}, query ->
        from q in query,
          join: c in assoc(q, :flow),
          where: ilike(c.name, ^"%#{flow}%")

      {:group, group}, query ->
        from q in query,
          join: g in assoc(q, :group),
          where: ilike(g.label, ^"%#{group}%")

      _, query ->
        query
    end)
  end

  @doc false
  @spec delete_trigger(Trigger.t()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def delete_trigger(%Trigger{} = trigger) do
    trigger
    |> Trigger.changeset(%{})
    |> Repo.delete()
  end

  @doc """
  Return the count of triggers, using the same filter as list_triggers
  """
  @spec count_triggers(map()) :: integer
  def count_triggers(args),
    do: Repo.count_filter(args, Trigger, &Repo.filter_with/2)

  @spec start_at(map()) :: DateTime.t()
  defp start_at(%{start_at: nil} = attrs), do: DateTime.new!(attrs.start_date, attrs.start_time)
  defp start_at(%{start_at: start_at} = _attrs), do: start_at

  @spec get_name(map()) :: String.t()
  defp get_name(%{name: name} = _attrs) when not is_nil(name), do: name

  defp get_name(attrs) do
    with {:ok, flow} <-
           Repo.fetch_by(Flow, %{id: attrs.flow_id, organization_id: attrs.organization_id}) do
      tz = Partners.organization_timezone(attrs.organization_id)
      time = DateTime.new!(attrs.start_date, attrs.start_time)
      org_time = DateTime.shift_zone!(time, tz)
      {:ok, date} = Timex.format(org_time, "_{D}/{M}/{YYYY}_{h12}:{0m}{AM}")
      "#{flow.name}#{date}"
    end
  end

  defp get_next_trigger_at(%{next_trigger_at: next_trigger_at} = _attrs, _start_at)
       when not is_nil(next_trigger_at),
       do: next_trigger_at

  defp get_next_trigger_at(_attrs, start_at), do: start_at

  @spec fix_attrs(map()) :: map()
  defp fix_attrs(attrs) do
    # compute start_at if not set
    start_at = start_at(attrs)

    attrs
    |> Map.put(:start_at, start_at)
    |> Map.put(:name, get_name(attrs))

    # set the last_trigger_at value to nil whenever trigger is updated or new trigger is created
    |> Map.put(:last_trigger_at, Map.get(attrs, :last_trigger_at, nil))

    # set the initial value of the next firing of the trigger
    |> Map.put(:next_trigger_at, get_next_trigger_at(attrs, start_at))
  end
end
