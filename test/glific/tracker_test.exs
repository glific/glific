defmodule Glific.TrackersTest do
  use Glific.DataCase

  alias Glific.{
    Seeds.SeedsDev,
    Trackers,
    Trackers.Tracker,
    Repo
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_users(organization)
    :ok
  end

  describe "trackers" do
    test "create_tracker/1 creates a new tracker", attrs do
      tracker_attrs = %{
        organization_id: attrs.organization_id,
        counts: %{"Webhook" => 5, "Flows Started" => 2},
        date: Date.utc_today(),
        period: "day"
      }

      {:ok, _tracker} = Trackers.create_tracker(tracker_attrs)

      assert {:ok, tracker} =
               Repo.fetch_by(Tracker, %{
                 organization_id: attrs.organization_id
               })

      assert tracker.counts == %{"Webhook" => 5, "Flows Started" => 2}
      assert tracker.period == "day"
    end

    test "update_tracker/2 updates an existing tracker", attrs do
      tracker_attrs = %{
        organization_id: attrs.organization_id,
        counts: %{},
        date: Date.utc_today(),
        period: "day"
      }

      {:ok, tracker} = Trackers.create_tracker(tracker_attrs)
      updated_attrs = %{counts: %{"Webhook" => 5, "Flows Started" => 2}}
      {:ok, updated_tracker} = Trackers.update_tracker(tracker, updated_attrs)

      assert updated_tracker.counts == %{"Webhook" => 5, "Flows Started" => 2}
      assert updated_tracker.period == "day"
    end

    test "upsert_tracker/4 inserts a new tracker when it doesn't exist", attrs do
      counts = %{"Webhook" => 5, "Flows Started" => 2}
      organization_id = attrs.organization_id
      date = Date.utc_today()
      period = "day"

      # Upsert should create a new entry when called for first time
      assert {:ok, tracker} = Trackers.upsert_tracker(counts, organization_id, date, period)
      assert tracker.counts == %{"Webhook" => 5, "Flows Started" => 2}
      assert tracker.period == "day"

      # Upsert should append counts to existing entry when called for second time

      new_count = %{"Webhook" => 8, "Flows Started" => 10}

      assert {:ok, updated_tracker} =
               Trackers.upsert_tracker(new_count, organization_id, date, period)

      assert updated_tracker.counts == %{"Webhook" => 13, "Flows Started" => 12}
      assert updated_tracker.period == "day"
    end
  end
end
