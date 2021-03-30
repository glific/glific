defmodule Glific.Seeds.SeedsStats do
  @moduledoc """
  One shot migration of data to seed the stats table
  """

  alias Glific.{Repo, Stats, Stats.Stat}

  @doc """
  Run the migration to populate the stats table for all active organizations
  """
  @spec seed_stats(list()) :: nil
  def seed_stats(org_id_list) do
    from_day = Timex.parse!("2021-03-01T00:00:00+00:00", "{ISO:Extended}")
    from_week = Timex.parse!("2021-01-04T00:00:00+00:00", "{ISO:Extended}")
    from_month = Timex.parse!("2020-06-01T00:00:00+00:00", "{ISO:Extended}")

    to =
      DateTime.utc_now()
      |> Timex.beginning_of_day()

    rows =
      %{}
      |> seed_daily(org_id_list, from_day, to)
      |> seed_weekly(org_id_list, from_week, to)
      |> seed_monthly(org_id_list, from_month, to)
      |> Stats.reject_empty()

    Repo.insert_all(Stat, rows)
    nil
  end

  @doc false
  @spec seed_monthly(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp seed_monthly(stats, org_id_list, from, to) do
    start = Timex.end_of_month(from)

    # we only compute till the end of the previous month
    finish = Timex.shift(Timex.end_of_month(to), months: -1)

    do_seed_monthly(stats, org_id_list, start, finish)
  end

  @spec do_seed_monthly(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp do_seed_monthly(stats, org_id_list, current, finish) do
    if DateTime.compare(current, finish) == :gt do
      stats
    else
      stats
      |> Stats.get_monthly_stats(org_id_list, time: current, summary: false)
      |> do_seed_monthly(org_id_list, Timex.shift(current, months: 1), finish)
    end
  end

  @doc false
  @spec seed_daily(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp seed_daily(stats, org_id_list, from, to) do
    start = Timex.end_of_day(from)

    do_seed_daily(stats, org_id_list, start, to)
  end

  @spec do_seed_daily(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp do_seed_daily(stats, org_id_list, current, finish) do
    if DateTime.compare(current, finish) == :gt do
      stats
    else
      stats
      |> Stats.get_daily_stats(org_id_list, time: current)
      |> do_seed_daily(org_id_list, Timex.shift(current, days: 1), finish)
    end
  end

  @doc false
  @spec seed_weekly(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp seed_weekly(stats, org_id_list, from, to) do
    start = Timex.end_of_week(from)

    # go back to the previous week
    finish = Timex.end_of_week(Timex.shift(to, days: -7))
    do_seed_weekly(stats, org_id_list, start, finish)
  end

  @spec do_seed_weekly(map(), list(), DateTime.t(), DateTime.t()) :: map()
  defp do_seed_weekly(stats, org_id_list, current, finish) do
    if DateTime.compare(current, finish) == :gt do
      stats
    else
      stats
      |> Stats.get_weekly_stats(org_id_list, time: current, summary: false)
      |> do_seed_weekly(org_id_list, Timex.shift(current, days: 7), finish)
    end
  end
end
