defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.FlowContext,
    Flows.MessageBroadcast,
    Messages.Message,
    Notifications.Notification,
    Partners,
    Repo,
    Stats.Stat
  }

  @doc false
  @spec get_kpi(atom(), non_neg_integer(), [{atom(), any()}]) :: integer()
  def get_kpi(kpi, org_id, opts \\ []) do
    Repo.put_process_state(org_id)

    get_count_query(kpi)
    |> add_timestamps(kpi, opts)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
    |> hd
  end

  @doc false
  @spec kpi_list() :: list()
  def kpi_list do
    [
      :conversation_count,
      :active_flow_count,
      :flows_started,
      :flows_completed,
      :valid_contact_count,
      :invalid_contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count,
      :non_opted_contacts_count,
      :monthly_error_count,
      :inbound_messages_count,
      :outbound_messages_count,
      :hsm_messages_count
    ]
  end

  @spec get_count_query(atom()) :: Ecto.Query.t()
  defp get_count_query(:valid_contact_count) do
    Contact
    |> select([q], count(q.id))
    |> where([q], q.status == "valid")
  end

  defp get_count_query(:invalid_contact_count) do
    Contact
    |> select([q], count(q.id))
    |> where([q], q.status == "invalid")
  end

  defp get_count_query(:opted_in_contacts_count) do
    Contact
    |> select([q], count(q.id))
    |> where([q], not is_nil(q.optin_time))
  end

  defp get_count_query(:opted_out_contacts_count) do
    Contact
    |> select([q], count(q.id))
    |> where([q], not is_nil(q.optout_time))
  end

  defp get_count_query(:non_opted_contacts_count) do
    Contact
    |> select([q], count(q.id))
    |> where([q], is_nil(q.optin_time))
    |> where([q], is_nil(q.optout_time))
  end

  defp get_count_query(:bsp_status) do
    Contact
    |> group_by([c], c.bsp_status)
    |> select([c], [c.bsp_status, count(c.id)])
  end

  defp get_count_query(:monthly_error_count) do
    Message
    |> select([q], count(q.id))
    |> where([q], fragment("? != '{}'", q.errors))
  end

  defp get_count_query(:critical_notification_count) do
    Notification
    |> select([q], count(q.id))
    |> where([q], q.severity == "Critical")
  end

  defp get_count_query(:warning_notification_count) do
    Notification
    |> select([q], count(q.id))
    |> where([q], q.severity == "Warning")
  end

  defp get_count_query(:information_notification_count) do
    Notification
    |> select([q], count(q.id))
    |> where([q], q.severity == "Information")
  end

  defp get_count_query(:active_flow_count) do
    FlowContext
    |> select([q], count(q.id))
    |> where([q], is_nil(q.completed_at))
  end

  defp get_count_query(:inbound_messages_count), do: select(Stat, [q], sum(q.inbound))

  defp get_count_query(:outbound_messages_count), do: select(Stat, [q], sum(q.outbound))

  defp get_count_query(:hsm_messages_count), do: select(Stat, [q], sum(q.hsm))

  defp get_count_query(:flows_started), do: select(Stat, [q], sum(q.flows_started))

  defp get_count_query(:flows_completed), do: select(Stat, [q], sum(q.flows_completed))

  defp get_count_query(:conversation_count), do: select(Stat, [q], sum(q.conversations))

  @spec get_day_range(String.t()) :: tuple()
  defp get_day_range(duration) do
    day = shifted_time(NaiveDateTime.utc_now(), -1) |> NaiveDateTime.to_date()
    last_7 = shifted_time(NaiveDateTime.utc_now(), -7) |> NaiveDateTime.to_date()

    case duration do
      "MONTHLY" ->
        {"month", Date.beginning_of_month(day), Date.end_of_month(day)}

      "WEEKLY" ->
        {"day", last_7, day}

      "DAILY" ->
        {"day", day, day}
    end
  end

  @spec add_timestamps(Ecto.Query.t(), atom(), [{atom(), any()}]) :: Ecto.Query.t()
  defp add_timestamps(query, kpi, _opts)
       when kpi in [
              :critical_notification_count,
              :warning_notification_count,
              :information_notification_count,
              :monthly_error_count,
              :active_flow_count
            ] do
    date = Timex.beginning_of_month(DateTime.utc_now())

    query
    |> where([q], q.inserted_at >= ^date)
  end

  defp add_timestamps(query, kpi, opts)
       when kpi in [
              :outbound_messages_count,
              :hsm_messages_count,
              :inbound_messages_count,
              :flows_started,
              :flows_completed,
              :conversation_count
            ] do
    duration = Keyword.get(opts, :duration, "WEEKLY")

    {period, start_day, end_day} = get_day_range(duration)

    query
    |> where([q], q.period == ^period)
    |> where([q], q.date >= ^start_day)
    |> where([q], q.date <= ^end_day)
  end

  defp add_timestamps(query, _kpi, _opts), do: query

  @doc """
  Returns last 7 days kpi data map with keys as date AND value as count

    ## Examples
    iex> Glific.Reports.get_kpi_data(1, "messages_conversations")
    iex> Glific.Reports.get_kpi_data(1, "contacts")
      %{
        "04-01-2023" => 0,
        "05-01-2023" => 0,
        "06-01-2023" => 0,
        "07-01-2023" => 0,
        "08-01-2023" => 2,
        "09-01-2023" => 3,
        "10-01-2023" => 10
      }

  """
  @spec get_kpi_data(non_neg_integer(), String.t(), map()) :: list()
  def get_kpi_data(org_id, table, date_range) do
    presets = get_date_preset(date_range)
    Repo.put_process_state(org_id)

    query_data =
      get_kpi_query(presets, table, org_id)
      |> Repo.all()

    Enum.reduce(query_data, presets.date_map, fn %{count: count, date: date}, acc ->
      Map.put(acc, date, count)
    end)
    |> Enum.map(fn {date, v} -> {Timex.format!(date, "{0D}-{0M}-{YYYY}"), v} end)
    |> Enum.sort()
  end

  @spec get_kpi_query(map(), String.t(), non_neg_integer()) :: String.t()
  defp get_kpi_query(presets, "stats", org_id) do
    start_date = presets.start_day |> Timex.to_date()
    end_date = presets.end_day |> Timex.to_date()
    from s in "stats",
    where: s.period == "day" and s.date >= ^start_date and s.date <= ^end_date and s.organization_id == ^org_id,
    select: %{date: s.date, count: s.conversations}
  end

  defp get_kpi_query(presets, table, org_id) do
    from(
      t in table,
      where:
        t.inserted_at > ^presets.start_day and t.inserted_at <= ^presets.end_day and
          t.organization_id == ^org_id,
      group_by: fragment("date_trunc('day', ?)", t.inserted_at),
      select: %{date: fragment("date_trunc('day', ?)", t.inserted_at), count: count(t.id)}
    )
  end

  @doc false
  @spec get_messages_data(non_neg_integer()) :: map()
  def get_messages_data(org_id) do
    timezone = Partners.organization_timezone(org_id)
    Repo.put_process_state(org_id)

    Stat
    |> select([q], %{
      hour: q.hour,
      inbound: sum(q.inbound),
      outbound: sum(q.outbound)
    })
    |> group_by([q], q.hour)
    |> where([q], q.organization_id == ^org_id)
    |> where([q], q.period == "hour")
    |> Repo.all()
    |> Enum.reduce(%{}, fn hourly_stat, acc ->
      time =
        DateTime.utc_now()
        |> Timex.shift(days: -1)
        |> Timex.beginning_of_day()
        |> Timex.Timezone.convert(timezone)
        |> Timex.shift(hours: hourly_stat.hour)

      Map.put(acc, Timex.format!(time, "{0h12}:{0m}{AM}"), Map.delete(hourly_stat, :hour))
    end)
  end

  @doc """
    gets data for the broadcast table
  """
  @spec get_broadcast_data(non_neg_integer()) :: list()
  def get_broadcast_data(org_id) do
    timezone = Partners.organization_timezone(org_id)

    MessageBroadcast
    |> join(:inner, [mb], flow in assoc(mb, :flow))
    |> join(:inner, [mb, flow], group in assoc(mb, :group))
    |> where([mb], mb.organization_id == ^org_id)
    |> select([mb, flow, group], %{
      flow_name: flow.name,
      group_label: group.label,
      started_at: mb.started_at,
      completed_at: mb.completed_at
    })
    |> order_by([mb], desc: mb.inserted_at)
    |> limit(25)
    |> Repo.all()
    |> Enum.reduce([], fn message_broadcast, acc ->
      started_at =
        message_broadcast.started_at
        |> Timex.Timezone.convert(timezone)
        |> Timex.format!("%d-%m-%Y %I:%M %p", :strftime)

      completed_at =
        if is_nil(message_broadcast.completed_at),
          do: "Not Completed Yet",
          else:
            message_broadcast.completed_at
            |> Timex.Timezone.convert(timezone)
            |> Timex.format!("%d-%m-%Y %I:%M %p", :strftime)

      acc ++
        [[message_broadcast.flow_name, message_broadcast.group_label, started_at, completed_at]]
    end)
  end

  @doc false
  @spec get_contact_data(non_neg_integer()) :: list()
  def get_contact_data(org_id) do
    get_count_query(:bsp_status)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
  end

  @spec get_date_preset(map()) :: map()
  def get_date_preset(date_range) do
    diff = NaiveDateTime.diff(date_range.end_day, date_range.start_day, :day)

    date_map = Enum.into(0..diff, %{}, fn day ->
      {date_range.start_day |> NaiveDateTime.add(day, :day), 0}
    end)

    %{
      start_day: date_range.start_day,
      date_map: date_map,
      end_day: date_range.end_day
    }
  end

  @doc false
  @spec get_export_data(atom(), non_neg_integer()) :: list()
  def get_export_data(chart, org_id) do
    get_export_query(chart)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
  end

  defp get_export_query(:optin) do
    Contact
    |> select([q], [q.id, q.name, q.phone, q.optin_status])
  end

  defp get_export_query(:notifications) do
    Notification
    |> select([q], [q.id, q.category, q.severity])
  end

  defp get_export_query(:messages) do
    Stat
    |> select([q], [q.id, q.inbound, q.outbound])
  end

  defp get_export_query(:contact_type) do
    Contact
    |> select([q], [q.id, q.name, q.phone, q.bsp_status])
  end

  @doc """
  Returns NaiveDatetime shifted by no. of days
  """
  @spec shifted_time(NaiveDateTime.t(), integer()) :: NaiveDateTime.t()
  def shifted_time(time, days) do
    time
    |> Timex.beginning_of_day()
    |> Timex.shift(days: days)
  end
end
