defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.Repo

  @doc false
  @spec get_kpi(String.t()) :: integer()
  def get_kpi(_kpi) do
    Enum.random(100..1000)
  end

  @doc false
  @spec kpi_list() :: list()
  def kpi_list do
    [
      :conversation_count,
      :active_flow_count,
      :contact_count,
      :opted_in_contacts_count,
      :opted_out_contacts_count
    ]
  end

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
  """
  @spec get_kpi_data(non_neg_integer(), String.t()) :: map()
  def get_kpi_data(org_id, table) do
    presets = get_preset_dates()

    query_data =
      get_kpi_query(presets, table, org_id)
      |> Repo.query!([])

    Enum.reduce(query_data.rows, presets.date_map, fn [date, count], acc ->
      Map.put(acc, Timex.format!(date, "{0D}-{0M}-{YYYY}"), count)
    end)
  end

  defp get_kpi_query(presets, "optin", org_id) do
    """
    SELECT date_trunc('day', optin_time) as optin_date,
    COUNT(id) as count
    FROM contacts
    WHERE
      inserted_at > '#{presets.last_day}'
      AND inserted_at <= '#{presets.today}'
      AND organization_id = #{org_id}
      AND optin_time IS NOT NULL
    GROUP BY optin_date
    """
  end

  defp get_kpi_query(presets, "optout", org_id) do
    """
    SELECT date_trunc('day', optout_time) as optout_date,
    COUNT(id) as count
    FROM contacts
    WHERE
      inserted_at > '#{presets.last_day}'
      AND inserted_at <= '#{presets.today}'
      AND organization_id = #{org_id}
      AND optout_time IS NOT NULL
    GROUP BY optout_date
    """
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

  @spec get_preset_dates(DateTime.t()) :: map()
  defp get_preset_dates(time \\ DateTime.utc_now()) do
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
