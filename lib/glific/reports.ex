defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.Repo

  @doc false
  @spec get_kpi(atom(), non_neg_integer()) :: integer()
  def get_kpi(kpi, org_id) do
    [[count]] =
      get_count_query(org_id, kpi)
      |> Repo.query!([])
      |> then(& &1.rows)

    case count do
      count -> count
      _ -> 0
    end
  end

  @doc false
  @spec kpi_list() :: list()
  def kpi_list do
    [
      :conversation_count,
      :active_flow_count,
      :valid_contact_count,
      :invalid_contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count,
      :non_opted_contacts_count,
      :inbound_messages_count,
      :outbound_messages_count,
      :hsm_messages_count
    ]
  end

  defp get_count_query(org_id, :conversation_count),
    do:
      "SELECT COUNT(id) FROM messages_conversations WHERE organization_id = #{org_id} and inserted_at >= date_trunc('month', CURRENT_DATE)"

  defp get_count_query(org_id, :active_flow_count),
    do:
      "SELECT COUNT(id) FROM flow_contexts WHERE organization_id = #{org_id} and completed_at IS NULL"

  defp get_count_query(org_id, :valid_contact_count),
    do: "SELECT COUNT(id) FROM contacts WHERE organization_id = #{org_id} and status = 'valid'"

  defp get_count_query(org_id, :invalid_contact_count),
    do: "SELECT COUNT(id) FROM contacts WHERE organization_id = #{org_id} and status = 'invalid'"

  defp get_count_query(org_id, :opted_in_contacts_count),
    do:
      "SELECT COUNT(id) FROM contacts WHERE organization_id = #{org_id} and optin_time IS NOT NULL"

  defp get_count_query(org_id, :opted_out_contacts_count),
    do:
      "SELECT COUNT(id) FROM contacts WHERE organization_id = #{org_id} and optout_time IS NOT NULL"

  defp get_count_query(org_id, :non_opted_contacts_count),
    do:
      "SELECT COUNT(id) FROM contacts WHERE organization_id = #{org_id} and optout_time IS NULL and optin_time IS NULL"

  defp get_count_query(org_id, :inbound_messages_count),
    do:
      "SELECT inbound FROM stats WHERE organization_id = #{org_id} and inserted_at >= CURRENT_DATE and period = 'day'"

  defp get_count_query(org_id, :outbound_messages_count),
    do:
      "SELECT outbound FROM stats WHERE organization_id = #{org_id} and inserted_at >= CURRENT_DATE and period = 'day'"

  defp get_count_query(org_id, :hsm_messages_count),
    do:
      "SELECT hsm FROM stats WHERE organization_id = #{org_id} and inserted_at >= CURRENT_DATE and period = 'day'"

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
