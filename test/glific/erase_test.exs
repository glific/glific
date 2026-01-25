defmodule Glific.EraseTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.{
    Contacts.ContactHistory,
    Erase,
    Fixtures,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Messages,
    Messages.Message,
    Notifications,
    Notifications.Notification,
    Repo
  }

  test "perform_periodic clears webhook log older than a month", attrs do
    Fixtures.webhook_log_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(WebhookLog,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    logs_count = WebhookLog.count_webhook_logs(%{filter: attrs})
    Erase.clean_old_records()
    assert WebhookLog.count_webhook_logs(%{filter: attrs}) == logs_count - 1
  end

  test "perform_periodic clears notifications log older than a month", attrs do
    Fixtures.notification_fixture(attrs)
    time = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(Notification,
      set: [
        inserted_at: Timex.shift(time, months: -2)
      ]
    )

    notification_count = Notifications.count_notifications(%{filter: attrs})
    Erase.clean_old_records()
    assert Notifications.count_notifications(%{filter: attrs}) == notification_count - 1
  end

  test "perform_periodic clears flow revisions with status as draft, and saving only recent 10",
       attrs do
    user = Repo.get_current_user()
    flow = Fixtures.flow_fixture(attrs)

    Enum.each(1..15, fn _x ->
      FlowRevision.create_flow_revision(%{
        definition: FlowRevision.default_definition(flow),
        flow_id: flow.id,
        user_id: user.id,
        organization_id: flow.organization_id
      })
    end)

    flow_revision_count = Repo.count_filter(%{}, FlowRevision, &Repo.filter_with/2)
    Erase.clean_old_records()
    assert Repo.count_filter(%{}, FlowRevision, &Repo.filter_with/2) == flow_revision_count - 6
  end

  test "delete beneficiary data", attrs do
    contact_1 = Fixtures.contact_fixture()
    contact_2 = Fixtures.contact_fixture()

    Fixtures.message_fixture(%{sender_id: contact_1.id})
    Fixtures.message_fixture(%{sender_id: contact_1.id})
    Fixtures.message_fixture(%{sender_id: contact_2.id})

    assert Message
           |> where([m], m.contact_id == ^contact_1.id)
           |> Repo.aggregate(:count) == 2

    assert :ok = Erase.delete_benefeciary_data(attrs.organization_id, contact_1.phone)

    assert Message
           |> where([m], m.contact_id == ^contact_1.id)
           |> Repo.aggregate(:count) == 0

    assert Message
           |> where([m], m.contact_id == ^contact_2.id)
           |> Repo.aggregate(:count) == 1

    assert {:error, ["Elixir.Glific.Contacts.Contact", "Resource not found"]} =
             Erase.delete_benefeciary_data(attrs.organization_id, contact_1.phone)
  end

  test "delete old messages, stops when rows deleted become 0 first", attrs do
    sender = Fixtures.contact_fixture(attrs)
    # > 2 month old messages
    for _i <- 0..5 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -90, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -90, :day)
      })
      |> Repo.update()
    end

    # < 2 month old messages
    for _i <- 0..5 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -40, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -40, :day)
      })
      |> Repo.update()
    end

    {:ok, _} = Erase.perform_message_purge(3, 10, false)
    assert_enqueued(worker: Erase, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} =
             Oban.drain_queue(queue: :purge, with_safety: false)

    assert length(Messages.list_messages(%{filter: %{contact_id: sender.id}})) == 6
  end

  test "delete old messages, stops when rows deleted become >= 5 first", attrs do
    sender = Fixtures.contact_fixture(attrs)
    # > 2 month old messages
    for _i <- 0..10 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -90, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -90, :day)
      })
      |> Repo.update()
    end

    # < 2 month old messages
    for _i <- 0..5 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -40, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -40, :day)
      })
      |> Repo.update()
    end

    {:ok, _} = Erase.perform_message_purge(3, 5, false)

    assert_enqueued(worker: Erase, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} =
             Oban.drain_queue(queue: :purge, with_safety: false)

    assert length(Messages.list_messages(%{filter: %{contact_id: sender.id}})) == 11
  end

  test "delete old messages with envs", attrs do
    sender = Fixtures.contact_fixture(attrs)
    # > 2 month old messages
    for _i <- 0..10 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -90, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -90, :day)
      })
      |> Repo.update()
    end

    # < 2 month old messages
    for _i <- 0..5 do
      Fixtures.message_fixture(%{
        organization_id: attrs.organization_id,
        sender_id: sender.id
      })
      |> Ecto.Changeset.change(%{
        inserted_at: DateTime.add(DateTime.utc_now(), -40, :day),
        updated_at: DateTime.add(DateTime.utc_now(), -40, :day)
      })
      |> Repo.update()
    end

    {:ok, _} = Erase.perform_message_purge()

    assert_enqueued(worker: Erase, prefix: "global")

    assert %{success: 1, failure: 0, snoozed: 0, discard: 0, cancelled: 0} =
             Oban.drain_queue(queue: :purge, with_safety: false)

    assert length(Messages.list_messages(%{filter: %{contact_id: sender.id}})) == 6
  end

  test "perform_periodic clears contact histories older than 2 month", attrs do
    contact = Fixtures.contact_fixture(attrs)

    attrs =
      %{
        event_type: "contact_flow_ended",
        event_label: "Flow Completed",
        contact_id: contact.id,
        event_datetime: DateTime.utc_now(),
        organization_id: contact.organization_id,
        event_meta: %{}
      }

    %ContactHistory{}
    |> ContactHistory.changeset(attrs)
    |> Repo.insert!()
    |> Ecto.Changeset.change(%{
      inserted_at: DateTime.add(DateTime.utc_now(), -90, :day),
      updated_at: DateTime.add(DateTime.utc_now(), -90, :day)
    })
    |> Repo.update()

    %ContactHistory{}
    |> ContactHistory.changeset(attrs)
    |> Repo.insert()

    histories =
      ContactHistory
      |> where([ch], ch.contact_id == ^contact.id)
      |> order_by([ch], ch.event_datetime)
      |> Repo.all()

    assert length(histories) == 2
    Erase.clean_old_records()

    histories =
      ContactHistory
      |> where([ch], ch.contact_id == ^contact.id)
      |> order_by([ch], ch.event_datetime)
      |> Repo.all()

    assert length(histories) == 1
  end
end
