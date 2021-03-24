defmodule Glific.StatsTest do
  use Glific.DataCase

  alias Glific.{Stats, Seeds.SeedsDev}

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  defp get_stats_count do
    {:ok, result} = Repo.query("SELECT count(*) from stats")
    [[count]] = result.rows
    count
  end

  test "Create a stat" do
    attrs = %{
      organization_id: 1,
      period: "hour",
      hour: 0,
      date: DateTime.to_date(DateTime.utc_now())
    }

    assert {:ok, stat} = Stats.create_stat(attrs)
    assert stat.period == "hour"
  end

  test "Update a stat" do
    attrs = %{
      organization_id: 1,
      period: "hour",
      hour: 0,
      date: DateTime.to_date(DateTime.utc_now())
    }

    assert {:ok, stat} = Stats.create_stat(attrs)

    {:ok, stat} = Stats.update_stat(stat, %{period: "day"})
    assert stat.period == "day"
  end

  test "Call all the functions in stats, and ensure that the DB size increases" do
    initial = get_stats_count()

    time = DateTime.utc_now() |> DateTime.truncate(:second)

    Stats.generate_stats([], false, [time: time])
    hour = get_stats_count()
    assert hour > initial

    time = Timex.beginning_of_day(time)
    Stats.generate_stats([], false, [time: time])
    day = get_stats_count()
    assert day > hour

    time = Timex.beginning_of_week(time)
    Stats.generate_stats([], false, [time: time])
    week = get_stats_count()
    assert week > day

    time = Timex.beginning_of_month(time)
    Stats.generate_stats([], false, [time: time])
    month = get_stats_count()
    assert month > week

    # now lets list all the stat entries
    stats = Stats.list_stats(%{filter: %{organization_id: 1}})
    checks = %{"hour" => false, "day" => false, "week" => false, "month" => false}

    stats
    |> Enum.reduce(
      checks,
      fn s, acc -> Map.put(acc, s.period, true) end
    )
    |> Enum.map(fn {_k, v} -> assert v == true end)

    # now lets set a filter that wont match
    assert Stats.list_stats(%{
             filter: %{
               organization_id: 1,
               period: "week",
               hour: 24,
               date: DateTime.to_date(time)
             }
           }) == []
  end
end
