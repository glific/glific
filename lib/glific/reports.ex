defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Flows.FlowContext,
    Flows.MessageBroadcast,
    Messages.Message,
    Notifications.Notification,
    Organization,
    Partners,
    Partners.Organization,
    Repo,
    Stats.Stat
  }

  @doc false
  @spec get_kpi(atom(), non_neg_integer(), map(), [{atom(), any()}]) :: integer()
  def get_kpi(kpi, org_id, date_range, opts \\ []) do
    Repo.put_process_state(org_id)

    get_count_query(kpi)
    |> remove_default_contacts(org_id, kpi)
    |> add_timestamps(kpi, opts, date_range)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
    |> hd || 0
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

  @spec remove_default_contacts(Ecto.Query.t(), non_neg_integer(), atom()) :: Ecto.Query.t()
  defp remove_default_contacts(query, org_id, kpi)
       when kpi in [
              :valid_contact_count,
              :invalid_contact_count,
              :opted_in_contacts_count,
              :opted_out_contacts_count,
              :non_opted_contacts_count,
              :bsp_status
            ] do
    org = Partners.get_organization!(org_id)

    query
    |> where([q], not like(q.phone, ^"#{Contacts.simulator_phone_prefix()}%"))
    |> where([q], q.id != ^org.contact_id)
  end

  defp remove_default_contacts(query, _, _), do: query

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

  @spec add_timestamps(Ecto.Query.t(), atom(), [{atom(), any()}], map()) :: Ecto.Query.t()
  defp add_timestamps(query, kpi, _opts, date_range)
       when kpi in [
              :critical_notification_count,
              :warning_notification_count,
              :information_notification_count,
              :monthly_error_count,
              :active_flow_count,
              :valid_contact_count,
              :invalid_contact_count,
              :opted_in_contacts_count,
              :opted_out_contacts_count,
              :non_opted_contacts_count,
              :bsp_status,
              :optin,
              :notifications,
              :contact_type
            ] do
    start_day = date_range.start_day
    end_day = date_range.end_day

    query
    |> where([q], q.inserted_at >= ^start_day)
    |> where([q], q.inserted_at <= ^end_day)
  end

  defp add_timestamps(query, kpi, opts, date_range)
       when kpi in [
              :outbound_messages_count,
              :hsm_messages_count,
              :inbound_messages_count,
              :flows_started,
              :flows_completed,
              :conversation_count,
              :messages
            ] do
    duration = Keyword.get(opts, :duration, "WEEKLY")

    period =
      case duration do
        "MONTHLY" -> "month"
        "WEEKLY" -> "day"
        "DAILY" -> "day"
      end

    query
    |> where([q], q.period == ^period)
    |> where([q], q.date >= ^date_range.start_day)
    |> where([q], q.date <= ^date_range.end_day)
  end

  defp add_timestamps(query, _kpi, _date_range, _opts), do: query

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

    date_map =
      Enum.into(presets.date_map, %{}, fn {date, v} ->
        {Timex.format!(date, "{0D}-{0M}-{YY}"), v}
      end)

    Repo.put_process_state(org_id)

    query_data =
      get_kpi_query(presets, table, org_id)
      |> Repo.all()
      |> Enum.map(fn %{date: date} = map ->
        Map.put(map, :date, Timex.format!(date, "{0D}-{0M}-{YY}"))
      end)

    Enum.reduce(query_data, date_map, fn %{count: count, date: date}, acc ->
      Map.put(acc, date, count)
    end)
    |> Enum.sort_by(fn {date, _} -> Date.from_iso8601!("20" <> date) end)
  end

  @spec get_kpi_query(map(), String.t(), non_neg_integer()) :: Ecto.Query.t()
  defp get_kpi_query(presets, "stats", org_id) do
    start_date = presets.start_day |> Timex.to_date()
    end_date = presets.end_day |> Timex.to_date()

    from s in "stats",
      where:
        s.period == "day" and s.date >= ^start_date and s.date <= ^end_date and
          s.organization_id == ^org_id,
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
  @spec get_messages_data(non_neg_integer(), map()) :: map()
  def get_messages_data(org_id, date_range) do
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
    |> where([q], q.date >= ^date_range.start_day)
    |> where([q], q.date <= ^date_range.end_day)
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
  @spec get_broadcast_data(non_neg_integer(), map()) :: list()
  def get_broadcast_data(org_id, date_range) do
    timezone = Partners.organization_timezone(org_id)

    MessageBroadcast
    |> join(:inner, [mb], flow in assoc(mb, :flow))
    |> join(:inner, [mb, flow], group in assoc(mb, :group))
    |> where([mb], mb.organization_id == ^org_id)
    |> where([mb], mb.inserted_at >= ^date_range.start_day)
    |> where([mb], mb.inserted_at <= ^date_range.end_day)
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
  @spec get_contact_data(non_neg_integer(), map()) :: list()
  def get_contact_data(org_id, date_range) do
    get_count_query(:bsp_status)
    |> where([q], q.organization_id == ^org_id)
    |> where([q], q.inserted_at >= ^date_range.start_day)
    |> where([q], q.inserted_at <= ^date_range.end_day)
    |> Repo.all()
  end

  @doc false
  @spec get_date_preset(map()) :: map()
  def get_date_preset(date_range) do
    diff = NaiveDateTime.diff(date_range.end_day, date_range.start_day, :day)

    date_map =
      Enum.into(0..diff, %{}, fn day ->
        {date_range.start_day |> NaiveDateTime.add(day, :day), 0}
      end)

    %{
      start_day: date_range.start_day,
      date_map: date_map,
      end_day: date_range.end_day
    }
  end

  @spec extract_bookmarks(map() | nil) :: map()
  defp extract_bookmarks(nil), do: %{}
  defp extract_bookmarks(bookmark), do: bookmark

  @doc "Get all saved bookmarks as map"
  @spec get_bookmark_data(non_neg_integer()) :: map()
  def get_bookmark_data(org_id) do
    Repo.put_process_state(org_id)

    Organization
    |> select([q], q.setting["bookmarks"])
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
    |> hd
    |> extract_bookmarks()
  end

  @doc "Delete a bookmark"
  @spec delete_bookmark_data(map(), non_neg_integer()) :: list()
  def delete_bookmark_data(%{"name" => name}, org_id) do
    Organization
    |> where([o], o.organization_id == ^org_id)
    |> update([o],
      set: [
        setting:
          fragment(
            "setting #- array['bookmarks', ?::text]",
            ^name
          )
      ]
    )
    |> Repo.update_all([])
  end

  @doc "Add a bookmark"
  @spec save_bookmark_data(map(), non_neg_integer()) :: list()
  def save_bookmark_data(%{"name" => name, "link" => link}, org_id)
      when name != "" and link != "" do
    Organization
    |> where([o], o.organization_id == ^org_id)
    |> update([o],
      set: [
        setting:
          fragment(
            """
            CASE
            WHEN setting->'bookmarks' IS NULL
            THEN jsonb_insert(setting, array['bookmarks'], jsonb_build_object(?, ?))
            ELSE jsonb_set(setting, array['bookmarks', ?::text], ?)
            END
            """,
            type(^name, :string),
            type(^link, :string),
            ^name,
            ^link
          )
      ]
    )
    |> Repo.update_all([])
  end

  def save_bookmark_data(_, _), do: []

  @doc "Update a bookmark"
  @spec update_bookmark_data(map(), non_neg_integer()) :: list()
  def update_bookmark_data(
        %{
          "name" => name,
          "link" => link,
          "prev_name" => prev_name
        },
        org_id
      )
      when name != "" and link != "" and prev_name != "" do
    Organization
    |> where([o], o.organization_id == ^org_id)
    |> update([o],
      set: [
        setting:
          fragment(
            "jsonb_set(setting #- array['bookmarks', ?::text], array['bookmarks', ?::text], ?)",
            ^prev_name,
            ^name,
            ^link
          )
      ]
    )
    |> Repo.update_all([])
  end

  def update_bookmark_data(_, _), do: []

  @doc false
  @spec get_export_data(atom(), non_neg_integer(), map()) :: list()
  def get_export_data(chart, org_id, date_range) do
    get_export_query(chart)
    |> add_timestamps(chart, [], date_range)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
  end

  @spec get_export_query(atom()) :: Ecto.Query.t()
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
