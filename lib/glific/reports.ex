defmodule Glific.Reports do
  @moduledoc """
  The Reports context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Repo
  }

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
  Returns last 7 days kpi data map with keys as date and value as count
  """
  @spec get_kpi_data(atom()) :: list()
  def get_kpi_data(:contacts) do
    get_kpi_date_keys()
    |> get_kpi_data_stats(:contacts)
  end

  # Returns last 7 days datetime which can then be used in query
  @spec get_kpi_date_keys() :: list()
  defp get_kpi_date_keys() do
    Enum.reduce(0..6, [], fn day, acc ->
      DateTime.utc_now()
      |> Timex.shift(days: -day)
      |> Timex.beginning_of_day()
      |> then(&(acc ++ [&1]))
    end)
  end

  # Query the KPI data and stitches it together in a map
  @spec get_kpi_data_stats(list(), atom()) :: map()
  defp get_kpi_data_stats(days, :contacts) do
    Enum.reduce(days, %{}, fn day, acc ->
      next_day = Timex.shift(day, days: 1)
      date_key = Timex.format!(day, "{0D}-{0M}-{YYYY}")

      Repo.one(
        from(p in Contact,
          select: count("*"),
          where: p.inserted_at >= ^day and p.inserted_at < ^next_day
        )
      )
      |> then(&Map.put(acc, date_key, &1))
    end)
  end
end
