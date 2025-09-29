defmodule Glific.StatsTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Partners,
    Seeds.SeedsDev,
    Stats
  }

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

  test "Create a stat", attrs do
    attrs = %{
      organization_id: attrs.organization_id,
      period: "hour",
      hour: 0,
      date: DateTime.to_date(DateTime.utc_now())
    }

    assert {:ok, stat} = Stats.create_stat(attrs)
    assert stat.period == "hour"
  end

  test "Update a stat", attrs do
    attrs = %{
      organization_id: attrs.organization_id,
      period: "hour",
      hour: 0,
      date: DateTime.to_date(DateTime.utc_now())
    }

    assert {:ok, stat} = Stats.create_stat(attrs)

    {:ok, stat} = Stats.update_stat(stat, %{period: "day"})
    assert stat.period == "day"
  end

  test "Call all the functions in stats, and ensure that the DB size increases", attrs do
    initial = get_stats_count()

    time = DateTime.utc_now() |> DateTime.truncate(:second)

    Stats.generate_stats([], false, time: time)
    hour = get_stats_count()
    assert hour > initial

    time = Timex.end_of_day(time)
    Stats.generate_stats([], false, time: time)
    day = get_stats_count()
    assert day > hour

    time = Timex.end_of_week(time)
    Stats.generate_stats([], false, time: time)
    week = get_stats_count()
    assert week > day

    # Don't check for "month" - time chaining causes monthly stats to query a future month
    # where no contacts exist, resulting in contacts: 0 and rejection by reject_empty()

    # now lets list all the stat entries
    stats = Stats.list_stats(%{filter: %{organization_id: attrs.organization_id}})
    checks = %{"hour" => false, "day" => false, "week" => false}

    stats
    |> Enum.reduce(
      checks,
      fn s, acc -> Map.put(acc, s.period, true) end
    )
    |> Enum.map(fn {_k, v} -> assert v == true end)

    # now lets set a filter that wont match
    assert Stats.list_stats(%{
             filter: %{
               organization_id: attrs.organization_id,
               period: "week",
               hour: 24,
               date: DateTime.to_date(time)
             }
           }) == []
  end

  test "count stats", attrs do
    inital = Stats.count_stats(%{filter: %{organization_id: attrs.organization_id}})
    assert inital == 0

    time = DateTime.utc_now() |> DateTime.truncate(:second)
    Stats.generate_stats([], false, time: time)

    assert Stats.count_stats(%{filter: %{organization_id: attrs.organization_id}}) > inital
  end

  test "mail_stats/2", attrs do
    org = Partners.get_organization!(attrs.organization_id)

    assert {:ok, %{message: _error}} = Stats.mail_stats(org)
  end

  test "daily stats should count created contacts and active contacts separately", attrs do
    org_id = attrs.organization_id
    test_date = Date.utc_today()

    contacts_list = Contacts.list_contacts(%{filter: %{organization_id: org_id}})

    contacts_created_today =
      contacts_list
      |> Enum.filter(fn contact ->
        DateTime.to_date(contact.inserted_at) == test_date
      end)

    existing_contacts_today = length(contacts_created_today)

    time = DateTime.new!(test_date, ~T[23:00:00], "Etc/UTC")
    Stats.generate_stats([org_id], false, time: time, day: true)

    daily_stats =
      Stats.list_stats(%{
        filter: %{
          organization_id: org_id,
          period: "day",
          date: test_date
        }
      })

    assert length(daily_stats) == 1
    [stat] = daily_stats

    assert stat.contacts == existing_contacts_today
  end
end
