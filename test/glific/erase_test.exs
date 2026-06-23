defmodule Glific.EraseTest do
  use Glific.DataCase
  use Oban.Pro.Testing, repo: Glific.Repo

  alias Glific.{
    Assistants,
    Assistants.Assistant,
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBase,
    Assistants.KnowledgeBaseVersion,
    Contacts.ContactHistory,
    Erase,
    Fixtures,
    Flows.FlowResult,
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
    {_, form} = Fixtures.whatsapp_form_fixture()

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

    # Organization record is preserved with deleted_at set
    {:ok, deleted_org} =
      Repo.fetch(Organization, organization.id, skip_organization_id: true, include_deleted: true)

    assert deleted_org.deleted_at != nil
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

    # Organization record preserved with deleted_at set
    {:ok, deleted_org} =
      Repo.fetch(Organization, organization.id, skip_organization_id: true, include_deleted: true)

    assert deleted_org.deleted_at != nil

    # All related data should be deleted
    {:ok, result} =
      Repo.query("SELECT count(*) FROM messages WHERE organization_id = #{organization.id}")

    [[count]] = result.rows
    assert count == 0

    {:ok, result} =
      Repo.query("SELECT count(*) FROM contacts WHERE organization_id = #{organization.id}")

    [[count]] = result.rows
    assert count == 0
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

  test "delete_organization_data clears all expected tables for the org", attrs do
    org_id = attrs.organization_id

    # messages_media
    media = Fixtures.message_media_fixture(attrs)

    # messages (requires a contact)
    contact = Fixtures.contact_fixture(attrs)
    msg = Fixtures.message_fixture(%{sender_id: contact.id, organization_id: org_id})

    # contact_histories
    {:ok, history} =
      %ContactHistory{}
      |> ContactHistory.changeset(%{
        event_type: "contact_flow_ended",
        event_label: "Flow Completed",
        contact_id: contact.id,
        event_datetime: DateTime.utc_now(),
        organization_id: org_id,
        event_meta: %{}
      })
      |> Repo.insert()

    # contacts_groups
    contact_group = Fixtures.contact_group_fixture(attrs)

    # flow_contexts
    flow_context = Fixtures.flow_context_fixture(attrs)

    # flow_results
    {:ok, flow_result} =
      FlowResult.upsert_flow_result(%{
        contact_id: contact.id,
        flow_context_id: flow_context.id,
        flow_id: flow_context.flow_id,
        flow_uuid: flow_context.flow_uuid,
        flow_version: 1,
        organization_id: org_id
      })

    # assistants — with active_config_version_id set (the FK violation case)
    {:ok, assistant} =
      Repo.insert(
        Assistant.changeset(%Assistant{}, %{
          name: "Test Assistant #{System.unique_integer()}",
          organization_id: org_id
        })
      )

    {:ok, config_version} =
      Repo.insert(
        AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
          assistant_id: assistant.id,
          organization_id: org_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant.",
          settings: %{},
          status: :ready
        })
      )

    Repo.update!(
      Assistant.set_active_config_version_changeset(assistant, %{
        active_config_version_id: config_version.id
      })
    )

    # knowledge_bases and knowledge_base_versions
    {:ok, kb} = Assistants.create_knowledge_base(%{name: "Test KB", organization_id: org_id})

    {:ok, kb_version} =
      Assistants.create_knowledge_base_version(%{
        knowledge_base_id: kb.id,
        organization_id: org_id,
        files: %{},
        status: :completed,
        llm_service_id: Ecto.UUID.generate()
      })

    # interactive_templates
    interactive = Fixtures.interactive_fixture(attrs)

    # triggers
    trigger = Fixtures.trigger_fixture(attrs)

    # notifications
    notification = Fixtures.notification_fixture(attrs)

    # webhook_logs
    webhook_log = Fixtures.webhook_log_fixture(attrs)

    assert :ok = Erase.delete_organization_data(org_id)

    # messages_media
    assert Repo.get(Messages.MessageMedia, media.id) == nil

    # messages
    assert Repo.get(Message, msg.id) == nil

    # contact_histories
    assert Repo.get(ContactHistory, history.id) == nil

    # contacts_groups
    assert Repo.get(Glific.Groups.ContactGroup, contact_group.id) == nil

    # flow_contexts
    assert Repo.get(Glific.Flows.FlowContext, flow_context.id) == nil

    # flow_results
    assert Repo.get(FlowResult, flow_result.id) == nil

    # assistants + config versions (FK violation fix)
    assert Repo.get(Assistant, assistant.id) == nil
    assert Repo.get(AssistantConfigVersion, config_version.id) == nil

    # knowledge_bases + versions
    assert Repo.get(KnowledgeBase, kb.id) == nil
    assert Repo.get(KnowledgeBaseVersion, kb_version.id) == nil

    # interactive_templates
    assert Repo.get(Glific.Templates.InteractiveTemplate, interactive.id) == nil

    # triggers
    assert Repo.get(Glific.Triggers.Trigger, trigger.id) == nil

    # notifications
    assert Repo.get(Notification, notification.id) == nil

    # webhook_logs
    assert Repo.get(WebhookLog, webhook_log.id) == nil
  end

  # Adding special tests for assistants as it contains 2 way FK relationships
  test "delete_organization_data succeeds when org has no assistants", attrs do
    assert :ok = Erase.delete_organization_data(attrs.organization_id)
  end

  test "delete_organization_data succeeds when assistant has no active_config_version_id set",
       attrs do
    org_id = attrs.organization_id

    {:ok, assistant} =
      Repo.insert(
        Assistant.changeset(%Assistant{}, %{
          name: "Test Assistant #{System.unique_integer()}",
          organization_id: org_id
        })
      )

    {:ok, config_version} =
      Repo.insert(
        AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
          assistant_id: assistant.id,
          organization_id: org_id,
          provider: "openai",
          model: "gpt-4o",
          prompt: "You are a helpful assistant.",
          settings: %{},
          status: :ready
        })
      )

    assert :ok = Erase.delete_organization_data(org_id)

    assert Repo.get(Assistant, assistant.id) == nil
    assert Repo.get(AssistantConfigVersion, config_version.id) == nil
  end

  test "delete_organization_data succeeds when multiple assistants each have active_config_version_id set",
       attrs do
    org_id = attrs.organization_id

    assistants_with_versions =
      Enum.map(1..3, fn i ->
        {:ok, assistant} =
          Repo.insert(
            Assistant.changeset(%Assistant{}, %{
              name: "Test Assistant #{System.unique_integer()} #{i}",
              organization_id: org_id
            })
          )

        {:ok, config_version} =
          Repo.insert(
            AssistantConfigVersion.changeset(%AssistantConfigVersion{}, %{
              assistant_id: assistant.id,
              organization_id: org_id,
              provider: "openai",
              model: "gpt-4o",
              prompt: "You are a helpful assistant.",
              settings: %{},
              status: :ready
            })
          )

        Repo.update!(
          Assistant.set_active_config_version_changeset(assistant, %{
            active_config_version_id: config_version.id
          })
        )

        {assistant, config_version}
      end)

    assert :ok = Erase.delete_organization_data(org_id)

    Enum.each(assistants_with_versions, fn {assistant, config_version} ->
      assert Repo.get(Assistant, assistant.id) == nil
      assert Repo.get(AssistantConfigVersion, config_version.id) == nil
    end)
  end

  test "delete_all_organization_data deletion order covers every org-scoped table" do
    # Guards against schema drift: if a new table with an organization_id column is
    # added without being appended to Erase.org_data_deletion_order/0, full org
    # deletion would silently leave its rows behind.
    %{rows: rows} =
      Repo.query!(
        """
        SELECT table_name
        FROM information_schema.columns
        WHERE column_name = 'organization_id'
          AND table_schema = 'public'
          AND table_name != 'organizations'
        """,
        [],
        skip_organization_id: true
      )

    schema_tables = MapSet.new(rows, fn [table] -> table end)
    listed_tables = MapSet.new(Erase.org_data_deletion_order())

    assert [] == MapSet.difference(schema_tables, listed_tables) |> Enum.sort(),
           "org-scoped tables missing from Erase.org_data_deletion_order/0"

    assert [] == MapSet.difference(listed_tables, schema_tables) |> Enum.sort(),
           "Erase.org_data_deletion_order/0 lists tables that no longer exist"
  end

  test "delete_all_organization_data deletes whatsapp_form_revisions that reference a user",
       %{organization_id: organization_id} do
    # whatsapp_form_revisions.user_id is a NOT NULL column with an ON DELETE SET NULL
    # FK to users, so the revision must be deleted before users — and before contacts,
    # which cascade-deletes users. Regression test: full deletion previously failed
    # here with a not-null violation when contacts/users were deleted first.
    Fixtures.whatsapp_form_fixture()

    {:ok, organization} = Repo.fetch(Organization, organization_id, skip_organization_id: true)
    {:ok, _deleted} = Glific.Partners.delete_organization(organization)

    assert :ok = Erase.delete_all_organization_data(organization_id)

    assert 0 == count_for_org("whatsapp_form_revisions", organization_id)
    assert 0 == count_for_org("users", organization_id)
  end

  defp count_for_org(table, organization_id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM #{table} WHERE organization_id = $1", [organization_id],
        skip_organization_id: true
      )

    count
  end
end
