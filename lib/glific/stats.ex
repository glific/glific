defmodule Glific.Stats do
  @moduledoc """
  The stats manager and API to interface with the stat sub-system
  """

  import Ecto.Query, warn: false

  use Publicist

  alias Glific.{
    BigQuery.BigQueryWorker,
    Communications.Mailer,
    Flows.FlowContext,
    Mails.DashboardMail,
    Messages.Message,
    Messages.MessageConversation,
    Partners,
    Partners.Saas,
    Repo,
    Reports,
    Stats.Stat,
    Users.User
  }

  require Resvg
  alias GlificWeb.StatsLive

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
  Since this is very basic and only listing functionality we added the status filter like this.
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
        from(q in query, where: q.period == ^period)

      {:hour, hour}, query ->
        from(q in query, where: q.hour == ^hour)

      {:date, date}, query ->
        from(q in query, where: q.date == ^date)

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

    # Lets force push this to the BQ SaaS monitoring storage every time we generate
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
      :flows_completed,
      :conversations
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
      updated_at: now,
      conversations: 0
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
    |> Repo.all(skip_organization_id: true, timeout: 120_000)
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
    |> get_conversation_stats(org_id_list, {period_date, start, finish})
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
    {:ok, time, _} = DateTime.from_iso8601("2021-#{month}-01 00:05:00Z")
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

    # Lets force push this to the BQ SaaS monitoring storage every time we generate
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

    # don't generate summary contact stats for hourly snapshots
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

  @spec get_conversation_stats(map(), list(), {tuple(), DateTime.t(), DateTime.t()}) :: map()
  defp get_conversation_stats(stats, org_id_list, {period_date, start, finish}) do
    query =
      MessageConversation
      |> where([c], c.organization_id in ^org_id_list)
      |> group_by([c], c.organization_id)
      |> select([c], [count(c.id), c.organization_id])

    {period, _date} = period_date

    time_query =
      if period == :summary,
        do: query,
        else:
          query
          |> where([c], c.inserted_at >= ^start)
          |> where([c], c.inserted_at <= ^finish)

    stats
    |> make_result(time_query, period_date, :conversations)
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

  @spec clean_data(any()) :: {:safe, [any()]}
  defp clean_data(data)
  when is_binary(data)
  do
    data =  if String.contains?(data, "No data") do
      [
        """
        <svg width="320" height="120" xmlns="http://www.w3.org/2000/svg">
          <text x="160" y="70" font-size="20" text-anchor="middle">No Data</text>
        </svg>
        """
      ]
    else
      [data]
    end

    {:safe, data}
  end

  defp clean_data(svg), do: svg

  @spec load_pie_svg([any()], String.t()) :: String.t()
  defp load_pie_svg(data, title) do
    data
    |> StatsLive.make_pie_chart_dataset()
    |> (&StatsLive.render_pie_chart(title, &1)).()
    |> clean_data()
    |> convert_svg_to_base64()
  end

  @spec load_bar_svg([any()], String.t(), [String.t()]) :: String.t()
  defp load_bar_svg(data, title, opts) do
    data
    |> StatsLive.make_bar_chart_dataset(opts)
    |> (&StatsLive.render_bar_chart(title, &1)).()
    |> clean_data()
    |> convert_svg_to_base64()
  end

  @spec convert_svg_to_base64({atom(), any()}) :: String.t()
  defp convert_svg_to_base64(svg) do
    {:safe, svg_string} = svg

    filename = System.tmp_dir!() <> "/temp.png"

    # Can control the quality of the image by passing width:
    svg_string
    |> List.flatten()
    |> Enum.join()
    |> Resvg.svg_string_to_png(filename, resources_dir: System.tmp_dir!(), width: 1080)

    {:ok, file_content} = File.read(filename)
    base64_data = Base.encode64(file_content)
    File.rm!(filename)

    "data:image/png;base64," <> base64_data
  end

  @spec fetch_inbound_outbound(non_neg_integer(), String.t(), map()) :: [tuple()]
  defp fetch_inbound_outbound(org_id, duration, date_range) do
    inbound = Reports.get_kpi(:inbound_messages_count, org_id, date_range, duration: duration)
    outbound = Reports.get_kpi(:outbound_messages_count, org_id, date_range, duration: duration)

    [
      {"Inbound: #{inbound}", inbound},
      {"Outbound: #{outbound}", outbound}
    ]
  end

  @spec get_day_range(String.t()) :: map()
  defp get_day_range(duration) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1, :day)
    end_day = now |> Timex.end_of_day()

    start_day =
      case duration do
        "MONTHLY" -> now |> Timex.beginning_of_month()
        "WEEKLY" -> now |> NaiveDateTime.add(-6, :day)
        "DAILY" -> now
      end
      |> Timex.beginning_of_day()

    %{start_day: start_day, end_day: end_day}
  end

  @spec get_date_label(String.t()) :: String.t()
  defp get_date_label(duration) do
    %{start_day: from, end_day: till} = get_day_range(duration)
    Timex.format!(from, "{0D}-{0M}-{YYYY}") <> " till " <> Timex.format!(till, "{0D}-{0M}-{YYYY}")
  end

  @doc """
  Sends mail to organization with their stats
  """
  @spec mail_stats(Partners.Organization.t(), String.t()) :: {:ok, term} | {:error, term}
  def mail_stats(org, duration \\ "WEEKLY") do
    contacts = Reports.get_kpi_data(org.id, "contacts", get_day_range("WEEKLY"))
    conversations = Reports.get_kpi_data(org.id, "stats", get_day_range("WEEKLY"))
    optin = StatsLive.fetch_count_data(:optin_chart_data, org.id, get_day_range(duration))
    messages = fetch_inbound_outbound(org.id, duration, get_day_range(duration))

    assigns = %{
      contact_chart_svg: load_bar_svg(contacts, "Contacts", ["Date", "Daily Contacts"]),
      conversation_chart_svg:
        load_bar_svg(conversations, "Conversations", ["Hour", "Daily Conversations"]),
      optin_chart_svg: load_pie_svg(optin, "Contacts Optin Status"),
      message_chart_svg: load_pie_svg(messages, "Messages"),
      duration: duration,
      date_range: get_date_label(duration),
      dashboard_link: "https://#{org.shortcode}.tides.coloredcow.com/",
      parent_org: org.parent_org
    }

    opts = [
      template: "dashboard.html"
    ]

    case DashboardMail.new_mail(org, assigns, opts)
         |> Mailer.send(%{
           category: "dashboard_report",
           organization_id: org.id
         }) do
      {:ok, %{id: _id}} -> {:ok, %{message: "Successfully sent mail to organization"}}
      error -> {:ok, %{message: error}}
    end
  end
end
