defmodule Glific.TriggersTest do

  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Messages,
    Seeds.SeedsDev,
    Triggers
  }


  setup do
  organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_flows(organization)
    SeedsDev.seed_users(organization)
    SeedsDev.seed_groups(organization)
    SeedsDev.seed_group_contacts(organization)
    SeedsDev.seed_group_users(organization)
    :ok
  end

  describe "triggers" do
    test "execute_triggers/2 should execute a trigger", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: -1)
      end_date = Timex.shift(DateTime.utc_now(), days: 1)

      _trigger = Fixtures.trigger_fixture(%{start_at: start_at, organization_id: attrs.organization_id, end_date: end_date})
      msg_count1 = Messages.count_messages(%{filter: attrs})
       Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "execute_triggers/2 should execute a trigger with last_trigger_at not nil", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: -1)
      end_date = Timex.shift(DateTime.utc_now(), days: 2)
      _trigger = Fixtures.trigger_fixture(%{start_at: start_at, organization_id: attrs.organization_id, last_trigger_at: time, end_date: end_date})
      msg_count1 = Messages.count_messages(%{filter: attrs})
       Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end
  end
end
