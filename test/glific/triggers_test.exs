defmodule Glific.TriggersTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Fixtures,
    Flows,
    Groups,
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
      start_at = Timex.shift(DateTime.utc_now(), days: 1)
      end_date = Timex.shift(DateTime.utc_now(), days: 2)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
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

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "execute_triggers/2 should execute a trigger with frequency as none",
         attrs do
      start_at = Timex.shift(DateTime.utc_now(), minutes: 10)
      end_date = Timex.shift(DateTime.utc_now(), days: 1)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          end_date: end_date,
          frequency: ["none"]
        })

      # Trigger should not execute after 2 mins
      trigger_time = Timex.shift(DateTime.utc_now(), minutes: 2)

      msg_count_before_trigger = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id, trigger_time)
      msg_count_after_trigger = Messages.count_messages(%{filter: attrs})
      assert msg_count_after_trigger == msg_count_before_trigger

      # Trigger should not execute after 6 mins
      trigger_time = Timex.shift(DateTime.utc_now(), minutes: 6)

      msg_count_before_trigger = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id, trigger_time)
      msg_count_after_trigger = Messages.count_messages(%{filter: attrs})
      assert msg_count_after_trigger == msg_count_before_trigger

      # Trigger should execute after 10 mins
      trigger_time = Timex.shift(DateTime.utc_now(), minutes: 10)

      msg_count_before_trigger = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id, trigger_time)
      msg_count_after_trigger = Messages.count_messages(%{filter: attrs})
      assert msg_count_after_trigger > msg_count_before_trigger
    end

    test "execute_triggers/2 should execute a trigger with frequency as daily for two days in a row",
         attrs do
      start_at = Timex.shift(DateTime.utc_now(), minutes: 10)
      end_date = Timex.shift(DateTime.utc_now(), days: 4)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          end_date: end_date,
          frequency: ["daily"],
          is_repeating: true
        })

      # Trigger should execute after 10 mins
      trigger_time = Timex.shift(DateTime.utc_now(), minutes: 11)
      msg_count_day_0 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id, trigger_time)
      msg_count_day_1 = Messages.count_messages(%{filter: attrs})
      assert msg_count_day_1 > msg_count_day_0

      # Trigger should execute after 1 day and 10 mins
      trigger_time = Timex.shift(DateTime.utc_now(), days: 1, minutes: 11)

      Triggers.execute_triggers(attrs.organization_id, trigger_time)

      msg_count_day_2 = Messages.count_messages(%{filter: attrs})
      assert msg_count_day_2 == msg_count_day_0 + 2
      assert msg_count_day_2 == msg_count_day_1 + 1
    end

    test "triggers field returns list of triggers", attrs do
      tr = Fixtures.trigger_fixture(attrs)
      assert Trigger.get_trigger!(tr.id) == tr
    end

    test "create_trigger/1 with invalid data returns error", attrs do
      [flow | _tail] = Flows.list_flows(%{organization_id: attrs.organization_id})
      [group | _tail] = Groups.list_groups(%{organization_id: attrs.organization_id})

      arc = %{
        days: [],
        end_date: Timex.shift(Date.utc_today(), days: 2),
        flow_id: flow.id,
        group_id: group.id,
        is_active: false,
        is_repeating: false,
        organization_id: 1,
        start_date: Timex.shift(Date.utc_today(), days: -1),
        start_time: Time.utc_now()
      }

      assert {:error, %Ecto.Changeset{}} = Trigger.create_trigger(arc)
    end

    test "execute_triggers/2 should execute a trigger with last_trigger_at not nil", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: 1)
      end_date = Timex.shift(DateTime.utc_now(), days: 2)

      _trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          organization_id: attrs.organization_id,
          last_trigger_at: start_at,
          end_date: end_date
        })

      time = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(Trigger,
        set: [
          start_at: Timex.shift(time, days: -1),
          last_trigger_at: nil,
          next_trigger_at: Timex.shift(time, days: -1)
        ]
      )

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end

    test "execute_triggers/2 should execute a trigger with frequency as daily", attrs do
      start_at = Timex.shift(DateTime.utc_now(), days: 1)
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

      time = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(Trigger,
        set: [
          start_at: Timex.shift(time, days: -1),
          last_trigger_at: Timex.shift(time, days: -1),
          next_trigger_at: Timex.shift(time, days: -1)
        ]
      )

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

      msg_count1 = Messages.count_messages(%{filter: attrs})
      Triggers.execute_triggers(attrs.organization_id)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
    end
  end
end
