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
    Messages.MessageConversation,
    Notifications.Notification,
    Repo,
    Stats.Stat
  }

  @doc false
  @spec get_kpi(atom(), non_neg_integer()) :: integer()
  def get_kpi(kpi, org_id) do
    Repo.put_process_state(org_id)

    get_count_query(kpi)
    |> add_timestamps(kpi)
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

  defp get_count_query(:conversation_count) do
    MessageConversation
    |> select([q], count(q.id))
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

  @spec add_timestamps(Ecto.Query.t(), atom()) :: Ecto.Query.t()
  defp add_timestamps(query, kpi)
       when kpi in [
              :critical_notification_count,
              :warning_notification_count,
              :information_notification_count,
              :monthly_error_count,
              :active_flow_count,
              :conversation_count
            ] do
    date = Timex.beginning_of_month(DateTime.utc_now())

    query
    |> where([q], q.inserted_at >= ^date)
  end

  defp add_timestamps(query, kpi)
       when kpi in [
              :outbound_messages_count,
              :hsm_messages_count,
              :inbound_messages_count,
              :flows_started,
              :flows_completed
            ] do
    day = Date.beginning_of_month(DateTime.utc_now())

    query
    |> where([q], q.period == "day")
    |> where([q], q.date >= ^day)
  end

  defp add_timestamps(query, _kpi), do: query

  @doc """
  Returns last 7 days kpi data map with keys as date AND value as count

    ## Examples

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
    iex> Glific.Reports.get_kpi_data(1, "messages_conversations")
    iex> Glific.Reports.get_kpi_data(1, "optin")
    iex> Glific.Reports.get_kpi_data(1, "optout")
    iex> Glific.Reports.get_kpi_data(1, "contact_type")
  """
  @spec get_kpi_data(non_neg_integer(), String.t()) :: map()
  def get_kpi_data(org_id, table) do
    presets = get_date_preset()

    query_data =
      get_kpi_query(presets, table, org_id)
      |> Repo.query!([])

    Enum.reduce(query_data.rows, presets.date_map, fn [date, count], acc ->
      Map.put(acc, Timex.format!(date, "{0D}-{0M}-{YYYY}"), count)
    end)
  end

  defp get_kpi_query(presets, table, org_id) do
    """
    SELECT date_trunc('day', inserted_at) as date,
    COUNT(id) as count
    FROM #{table}
    WHERE
      inserted_at > '#{presets.last_day}'
      AND inserted_at <= '#{presets.today}'
      AND organization_id = #{org_id}
    GROUP BY date
    """
  end

  @spec get_messages_data(non_neg_integer()) :: map()
  def get_messages_data(org_id) do
    query_data =
      get_hourly_messages_query(org_id)
      |> Repo.query!([])

    hourly_msg = Enum.into(0..23, %{}, fn key -> {key, %{inbound: 0, outbound: 0}} end)
    res = Enum.reduce(query_data.rows, hourly_msg, fn [hour, inbound, outbound], acc ->
      Map.put(acc, hour, %{inbound: inbound, outbound: outbound})
    end)
    IO.inspect(res)
  end

  defp get_hourly_messages_query(org_id) do
    """
    SELECT hour, inbound, outbound
    FROM stats
    WHERE
      organization_id = #{org_id}
      and date_trunc('month',date) = date_trunc('month',CURRENT_DATE)
      and period = 'hour'
    """
  end

  @doc """
    gets data for the broadcast table
  """
  @spec get_broadcast_data(non_neg_integer()) :: list()
  def get_broadcast_data(org_id) do
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
      started_at = Timex.format!(message_broadcast.started_at, "%d-%m-%Y %I:%M %p", :strftime)

      completed_at =
        if is_nil(message_broadcast.completed_at),
          do: "Not Completed Yet",
          else: Timex.format!(message_broadcast.completed_at, "%d-%m-%Y %I:%M %p", :strftime)

      acc ++
        [[message_broadcast.flow_name, message_broadcast.group_label, started_at, completed_at]]
    end)
  end

  @doc false
  @spec get_contact_data(non_neg_integer()) :: map()
  def get_contact_data(org_id) do
    get_count_query(:bsp_status)
    |> where([q], q.organization_id == ^org_id)
    |> Repo.all()
  end

  @spec get_date_preset(DateTime.t()) :: map()
  defp get_date_preset(time \\ DateTime.utc_now()) do
    today = shifted_time(time, 1) |> Timex.format!("{YYYY}-{0M}-{0D}")

    last_day = shifted_time(time, -6) |> Timex.format!("{YYYY}-{0M}-{0D}")

    date_map =
      Enum.reduce(0..6, %{}, fn day, acc ->
        time
        |> shifted_time(-day)
        |> Timex.format!("{0D}-{0M}-{YYYY}")
        |> then(&Map.put(acc, &1, 0))
      end)

    %{today: today, last_day: last_day, date_map: date_map}
  end

  @spec shifted_time(DateTime.t(), integer()) :: DateTime.t()
  defp shifted_time(time, days) do
    time
    |> Timex.beginning_of_day()
    |> Timex.shift(days: days)
  end
end
