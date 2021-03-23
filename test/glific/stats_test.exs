defmodule Glific.StatsTest do
  use Glific.DataCase

  alias Glific.Stats

  defp get_stats_count do
    {:ok, result} = Repo.query("SELECT count(*) from stats")
    [[count]] = result.rows
    count
  end

  test "Call all the functions in stats, and ensure that the DB size increases" do
    initial = get_stats_count()

    time = DateTime.utc_now() |> DateTime.truncate(:second)

    Stats.generate_stats([], false, time)
    hour = get_stats_count()
    assert hour > initial

    time = Timex.beginning_of_day(time)
    Stats.generate_stats([], false, time)
    day = get_stats_count()
    assert day > hour

    time = Timex.beginning_of_week(time)
    Stats.generate_stats([], false, time)
    week = get_stats_count()
    assert week > day

    time = Timex.beginning_of_month(time)
    Stats.generate_stats([], false, time)
    month = get_stats_count()
    assert month > week
  end
end
