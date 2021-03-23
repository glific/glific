defmodule Glific.Stats do
  @moduledoc """
  The stats manager and API to interface with the stat sub-system
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Repo,
    Stats.Stat
  }

  @doc """
  Create a Stat
  """
  @spec create_stat(map()) :: {:ok, Stat.t()} | {:error, Ecto.Changeset.t()}
  def create_stat(attrs \\ %{}) do
    %Stat{}
    |> Stat.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Stat
  """
  @spec update_stat(Stat.t(), map()) ::
          {:ok, Stat.t()} | {:error, Ecto.Changeset.t()}
  def update_stat(stat, attrs) do
    stat
    |> Stat.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of stats.
  Since this is very basic and only listing funcatinality we added the status filter like this.
  In future we will put the status as virtual filed in the stats itself.
  """
  @spec list_stats(map()) :: list()
  def list_stats(args),
    do: Repo.list_filter(args, Stat, &Repo.opts_with_inserted_at/2, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to stats only.
    # We might want to move them in the repo in the future.

    Enum.reduce(filter, query, fn
      {:period, period}, query ->
        from q in query, where: q.period == ^period

      {:hour, hour}, query ->
        from q in query, where: q.hour == ^hour

      {:date, date}, query ->
        from q in query, where: q.date == ^date

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of stats, using the same filter as list_stats
  """
  @spec count_stats(map()) :: integer
  def count_stats(args),
    do: Repo.count_filter(args, Stat, &filter_with/2)

  @spec generate_stats(list, boolean, DateTime.t()) :: nil
  def generate_stats(list \\ [], recent \\ true, time \\ DateTime.utc_now()) do
    org_id_list = Partners.org_id_list(list, recent)

    # org_id_list can be empty here, if so we return an empty map
    if org_id_list == [],
      do: nil,
      else: do_generate_stats(org_id_list, time)
  end

  @spec do_generate_stats(list, DateTime.t()) :: nil
  defp do_generate_stats(org_id_list, time) do
    # lets shift the time by an hour, since thats what we are interested in (the hour/day/week/month just completed)
    time = time |> Timex.shift(hours: -1)
    date = DateTime.to_date(time)

    org_id_list
    |> empty_results(time, date)
    |> get_hourly_stats(org_id_list, time)
    |> get_daily_stats(org_id_list, time)
    |> get_weekly_stats(org_id_list, time)
    |> get_monthly_stats(org_id_list, time)
  end

  @spec is_daily?(DateTime.t()) :: boolean
  defp is_daily?(time), do: time.hour == 23

  @spec is_weekly?(DateTime.t(), Date.t()) :: boolean
  defp is_weekly?(time, date) do
    is_daily?(time) &&
      Date.day_of_week(date) == 7
  end

  @spec is_monthly?(Date.t(), DateTime.t()) :: boolean
  defp is_monthly?(time, date) do
    is_daily?(time) &&
      Date.days_in_month(date) == time.day
  end

  @spec empty_results(list(), DateTime.t(), Date.t()) :: map()
  defp empty_results(org_id_list, time, date) do
    Enum.reduce(
      org_id_list,
      %{},
      fn id, acc ->
        acc
        |> Map.put({:hour, id}, empty_result(time, date, "hour"))
        |> empty_daily_results(time, date, id)
        |> empty_weekly_results(time, date, id)
        |> empty_monthly_results(time, date, id)
      end
    )
  end

  @spec empty_daily_results(map(), DateTime.t(), Date.t(), non_neg_integer()) :: map()
  defp empty_daily_results(stats, time, date, org_id) do
    if is_daily?(time) do
      stats |> Map.put({:day, org_id}, empty_result(time, date, "day"))
    else
      stats
    end
  end

  @spec empty_weekly_results(map(),  Date.t(), DateTime.t(), non_neg_integer()) :: map()
  defp empty_weekly_results(stats, time, date, org_id) do
    if is_weekly?(time, date) do
      stats |> Map.put({:week, org_id}, empty_result(time, Date.beginning_of_week(date), "week"))
    else
      stats
    end
  end

  @spec empty_monthly_results(map(),  Date.t(), DateTime.t(), non_neg_integer()) :: map()
  defp empty_monthly_results(stats, time, date, org_id) do
    if is_monthly?(time, date) do
      stats |> Map.put({:month, org_id}, empty_result(time, Date.beginning_of_month(date), "month"))
    else
      stats
    end
  end

  @spec empty_result(DateTime.t(), Date.t(), String.t()) :: map()
  defp empty_result(time, date, period) do
    %{
      contacts: 0,
      active: 0,
      optin: 0,
      optout: 0,
      messages: 0,
      inbound: 0,
      outbound: 0,
      hsm: 0,
      flows_started: 0,
      flows_completed: 0,
      period: period,
      date: date,
      hour: if(period == "hour", do: time.hour, else: 0)
    }
  end

  @spec add(map(), tuple(), atom(), non_neg_integer) :: map()
  defp add(result, {period_org, org_id}, key, value) do
    result
    |> Map.put(org_id, Map.put(result[period_org], key, value))
  end

  @spec make_result(map(), Ecto.Query.t(), String.t(), atom()) :: map()
  defp make_result(result, query, period, key) do
    query
    |> Repo.all(skip_organization_id: true)
    |> Enum.reduce(
      result,
      fn [cnt, org_id], result -> add(result, {period, org_id}, key, cnt) end
    )
  end

  @spec get_periodic_stats(map(), list(), {atom(), DateTime.t(), DateTime.t()}) :: map()
  defp get_periodic_stats(stats, org_id_list, {period, start, finish}) do
    stats
    |> get_contact_stats(org_id_list, {period, start, finish})
    # |> get_message_stats(org_id_list, {period, start, finish})
    # |> get_flow_stats(org_id_list, {period, start, finish})
  end

  @spec get_hourly_stats(map(), list(), DateTime.t()) :: map()
  defp get_hourly_stats(stats, org_id_list, time) do
    start = %{time | minute: 0, second: 0}
    finish = %{time | minute: 59, second: 59}

    stats
    |> get_periodic_stats(org_id_list, {:hour, start, finish})
  end

  @spec get_daily_stats(map(), list(), DateTime.t()) :: map()
  defp get_daily_stats(stats, org_id_list, time) do
    start = Timex.beginning_of_day(time)
    finish = Timex.end_of_day(time)

    stats
    |> get_periodic_stats(org_id_list, {:day, start, finish})
  end

  defp get_daily_stats(stats, %{hour: hour} = _time, _date) when hour != 23, do: stats

  defp get_daily_stats(_stats, _time, _date) do
  end

  @spec get_weekly_stats(map(), list(), DateTime.t()) :: map()
  defp get_weekly_stats(stats, org_id_list, time) do
    start = Timex.beginning_of_week(time)
    finish = Timex.end_of_week(time)

    stats
    |> get_periodic_stats(org_id_list, {:week, start, finish})
  end

  @spec get_monthly_stats(map(), list(), DateTime.t()) :: map()
  defp get_monthly_stats(stats, org_id_list, time) do
    start = Timex.beginning_of_month(time)
    finish = Timex.end_of_month(time)

    stats
    |> get_periodic_stats(org_id_list, {:week, start, finish})
  end

  @spec get_contact_stats(map(), list(), {atom(), DateTime.t(), DateTime.t()}) :: map()
  defp get_contact_stats(stats, org_id_list, {period, start, finish}) do
    query = Partners.contact_organization_query(org_id_list)

    time_query =
      query
      |> where([c], c.last_message_at >= ^start)
      |> where([c], c.last_message_at <= ^finish)

    optin = time_query |> where([c], not is_nil(c.optin_time))
    optout = time_query |> where([c], not is_nil(c.optout_time))

    stats
    |> make_result(query, period, :contacts)
    |> make_result(time_query, period, :active)
    |> make_result(optin, period, :optin)
    |> make_result(optout, period, :optout)
  end
end
