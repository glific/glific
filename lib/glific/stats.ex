defmodule Glific.Stats do
  @moduledoc """
  The stats manager and API to interface with the stat sub-system
  """

  import Ecto.Query, warn: false

  use Publicist

  alias Glific.{
    BigQuery.BigQueryWorker,
    Flows.FlowContext,
    Messages.Message,
    Partners,
    Partners.Saas,
    Repo,
    Stats.Stat,
    Users.User
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
  def list_stats(args) do
    Repo.list_filter(args, Stat, &Repo.opts_with_inserted_at/2, &filter_with/2)
  end

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

  @doc """
  Top level function to generate stats for all active organizations
  by default. Can control behavior by setting function parameters
  """
  @spec generate_stats(list, boolean, Keyword.t()) :: :ok
  def generate_stats(list \\ [], recent \\ true, opts \\ []) do
    org_id_list = Partners.org_id_list(list, recent)

    # org_id_list can be empty here, if so we return an empty map
    if org_id_list == [],
      do: nil,
      else: do_generate_stats(org_id_list, opts)

    # Lets force push this to the BQ SaaS monitoring storage everytime we generate
    # stats so, we get it soon
    BigQueryWorker.perform_periodic(Saas.organization_id())
  end

  @spec do_generate_stats(list, Keyword.t()) :: nil
  defp do_generate_stats(org_id_list, opts) do
    # lets shift the time by an hour if we are in charge of generating it
    # since this is when the cron job is triggered, in the next hour
    time = Keyword.get(opts, :time, Timex.shift(DateTime.utc_now(), hours: -1))

    opts =
      opts
      |> Keyword.put(:time, time)
      |> Keyword.put(:date, DateTime.to_date(time))

    rows =
      %{}
      |> get_hourly_stats(org_id_list, opts)
      |> get_daily_stats(org_id_list, opts)
      |> get_weekly_stats(org_id_list, opts)
      |> get_monthly_stats(org_id_list, opts)
      |> reject_empty()

    Repo.insert_all(Stat, rows)
    nil
  end

  @spec is_empty?(map()) :: boolean
  defp is_empty?(stat) do
    keys = [
      :contacts,
      :active,
      :optin,
      :optout,
      :messages,
      :inbound,
      :outbound,
      :hsm,
      :flows_started,
      :flows_completed
    ]

    Enum.all?(keys, fn k -> Map.get(stat, k) == 0 end)
  end

  @doc false
  @spec reject_empty(map()) :: list()
  def reject_empty(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_empty?(v) end)
    |> Enum.into(%{})
    |> Map.values()
  end

  @spec is_daily?(DateTime.t()) :: boolean
  defp is_daily?(time), do: time.hour == 23

  @spec is_weekly?(DateTime.t(), Date.t()) :: boolean
  defp is_weekly?(time, date) do
    is_daily?(time) &&
      Date.day_of_week(date) == 7
  end

  @spec is_monthly?(DateTime.t(), Date.t()) :: boolean
  defp is_monthly?(time, date) do
    is_daily?(time) && time.day == Date.days_in_month(date)
  end

  @spec empty_stats(map(), list(), tuple()) :: map()
  defp empty_stats(stats, org_id_list, period_date) do
    {period, date} = period_date

    Enum.reduce(
      org_id_list,
      stats,
      fn id, acc ->
        Map.put(acc, {period_date, id}, empty_stat(date, id, period))
      end
    )
  end

  @spec empty_stat(Date.t() | DateTime.t(), non_neg_integer, atom()) :: map()
  defp empty_stat(date, organization_id, period) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

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
      users: 0,
      period: Atom.to_string(period),
      date: if(period == :hour, do: DateTime.to_date(date), else: date),
      hour: if(period == :hour, do: date.hour, else: 0),
      organization_id: organization_id,
      inserted_at: now,
      updated_at: now
    }
  end

  @spec add(map(), tuple(), atom(), non_neg_integer) :: map()
  defp add(result, period_org, key, value) do
    result
    |> Map.put(period_org, Map.put(result[period_org], key, value))
  end

  @spec make_result(map(), Ecto.Query.t(), tuple(), atom()) :: map()
  defp make_result(result, query, period_date, key) do
    query
    |> Repo.all(skip_organization_id: true, timeout: 60_000)
    |> Enum.reduce(
      result,
      fn [cnt, org_id], result -> add(result, {period_date, org_id}, key, cnt) end
    )
  end

  @spec get_periodic_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_periodic_stats(stats, org_id_list, {period_date, start, finish}) do
    stats
    |> empty_stats(org_id_list, period_date)
    |> get_contact_stats(org_id_list, {period_date, start, finish})
    |> get_message_stats(org_id_list, {period_date, start, finish})
    |> get_flow_stats(org_id_list, {period_date, start, finish})
    |> get_user_stats(org_id_list, {period_date, start, finish})
  end

  @spec get_hourly_stats(map(), list(), Keyword.t()) :: map()
  defp get_hourly_stats(stats, org_id_list, opts) do
    # check if we should emit hourly stats
    if Keyword.get(opts, :hour, true) do
      time = Keyword.get(opts, :time)
      start = %{time | minute: 0, second: 0}
      finish = %{time | minute: 59, second: 59}

      stats
      |> get_periodic_stats(org_id_list, {{:hour, start}, start, finish})
    else
      stats
    end
  end

  @doc false
  @spec get_daily_stats(map(), list(), Keyword.t()) :: map()
  def get_daily_stats(stats, org_id_list, opts) do
    time = Keyword.get(opts, :time)
    date = Keyword.get(opts, :date, DateTime.to_date(time))

    if Keyword.get(opts, :day, true) && is_daily?(time) do
      start = Timex.beginning_of_day(time)
      finish = Timex.end_of_day(time)

      stats
      |> get_periodic_stats(org_id_list, {{:day, date}, start, finish})
    else
      stats
    end
  end

  @doc false
  @spec get_weekly_stats(map(), list(), Keyword.t()) :: map()
  def get_weekly_stats(stats, org_id_list, opts) do
    time = Keyword.get(opts, :time)
    date = Keyword.get(opts, :date, DateTime.to_date(time))

    if Keyword.get(opts, :week, true) && is_weekly?(time, date) do
      start = Timex.beginning_of_week(time)
      finish = Timex.end_of_week(time)
      summary = Keyword.get(opts, :summary, true)

      if(summary,
        do:
          get_periodic_stats(
            stats,
            org_id_list,
            {{:summary, DateTime.to_date(start)}, start, finish}
          ),
        else: stats
      )
      |> get_periodic_stats(org_id_list, {{:week, DateTime.to_date(start)}, start, finish})
    else
      stats
    end
  end

  @doc false
  @spec get_one_month(String.t()) :: nil
  def get_one_month(month) do
    org_id_list = Partners.org_id_list([], false)
    {:ok, time, _} = DateTime.from_iso8601("2021-#{month}-01 00:00:05Z")
    time = Timex.shift(time, hours: -1)

    opts =
      [month: true]
      |> Keyword.put(:time, time)
      |> Keyword.put(:date, DateTime.to_date(time))

    rows =
      %{}
      |> get_monthly_stats(org_id_list, opts)
      |> reject_empty()

    Repo.insert_all(Stat, rows)

    # Lets force push this to the BQ SaaS monitoring storage everytime we generate
    # stats so, we get it soon
    BigQueryWorker.perform_periodic(Saas.organization_id())

    nil
  end

  @doc false
  @spec get_monthly_stats(map(), list(), Keyword.t()) :: map()
  def get_monthly_stats(stats, org_id_list, opts) do
    time = Keyword.get(opts, :time)
    date = Keyword.get(opts, :date, DateTime.to_date(time))

    if Keyword.get(opts, :month, true) && is_monthly?(time, date) do
      start = Timex.beginning_of_month(time)
      finish = Timex.end_of_month(time)
      summary = Keyword.get(opts, :summary, true)

      if(summary,
        do:
          get_periodic_stats(
            stats,
            org_id_list,
            {{:summary, DateTime.to_date(start)}, start, finish}
          ),
        else: stats
      )
      |> get_periodic_stats(org_id_list, {{:month, DateTime.to_date(start)}, start, finish})
    else
      stats
    end
  end

  @spec get_contact_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_contact_stats(stats, org_id_list, {period_date, start, finish}) do
    query = Partners.contact_organization_query(org_id_list)

    {period, _date} = period_date

    time_query =
      if period == :summary,
        do: query,
        else:
          query
          |> where([c], c.last_message_at >= ^start)
          |> where([c], c.last_message_at <= ^finish)

    optin = time_query |> where([c], not is_nil(c.optin_time))
    optout = time_query |> where([c], not is_nil(c.optout_time))

    # dont generate summary contact stats for hourly snapshots
    if(period == :hour, do: stats, else: make_result(stats, query, period_date, :contacts))
    |> make_result(time_query, period_date, :active)
    |> make_result(optin, period_date, :optin)
    |> make_result(optout, period_date, :optout)
  end

  @spec get_message_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_message_stats(stats, org_id_list, {period_date, start, finish}) do
    query =
      Message
      |> where([m], m.organization_id in ^org_id_list)
      |> group_by([m], m.organization_id)
      |> select([m], [count(m.id), m.organization_id])

    {period, _date} = period_date

    time_query =
      if period == :summary,
        do: query,
        else:
          query
          |> where([m], m.inserted_at >= ^start)
          |> where([m], m.inserted_at <= ^finish)

    inbound = time_query |> where([m], m.flow == :inbound)
    outbound = time_query |> where([m], m.flow == :outbound)
    hsm = time_query |> where([m], m.is_hsm == true)

    stats
    |> make_result(time_query, period_date, :messages)
    |> make_result(inbound, period_date, :inbound)
    |> make_result(outbound, period_date, :outbound)
    |> make_result(hsm, period_date, :hsm)
  end

  @spec get_flow_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_flow_stats(stats, _org_id_list, {{:summary, _}, _start, _finish}), do: stats

  defp get_flow_stats(stats, org_id_list, {period_date, start, finish}) do
    query =
      FlowContext
      |> where([fc], fc.organization_id in ^org_id_list)
      |> group_by([fc], fc.organization_id)
      |> select([fc], [count(fc.id), fc.organization_id])

    flows_started =
      query
      |> where([fc], fc.inserted_at >= ^start)
      |> where([fc], fc.inserted_at <= ^finish)

    flows_completed =
      query
      |> where([fc], fc.completed_at >= ^start)
      |> where([fc], fc.completed_at <= ^finish)

    stats
    |> make_result(flows_started, period_date, :flows_started)
    |> make_result(flows_completed, period_date, :flows_completed)
  end

  @spec get_user_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_user_stats(stats, org_id_list, {period_date, start, finish}) do
    query =
      User
      |> where([u], u.organization_id in ^org_id_list)
      |> group_by([u], u.id)
      |> select([u], [count(u.id), u.organization_id])

    {period, _date} = period_date

    time_query =
      if period == :summary,
        do: query,
        else:
          query
          |> where([u], u.last_login_at >= ^start)
          |> where([u], u.last_login_at <= ^finish)

    stats
    |> make_result(time_query, period_date, :users)
  end

  @doc """
  Get the details of the usage for this organization, from start_date to end_date both inclusive
  """
  @spec usage(non_neg_integer, Date.t(), Date.t()) :: %{atom => pos_integer} | nil
  def usage(organization_id, start_date, end_date) do
    Stat
    |> where([s], s.organization_id == ^organization_id)
    |> where([s], s.period == "day")
    |> where([s], s.date >= ^start_date and s.date <= ^end_date)
    |> group_by([s], s.organization_id)
    |> select([s], %{
      messages: sum(s.messages),
      users: max(s.users)
    })
    |> Repo.one()
  end
end
