defmodule Glific.TriggersTest do
  alias Glific.Flows.Flow
  alias Glific.Groups.Group
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo
  import Ecto.Query

  alias Glific.{
    Fixtures,
    Flows,
    Flows.Broadcast,
    Groups,
    Messages,
    Repo,
    Seeds.SeedsDev,
    Triggers,
    Triggers.Trigger,
    Triggers.TriggerLog
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts(organization)
    SeedsDev.seed_flows(organization)
    SeedsDev.seed_users(organization)
    SeedsDev.seed_groups(organization)
    SeedsDev.seed_group_contacts(organization)
    SeedsDev.seed_group_users(organization)
    SeedsDev.seed_test_flows()
    SeedsDev.seed_wa_managed_phones()
    SeedsDev.seed_wa_groups()
    SeedsDev.seed_wa_group_collections()
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
      assert Triggers.get_trigger!(tr.id) == tr
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
        start_time: Time.utc_now(),
        frequency: ["none"]
      }

      {:error, message} = Triggers.create_trigger(arc)
      error_message = Map.get(message, :message)
      assert error_message == nil
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

    @hour_12pm 12
    @hour_3pm 15
    @hour_9pm 21
    test "execute_triggers/2 should execute a trigger with frequency as hourly", attrs do
      # Setting trigger start at 12pm IST
      start_at =
        DateTime.utc_now()
        |> Timex.beginning_of_day()
        |> Timex.shift(hours: 6, minutes: 30)
        |> Timex.shift(days: 1)

      # Setting trigger start at 5 days later
      end_date =
        DateTime.utc_now()
        |> Timex.beginning_of_day()
        |> Timex.shift(days: 5)

      trigger =
        Fixtures.trigger_fixture(%{
          start_at: start_at,
          frequency: ["hourly"],
          is_repeating: true,
          organization_id: attrs.organization_id,
          end_date: end_date,
          hours: [@hour_12pm, @hour_3pm, @hour_9pm]
        })

      msg_count1 = Messages.count_messages(%{filter: attrs})
      # Executing trigger at the starting time
      Triggers.execute_triggers(attrs.organization_id, start_at)
      msg_count2 = Messages.count_messages(%{filter: attrs})
      assert msg_count2 > msg_count1
      trigger = Triggers.get_trigger!(trigger.id)
      assert trigger.next_trigger_at.hour == 9

      # Executing trigger at second set time i.e 3PM IST
      execute_time = start_at |> Timex.shift(hours: 3)
      Triggers.execute_triggers(attrs.organization_id, execute_time)
      msg_count3 = Messages.count_messages(%{filter: attrs})
      assert msg_count3 > msg_count2
      trigger = Triggers.get_trigger!(trigger.id)
      assert trigger.next_trigger_at.hour == 15
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

  describe "trigger logs" do
    test "create_trigger_log/1 creates a trigger log", attrs do
      trigger = Fixtures.trigger_fixture(%{organization_id: attrs.organization_id})
      flow_context = Fixtures.flow_context_fixture(%{organization_id: attrs.organization_id})

      trigger_log_attrs = %{
        trigger_id: trigger.id,
        flow_context_id: flow_context.id,
        started_at: Timex.shift(DateTime.utc_now(), days: -1),
        organization_id: attrs.organization_id
      }

      {:ok, trigger_log} = TriggerLog.create_trigger_log(trigger_log_attrs)
      assert trigger_log.id
      assert trigger_log.trigger_id == trigger.id
      assert trigger_log.flow_context_id == flow_context.id
      assert trigger_log.started_at
    end

    test "update_trigger_log/2 updates a trigger log", attrs do
      trigger = Fixtures.trigger_fixture(%{organization_id: attrs.organization_id})
      flow_context = Fixtures.flow_context_fixture(%{organization_id: attrs.organization_id})

      trigger_log_attrs = %{
        trigger_id: trigger.id,
        flow_context_id: flow_context.id,
        started_at: Timex.shift(DateTime.utc_now(), days: -1),
        organization_id: attrs.organization_id
      }

      {:ok, trigger_log} = TriggerLog.create_trigger_log(trigger_log_attrs)

      updated_flow_context =
        Fixtures.flow_context_fixture(%{organization_id: attrs.organization_id})

      # Providing a valid value
      updated_attrs = %{flow_context_id: updated_flow_context.id}

      {:ok, updated_trigger_log} = TriggerLog.update_trigger_log(trigger_log, updated_attrs)

      assert Map.get(updated_trigger_log, :flow_context_id) == updated_flow_context.id
    end
  end

  test "check_trigger_warnings/1 with incorrect node should returns error", attrs do
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
      start_time: Time.utc_now(),
      frequency: ["none"]
    }

    {:warning, message} = Triggers.validate_trigger(arc)
    assert message == "The first message node is not an HSM template"
  end

  test "execute_triggers/2 should execute a trigger for WA group collections", attrs do
    start_at = Timex.shift(DateTime.utc_now(), days: 1)
    end_date = Timex.shift(DateTime.utc_now(), days: 2)

    {:ok, _trigger} =
      create_wa_group_trigger(attrs, %{
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

    Triggers.execute_triggers(attrs.organization_id)
  end

  test "broadcast_per_minute count depending on high trigger tps enabled", attrs do
    FunWithFlags.enable(:high_trigger_tps_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    assert 300 = Broadcast.broadcast_per_minute_count(attrs.organization_id)

    FunWithFlags.disable(:high_trigger_tps_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )
  end

  test "broadcast_per_minute count depending on high trigger tps not enabled", attrs do
    assert 100 = Broadcast.broadcast_per_minute_count(attrs.organization_id)
  end

  defp create_wa_group_trigger(attrs, trigger_attrs) do
    valid_attrs = %{
      name: "test wa group trigger",
      end_date: Faker.DateTime.forward(5),
      is_active: true,
      is_repeating: false,
      start_date: Timex.shift(Date.utc_today(), days: 1),
      start_time: Time.utc_now(),
      frequency: ["none"]
    }

    [g1 | _] =
      Group
      |> where([grp], grp.organization_id == ^attrs.organization_id and grp.group_type == "WA")
      |> Repo.all()

    {:ok, flow} =
      Repo.fetch_by(Flow, %{name: "Whatsapp Group", organization_id: attrs.organization_id})

    valid_attrs =
      Map.merge(valid_attrs, trigger_attrs)
      |> Map.put(:flow_id, flow.id)
      |> Map.put(:group_ids, [g1.id])
      |> Map.put(:organization_id, attrs.organization_id)
      |> Map.put(:group_type, "WA")

    Triggers.create_trigger(valid_attrs)
  end
end
