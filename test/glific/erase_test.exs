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

  test "deletes data from every org-scoped table while leaving the survivor org intact", %{
    organization_id: org1_id
  } do
    org2 = Fixtures.organization_fixture(%{status: :ready_to_delete})

    tables = org_scoped_tables()

    # Seed exactly one row per org-scoped table for org2 (dependencies are created
    # transitively, e.g. inserting "messages" first creates the "contacts" row it needs).
    Enum.each(tables, &ensure_row(&1, org2.id))

    # Snapshot org1's row counts before deletion, to prove org1 is left untouched.
    org1_counts_before = count_rows_per_table(tables, org1_id)

    # Run the deletion.
    assert {:ok, job} = Erase.delete_organization(org2.id)
    assert :ok = perform_job(Erase, job.args)

    # org2 row is preserved (soft-delete marker), not hard-deleted.
    {:ok, deleted_org2} =
      Repo.fetch(Organization, org2.id, skip_organization_id: true, include_deleted: true)

    assert deleted_org2.deleted_at != nil

    # Every org-scoped table must have zero rows for org2 after deletion.
    org2_counts_after = count_rows_per_table(tables, org2.id)

    for {table, count} <- org2_counts_after do
      assert count == 0, "Expected 0 rows in #{table} for org2, found #{count}"
    end

    # org1 data must be completely unaffected, in every org-scoped table.
    org1_counts_after = count_rows_per_table(tables, org1_id)

    for table <- tables do
      assert org1_counts_after[table] == org1_counts_before[table],
             "Org1 row count in #{table} changed after org2 deletion: " <>
               "#{org1_counts_before[table]} → #{org1_counts_after[table]}"
    end
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

  # ── Generic org-scoped table seeding helpers ────────────────────────────
  #
  # Discovers every table with an organization_id column (mirroring exactly
  # what delete_organization_data targets) and inserts one minimal valid row
  # per table for a given org, resolving FK dependencies recursively via raw
  # catalog introspection. This keeps the test in sync automatically as new
  # org-scoped tables are added, instead of hand-maintaining a fixture list.

  # Returns every public-schema table that has an organization_id column, i.e.
  # the exact table set delete_organization_data operates on.
  @spec org_scoped_tables() :: [String.t()]
  defp org_scoped_tables do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT DISTINCT table_name
      FROM information_schema.columns
      WHERE column_name = 'organization_id'
        AND table_schema = 'public'
        AND table_name != 'organizations'
      ORDER BY table_name
      """)

    Enum.map(rows, fn [table] -> table end)
  end

  # Counts rows for the given organization_id in each of the given tables,
  # returning a %{table_name => count} map. Used to snapshot/compare counts
  # before and after deletion (for both the deleted org and the survivor org).
  @spec count_rows_per_table([String.t()], non_neg_integer()) :: %{String.t() => integer()}
  defp count_rows_per_table(tables, organization_id) do
    Map.new(tables, fn table ->
      {:ok, %{rows: [[count]]}} =
        Repo.query("SELECT count(*) FROM #{table} WHERE organization_id = $1", [
          organization_id
        ])

      {table, count}
    end)
  end

  # Looks up every foreign-key column on the given table via pg_constraint and
  # returns a %{column_name => referenced_table} map (referenced_table comes
  # back schema-qualified, e.g. "global.permissions", when outside public).
  # Used to figure out which other table must have a row created first before
  # a given column can be filled in.
  @spec fk_columns(String.t()) :: %{String.t() => String.t()}
  defp fk_columns(table) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT a.attname AS column_name, con.confrelid::regclass::text AS ref_table
        FROM pg_constraint con
        CROSS JOIN LATERAL
          unnest(con.conkey) WITH ORDINALITY AS u(local_attnum, ord)
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = u.local_attnum
        WHERE con.contype = 'f' AND con.conrelid = to_regclass($1)
        """,
        [table]
      )

    Map.new(rows, fn [column, ref_table] -> {column, ref_table} end)
  end

  # Returns [column_name, data_type, udt_name] for every column on the given
  # table that is NOT NULL with no DB-level default — i.e. every column that
  # an INSERT must supply a value for. Accepts a plain table name or a
  # schema-qualified one (e.g. "global.permissions").
  @spec required_columns(String.t()) :: [[String.t()]]
  defp required_columns(table) do
    {schema, bare_table} =
      case String.split(table, ".", parts: 2) do
        [schema, bare_table] -> {schema, bare_table}
        [bare_table] -> {"public", bare_table}
      end

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT column_name, data_type, udt_name
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2
          AND is_nullable = 'NO' AND column_default IS NULL
          AND column_name != 'id'
        """,
        [schema, bare_table]
      )

    rows
  end

  # Returns the first valid label of a real Postgres enum type (e.g.
  # whatsapp_forms_status_enum), or nil if udt_name isn't an enum type at all.
  # Needed for columns declared with a Postgres ENUM rather than plain text,
  # since any other string would violate the type.
  @spec enum_label(String.t()) :: String.t() | nil
  defp enum_label(udt_name) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT e.enumlabel FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        WHERE t.typname = $1
        ORDER BY e.enumsortorder LIMIT 1
        """,
        [udt_name]
      )

    case rows do
      [[label]] -> label
      [] -> nil
    end
  end

  # Returns an id to use for an FK pointing at a non-org-scoped (global) table,
  # e.g. languages or providers. Global lookup tables are usually pre-seeded,
  # so this normally just grabs an existing row; if one is genuinely empty in
  # this test DB (e.g. global.permissions), it creates a minimal row instead
  # of failing. Caches the resolved id per table for the rest of the test.
  @spec global_lookup_id(String.t()) :: integer()
  defp global_lookup_id(table) do
    case Process.get({:global_id_cache, table}) do
      nil ->
        id = existing_global_row_id(table) || create_global_row(table)
        Process.put({:global_id_cache, table}, id)
        id

      id ->
        id
    end
  end

  # Returns the id of any existing row in a global (non-org-scoped) table, or
  # nil if the table has no rows at all.
  @spec existing_global_row_id(String.t()) :: integer() | nil
  defp existing_global_row_id(table) do
    {:ok, %{rows: rows}} = Repo.query("SELECT id FROM #{table} ORDER BY id LIMIT 1")

    case rows do
      [[id]] -> id
      [] -> nil
    end
  end

  # Inserts a minimal valid row into a global (non-org-scoped) table by
  # filling every required column with a dummy value (recursing into
  # global_lookup_id for any of its own FK columns), and returns the new id.
  @spec create_global_row(String.t()) :: integer()
  defp create_global_row(table) do
    fk_map = fk_columns(table)

    {columns, values} =
      table
      |> required_columns()
      |> Enum.map(fn [column, data_type, udt_name] ->
        value =
          if Map.has_key?(fk_map, column) do
            global_lookup_id(fk_map[column])
          else
            dummy_scalar(column, data_type, udt_name)
          end

        {column, value}
      end)
      |> Enum.unzip()

    placeholders = values |> Enum.with_index(1) |> Enum.map_join(", ", fn {_v, i} -> "$#{i}" end)
    column_list = Enum.join(columns, ", ")

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        "INSERT INTO #{table} (#{column_list}) VALUES (#{placeholders}) RETURNING id",
        values
      )

    id
  end

  # Generates a placeholder value for a required, non-FK column, picked
  # purely from its Postgres data_type/udt_name (column name is only used as
  # a fallback to make the value recognizable). Each clause below handles one
  # data_type family so a new type just needs a new clause, not a bigger
  # conditional.
  @spec dummy_scalar(String.t(), String.t(), String.t()) :: term()
  defp dummy_scalar(_column, "boolean", _udt_name), do: false

  defp dummy_scalar(_column, type, _udt_name) when type in ["integer", "bigint", "smallint"],
    do: 1

  defp dummy_scalar(_column, type, _udt_name)
       when type in ["numeric", "double precision", "real"],
       do: 1

  defp dummy_scalar(_column, "uuid", _udt_name), do: Ecto.UUID.bingenerate()
  defp dummy_scalar(_column, type, _udt_name) when type in ["jsonb", "json"], do: %{}
  defp dummy_scalar(_column, "date", _udt_name), do: Date.utc_today()

  defp dummy_scalar(_column, type, _udt_name)
       when type in ["timestamp without time zone", "timestamp with time zone"] do
    NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
  end

  defp dummy_scalar(_column, "inet", _udt_name), do: "127.0.0.1"
  defp dummy_scalar(_column, "ARRAY", _udt_name), do: []

  # "USER-DEFINED" covers real Postgres enum/domain types (e.g. citext); try
  # to resolve a real enum label first, otherwise fall back to plain text.
  defp dummy_scalar(column, "USER-DEFINED", udt_name),
    do: enum_label(udt_name) || "test_#{column}"

  # Fallback for any other type (varchar, text, citext, etc.) — a short,
  # unique-ish string so it doesn't collide with unique constraints.
  defp dummy_scalar(column, _data_type, _udt_name) do
    "test_#{column}_#{String.slice(Ecto.UUID.generate(), 0, 8)}"
  end

  # Returns the id of the org-scoped row for `table`/`organization_id`,
  # creating it (and any FK dependencies it needs) on first call. Subsequent
  # calls for the same table return the cached id instead of inserting again
  # — this is what lets the dependency recursion in insert_row/2 call back
  # into this function freely without ever double-inserting a table.
  @spec ensure_row(String.t(), non_neg_integer()) :: integer()
  defp ensure_row(table, organization_id) do
    case Process.get({:row_cache, table}) do
      nil -> create_row(table, organization_id)
      id -> id
    end
  end

  # Resolves the row to use for table/organization_id: reuses one if it
  # already exists (e.g. organization_fixture already created a contact or
  # credential row), otherwise inserts a fresh one.
  @spec create_row(String.t(), non_neg_integer()) :: integer()
  defp create_row(table, organization_id) do
    case existing_row_id(table, organization_id) do
      nil ->
        insert_row(table, organization_id)

      id ->
        Process.put({:row_cache, table}, id)
        id
    end
  end

  # Some org-scoped rows already exist as a side effect of organization_fixture
  # (e.g. credentials, users, contacts) — reuse them instead of inserting a
  # conflicting duplicate.
  @spec existing_row_id(String.t(), non_neg_integer()) :: integer() | nil
  defp existing_row_id(table, organization_id) do
    {:ok, %{rows: rows}} =
      Repo.query("SELECT id FROM #{table} WHERE organization_id = $1 LIMIT 1", [
        organization_id
      ])

    case rows do
      [[id]] -> id
      [] -> nil
    end
  end

  # Inserts one fresh, minimal valid row into `table` for `organization_id`
  # and returns its new id. Builds the row by walking every NOT-NULL column
  # (from required_columns/1) and, for each one:
  #   - "organization_id" -> the org being seeded
  #   - an FK to "organizations" -> the same org id
  #   - an FK to another org-scoped table -> ensure_row/2 for that table,
  #     recursing (and transitively creating) whatever it depends on
  #   - an FK to a non-org-scoped table -> global_lookup_id/1
  #   - anything else -> dummy_scalar/3 picks a type-appropriate placeholder
  # Tracks {:in_progress, table} for the duration of the call so that a true
  # circular NOT NULL FK (which the production delete_organization_data
  # function would also be unable to resolve) raises a clear error instead of
  # recursing forever.
  @spec insert_row(String.t(), non_neg_integer()) :: integer()
  defp insert_row(table, organization_id) do
    if Process.get({:in_progress, table}) do
      raise "Unbreakable FK cycle detected involving #{table} " <>
              "(NOT NULL FK back to a table still being created)"
    end

    Process.put({:in_progress, table}, true)
    org_scoped = org_scoped_tables()
    fk_map = fk_columns(table)

    {columns, values} =
      table
      |> required_columns()
      |> Enum.map(fn [column, data_type, udt_name] ->
        value =
          cond do
            column == "organization_id" ->
              organization_id

            Map.has_key?(fk_map, column) ->
              ref_table = fk_map[column]

              cond do
                ref_table == "organizations" -> organization_id
                ref_table in org_scoped -> ensure_row(ref_table, organization_id)
                true -> global_lookup_id(ref_table)
              end

            true ->
              dummy_scalar(column, data_type, udt_name)
          end

        {column, value}
      end)
      |> Enum.unzip()

    placeholders = values |> Enum.with_index(1) |> Enum.map_join(", ", fn {_v, i} -> "$#{i}" end)
    column_list = Enum.join(columns, ", ")

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        "INSERT INTO #{table} (#{column_list}) VALUES (#{placeholders}) RETURNING id",
        values
      )

    Process.put({:row_cache, table}, id)
    Process.delete({:in_progress, table})
    id
  end
end
