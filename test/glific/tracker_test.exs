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
        counts: %{},
        date: Date.utc_today(),
        period: "day"
      }

      {:ok, tracker} = Trackers.create_tracker(tracker_attrs)
      assert %Tracker{} = tracker
      assert Repo.get_by(Tracker, organization_id: attrs.organization_id)
    end

    test "update_tracker/2 updates an existing tracker", attrs do
      tracker_attrs = %{
        organization_id: attrs.organization_id,
        counts: %{},
        date: Date.utc_today(),
        period: "day"
      }

      {:ok, tracker} = Trackers.create_tracker(tracker_attrs)
      updated_attrs = %{counts: %{sms: 10}}
      {:ok, updated_tracker} = Trackers.update_tracker(tracker, updated_attrs)

      assert %{sms: 10} = updated_tracker.counts
    end

    test "upsert_tracker/4 inserts a new tracker when it doesn't exist", attrs do
      counts = %{sms: 5}
      organization_id = attrs.organization_id
      date = Date.utc_today()
      period = "day"

      assert {:ok, _} = Trackers.upsert_tracker(counts, organization_id, date, period)
      assert %Tracker{} = Repo.get_by(Tracker, organization_id: organization_id)
    end

  end
end
