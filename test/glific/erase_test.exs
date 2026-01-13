defmodule Glific.EraseTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

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
    Partners.Organization,
    Repo,
    WhatsappForms.WhatsappFormRevision,
    WhatsappFormsRevisions
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

  test "perform_periodic clears whatsapp forms revisions, and saving only recent 10",
       _attrs do
    user = Repo.get_current_user()
    form = Fixtures.whatsapp_form_fixture()

    value = %{
      whatsapp_form_id: form.id,
      definition: %{"key" => Ecto.UUID.generate()}
    }

    Enum.each(1..15, fn _ ->
      WhatsappFormsRevisions.save_revision(
        value,
        user
      )
    end)

    total_revisions_before =
      Repo.aggregate(
        from(r in WhatsappFormRevision,
          where: r.whatsapp_form_id == ^form.id
        ),
        :count
      )

    assert total_revisions_before == 16
    Erase.clean_old_records()

    total_revisions_after =
      Repo.aggregate(
        from(r in WhatsappFormRevision,
          where: r.whatsapp_form_id == ^form.id
        ),
        :count
      )

    assert total_revisions_after == 10
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

  test "successfully processes organization deletion" do
    organization = Fixtures.organization_fixture(%{status: :ready_to_delete})

    assert {:ok, job} = Erase.delete_organization(organization.id)
    assert %Oban.Job{args: %{"organization_id" => organization_id}} = job
    assert organization_id == organization.id
    assert :ok = perform_job(Erase, job.args)
    assert {:error, [_module, "Resource not found"]} = Repo.fetch(Organization, organization.id)
  end

  test "handles non-existent organization gracefully" do
    non_existent_id = 999_999_999

    assert {:ok, job} = Erase.delete_organization(non_existent_id)
    assert {:error, "Organization not found"} = perform_job(Erase, job.args)
  end

  test "handles organization that is not deletable" do
    organization = Fixtures.organization_fixture(%{status: :active})

    assert {:ok, job} = Erase.delete_organization(organization.id)
    assert {:error, "Organization not deletable"} = perform_job(Erase, job.args)
  end

  test "enqueues organization deletion job correctly" do
    organization = Fixtures.organization_fixture(%{is_active: false})

    assert {:ok, %Oban.Job{} = job} = Erase.delete_organization(organization.id)
    assert job.queue == "purge"
    assert job.max_attempts == 1
    assert job.args["organization_id"] == organization.id
  end

  test "handles organization deletion with dependent data" do
    organization = Fixtures.organization_fixture(%{status: :ready_to_delete})
    contact = Fixtures.contact_fixture(%{organization_id: organization.id})

    Fixtures.message_fixture(%{
      organization_id: organization.id,
      sender_id: contact.id,
      receiver_id: contact.id
    })

    assert {:ok, job} = Erase.delete_organization(organization.id)

    assert :ok = perform_job(Erase, job.args)

    assert {:error, [_module, "Resource not found"]} = Repo.fetch(Organization, organization.id)
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
