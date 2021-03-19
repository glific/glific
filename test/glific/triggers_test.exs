defmodule Glific.TriggersTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo
  import ExUnit.CaptureLog
  require Logger

  alias Glific.{
    Fixtures,
    Messages,
    Repo,
    Seeds.SeedsDev,
    Triggers,
    Triggers.Trigger
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

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          end_date: end_date
        })

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "triggers field returns list of triggers", attrs do
      tr = Fixtures.trigger_fixture(attrs)
      assert Trigger.get_trigger!(tr.id) == tr
    end

    @tag :pending
    test "execute_triggers/2 should execute a trigger and capture log", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: -1)
      end_date = Timex.shift(DateTime.utc_now(), days: 1)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          end_date: end_date
        })

      assert capture_log(fn ->
               Triggers.execute_triggers(attrs.organization_id)
             end) =~ "executing trigger: test trigger for org_id: #{attrs.organization_id}"
    end

    test "execute_triggers/2 should execute a trigger with last_trigger_at not nil", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: -1)
      end_date = Timex.shift(DateTime.utc_now(), days: 2)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          last_trigger_at: start_at,
          end_date: end_date
        })

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "execute_triggers/2 should execute a trigger with frequency as daily", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: -1)
      end_date = Timex.shift(DateTime.utc_now(), days: 5)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          frequency: ["daily"],
          is_repeating: true,
          organization_id: attrs.organization_id,
          last_trigger_at: start_at,
          end_date: end_date
        })

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "execute_triggers/2 should execute a trigger with frequency as weekly with days defined",
         attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: 1)
      end_date = Timex.shift(DateTime.utc_now(), days: 5)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          days: [7, 6, 5, 4, 3, 2, 1],
          frequency: ["weekly"],
          is_repeating: true,
          organization_id: attrs.organization_id,
          last_trigger_at: start_at,
          end_date: end_date
        })

      time = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(Trigger,
        set: [
          start_at: Timex.shift(time, days: -1),
          last_trigger_at: Timex.shift(time, days: -1),
          next_trigger_at: Timex.shift(time, days: -1)
        ]
      )
      | Trigger.list_triggers(%{})

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end
  end
end
