defmodule Glific.BigQuery.BigQueryWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a bigquery Worker Job to deliver the message to
  the bigquery servers

  We centralize both the cron job and the worker job in one module
  """

  @doc """
  we are using this module to sync the data from the postgres database to bigquery. Before that you need to create a database schema for the query for more info
  go to bigquery_schema.ex file and create a schema for the table.
  """

  import Ecto.Query

  require Logger
  use Publicist

  use Oban.Worker,
    queue: :bigquery,
    max_attempts: 1,
    priority: 1

  alias Glific.{
    BigQuery,
    Contacts,
    Contacts.Contact,
    Contacts.ContactHistory,
    Flows,
    Flows.Flow,
    Flows.FlowCount,
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.MessageBroadcast,
    Flows.MessageBroadcastContact,
    Groups.Group,
    Jobs,
    Messages.Message,
    Messages.MessageConversation,
    Messages.MessageMedia,
    Partners,
    Profiles.Profile,
    Repo,
    Stats.Stat,
    Tickets.Ticket,
    Trackers.Tracker,
    Users.User,
    WAGroup.WAMessage
  }

  @per_min_limit 500

  @doc """
  This is called from the cron job on a regular schedule. we sweep the messages table
  and queue them up for delivery to bigquery
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(org_id) do
    if BigQuery.active?(org_id) do
      Logger.info("Found bigquery credentials for org_id: #{org_id}")

      Jobs.get_bigquery_jobs(org_id)
      |> Enum.each(&init_insert_job(&1, org_id))
    end

    :ok
  end

  @doc """
  This is called from the cron job on a regular schedule. We updates existing tables
  """
  @spec periodic_updates(non_neg_integer) :: :ok
  def periodic_updates(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services["bigquery"]

    if credential do
      [
        "contacts",
        "messages",
        "flow_results",
        "flow_counts",
        "messages_media",
        "flow_contexts",
        "profiles",
        "message_broadcasts",
        "message_broadcast_contacts",
        "tickets",
        "wa_messages"
      ]
      |> Enum.each(&init_removal_job(&1, organization_id))
    end

    :ok
  end

  @spec init_insert_job(BigQuery.BigQueryJob.t() | nil, non_neg_integer) :: any()
  defp init_insert_job(bq_job, org_id) do
    [:insert, :update]
    |> Enum.each(fn action ->
      __MODULE__.new(%{
        table: bq_job.table,
        organization_id: org_id,
        action: action
      })
      |> Oban.insert()
    end)
  end

  defp init_removal_job(table, org_id) do
    __MODULE__.new(%{
      table: table,
      organization_id: org_id,
      remove_duplicates: true
    })
    |> Oban.insert()
  end

  @impl Oban.Worker
  @doc """
  Standard perform method to use Oban worker
  """
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(
        %Oban.Job{
          args: %{
            "table" => table,
            "organization_id" => organization_id,
            "remove_duplicates" => true
          }
        } = _job
      ) do
    Repo.put_process_state(organization_id)
    Logger.info("removing duplicates for org_id: #{organization_id} table: #{table}")
    BigQuery.make_job_to_remove_duplicate(table, organization_id)
    :ok
  end

  def perform(
        %Oban.Job{
          args: %{"table" => table, "organization_id" => organization_id, "action" => action}
        } = _job
      ) do
    Repo.put_process_state(organization_id)

    Jobs.get_bigquery_job(organization_id, table)
    |> insert_for_table(organization_id, action)
  end

  @spec format_date_with_millisecond(DateTime.t(), non_neg_integer()) :: String.t()
  defp format_date_with_millisecond(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}{ss}")
  end

  @spec insert_max_id(String.t(), non_neg_integer, non_neg_integer) :: non_neg_integer
  defp insert_max_id(table_name, table_id, organization_id) do
    Logger.info("Checking for bigquery job for org_id: #{organization_id} table: #{table_name}")

    max_id =
      BigQuery.get_table_struct(table_name)
      |> where([m], m.id > ^table_id)
      |> add_organization_id(table_name, organization_id)
      |> order_by([m], m.id)
      |> limit(@per_min_limit)
      |> Repo.aggregate(:max, :id)

    if is_nil(max_id),
      do: table_id,
      else: max_id
  end

  @spec insert_last_updated(String.t(), DateTime.t() | nil, non_neg_integer) :: DateTime.t()
  defp insert_last_updated(table_name, table_last_updated_at, organization_id) do
    Logger.info(
      "Checking for bigquery job for org_id: #{organization_id} table: #{table_name} since: #{table_last_updated_at}"
    )

    max_last_update =
      BigQuery.get_table_struct(table_name)
      |> where([tb], tb.updated_at > ^table_last_updated_at)
      |> where(
        [tb],
        ## Adding clause so that we don't pick the newly inserted rows.
        fragment("DATE_PART('seconds', age(?, ?))::integer", tb.updated_at, tb.inserted_at) > 0
      )
      |> add_organization_id(table_name, organization_id)
      |> order_by([tb], [tb.updated_at, tb.id])
      |> limit(@per_min_limit)
      |> Repo.aggregate(:max, :updated_at, timeout: 40_000)

    if is_nil(max_last_update),
      do: table_last_updated_at,
      else: max_last_update
  end

  @spec insert_for_table(BigQuery.BigQueryJob.t() | nil, non_neg_integer, String.t()) ::
          :ok | nil
  defp insert_for_table(nil, _, _), do: nil

  defp insert_for_table(
         %{table: table, table_id: table_id, last_updated_at: table_last_updated_at} = _job,
         organization_id,
         action
       ) do
    if action == "update" do
      insert_updated_records(table, table_last_updated_at, organization_id)
    else
      insert_new_records(table, table_id, table_last_updated_at, organization_id)
    end

    :ok
  end

  @spec insert_new_records(binary, non_neg_integer, DateTime.t() | nil, non_neg_integer) :: :ok
  defp insert_new_records(table, table_id, table_last_updated_at, organization_id) do
    max_id = insert_max_id(table, table_id, organization_id)

    if max_id > table_id,
      do:
        queue_table_data(table, organization_id, %{
          min_id: table_id,
          max_id: max_id,
          action: :insert,
          last_updated_at: table_last_updated_at
        })

    :ok
  end

  @spec insert_updated_records(binary, DateTime.t() | nil, non_neg_integer) :: :ok
  defp insert_updated_records(table, table_last_updated_at, organization_id) do
    if table in BigQuery.ignore_updates_for_table() do
      :ok
    else
      table_last_updated_at = table_last_updated_at || DateTime.utc_now()
      last_updated_at = insert_last_updated(table, table_last_updated_at, organization_id)

      queue_table_data(table, organization_id, %{
        action: :update,
        max_id: nil,
        last_updated_at: last_updated_at,
        table_last_updated_at: table_last_updated_at
      })
    end
  end

  @spec add_organization_id(Ecto.Query.t(), String.t(), non_neg_integer) :: Ecto.Query.t()
  defp add_organization_id(query, "stats_all", _organization_id),
    do: query

  defp add_organization_id(query, "trackers_all", _organization_id),
    do: query

  defp add_organization_id(query, _table, organization_id),
    do: query |> where([m], m.organization_id == ^organization_id)

  ## ignore the tables for updates.
  @spec queue_table_data(String.t(), non_neg_integer(), map()) :: :ok
  defp queue_table_data(table, _organization_id, %{action: :update, max_id: nil} = _attrs)
       when table in ["flows", "stats", "stats_all"],
       do: :ok

  defp queue_table_data("messages", organization_id, attrs) do
    Logger.info(
      "fetching messages data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("messages", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce([], fn row, acc ->
      [
        row
        |> get_message_row(organization_id)
        |> Map.merge(bq_fields(organization_id))
        |> then(&%{json: &1})
        | acc
      ]
    end)
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :messages, organization_id, attrs))

    :ok
  end

  defp queue_table_data("message_broadcast_contacts", organization_id, attrs) do
    Logger.info(
      "fetching message_broadcast_contacts data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("message_broadcast_contacts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            message_broadcast_id: row.id,
            phone: row.phone,
            status: row.status,
            processed_at: BigQuery.format_date(row.processed_at, organization_id),
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :message_broadcast_contacts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("message_broadcasts", organization_id, attrs) do
    Logger.info(
      "fetching message_broadcasts data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("message_broadcasts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            flow_id: row.id,
            flow_name: row.flow_name,
            user_id: row.user_id,
            user_phone: row.user_phone,
            group_id: row.group_id,
            group_name: row.group_name,
            broadcast_type: row.broadcast_type,
            message_params: BigQuery.format_json(row.message_params),
            started_at: BigQuery.format_date(row.started_at, organization_id),
            completed_at: BigQuery.format_date(row.completed_at, organization_id),
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :message_broadcasts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("contacts", organization_id, attrs) do
    Logger.info(
      "fetching contacts data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("contacts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        if Contacts.simulator_contact?(row.phone),
          do: acc,
          else: [
            # We are sending nil, as setting is a record type and need to structure the data first(like field)
            %{
              id: row.id,
              name: row.name,
              phone: row.phone,
              provider_status: row.bsp_status,
              status: row.status,
              language: row.language.label,
              optin_time: BigQuery.format_date(row.optin_time, organization_id),
              optout_time: BigQuery.format_date(row.optout_time, organization_id),
              contact_optin_method: row.optin_method,
              last_message_at: BigQuery.format_date(row.last_message_at, organization_id),
              inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
              updated_at: format_date_with_millisecond(row.updated_at, organization_id),
              fields:
                Enum.map(row.fields, fn {_key, field} ->
                  %{
                    label: field["label"],
                    inserted_at: BigQuery.format_date(field["inserted_at"], organization_id),
                    type: field["type"],
                    value: field["value"]
                  }
                end),
              settings: nil,
              user_name: if(!is_nil(row.user), do: row.user.name),
              user_role: if(!is_nil(row.user), do: BigQuery.format_json(row.user.roles)),
              groups:
                Enum.map(row.groups, fn group ->
                  %{label: group.label, description: group.description}
                end),
              tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end),
              raw_fields: BigQuery.format_json(row.fields),
              group_labels: Enum.map_join(row.groups, ",", &Map.get(&1, :label))
            }
            |> Map.merge(bq_fields(organization_id))
            |> then(&%{json: &1})
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :contacts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("profiles", organization_id, attrs) do
    # This function will fetch all the profiles from the database and will insert it in bigquery in chunks of 100.
    Logger.info(
      "fetching profiles data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("profiles", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            name: row.name,
            type: row.type,
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id),
            phone: row.contact.phone,
            language: row.language.label,
            fields:
              Enum.map(row.fields, fn {_key, field} ->
                %{
                  label: field["label"],
                  inserted_at: BigQuery.format_date(field["inserted_at"], organization_id),
                  type: field["type"],
                  value: field["value"]
                }
              end)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :profiles, organization_id, attrs))

    :ok
  end

  defp queue_table_data("contact_histories", organization_id, attrs) do
    Logger.info(
      "fetching contact_histories data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("contact_histories", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            event_type: row.event_type,
            event_label: row.event_label,
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id),
            event_datetime: BigQuery.format_date(row.event_datetime, organization_id),
            phone: row.contact.phone,
            profile_id: row.profile_id
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :contact_histories, organization_id, attrs))

    :ok
  end

  defp queue_table_data("message_conversations", organization_id, attrs) do
    Logger.info(
      "fetching message_conversations data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("message_conversations", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            conversation_uuid: row.conversation_id,
            deduction_type: row.deduction_type,
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id),
            is_billable: row.is_billable,
            message_id: row.message_id,
            payload: BigQuery.format_json(row.payload),
            phone: row.phone
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :message_conversations, organization_id, attrs))

    :ok
  end

  defp queue_table_data("flows", organization_id, attrs) do
    Logger.info(
      "fetching flows data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("flows", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            name: row.flow.name,
            uuid: row.flow.uuid,
            inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
            updated_at: format_date_with_millisecond(row.updated_at, organization_id),
            keywords: BigQuery.format_json(row.flow.keywords),
            status: row.status,
            revision: BigQuery.format_json(row.definition),
            tag: if(!is_nil(row.flow.tag), do: row.flow.tag.label)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flows, organization_id, attrs))

    :ok
  end

  defp queue_table_data("flow_results", organization_id, attrs) do
    Logger.info(
      "fetching flow_results data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("flow_results", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        if Contacts.simulator_contact?(row.contact.phone),
          do: acc,
          else: [
            %{
              id: row.id,
              name: row.flow.name,
              uuid: row.flow.uuid,
              inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
              updated_at: format_date_with_millisecond(row.updated_at, organization_id),
              results: BigQuery.format_json(row.results),
              contact_phone: row.contact.phone,
              contact_name: row.contact.name,
              flow_version: row.flow_version,
              flow_context_id: row.flow_context_id,
              profile_id: row.profile_id
            }
            |> Map.merge(bq_fields(organization_id))
            |> then(&%{json: &1})
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flow_results, organization_id, attrs))

    :ok
  end

  defp queue_table_data("flow_counts", organization_id, attrs) do
    Logger.info(
      "fetching flow_counts data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("flow_counts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            source_uuid: row.uuid,
            destination_uuid: row.destination_uuid,
            flow_name: row.flow.name,
            flow_uuid: row.flow.uuid,
            type: row.type,
            count: row.count,
            recent_messages: BigQuery.format_json(row.recent_messages),
            inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
            updated_at: format_date_with_millisecond(row.updated_at, organization_id)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flow_counts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("messages_media", organization_id, attrs) do
    Logger.info(
      "fetching messages_media data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("messages_media", organization_id, attrs)
    |> Repo.all()
    |> queue_message_media_data(organization_id, attrs)

    :ok
  end

  defp queue_table_data("flow_contexts", organization_id, attrs) do
    Logger.info(
      "fetching flow_contexts data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("flow_contexts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          # We are sending nil, as setting is a record type and need to structure the data first(like field)
          %{
            id: row.id,
            node_uuid: row.node_uuid,
            flow_uuid: row.flow.uuid,
            flow_id: row.flow.id,
            flow_name: row.flow.name,
            contact_id: if(!is_nil(row.contact), do: row.contact.id),
            contact_phone: if(!is_nil(row.contact), do: row.contact.phone),
            results: BigQuery.format_json(row.results),
            recent_inbound: BigQuery.format_json(row.recent_inbound),
            recent_outbound: BigQuery.format_json(row.recent_outbound),
            status: row.status,
            parent_id: row.parent_id,
            message_broadcast_id: row.message_broadcast_id,
            is_background_flow: row.is_background_flow,
            is_await_result: row.is_await_result,
            is_killed: row.is_killed,
            profile_id: row.profile_id,
            wa_group_id: if(!is_nil(row.wa_group), do: row.wa_group.id),
            wa_group_name: if(!is_nil(row.wa_group), do: row.wa_group.label),
            wa_group_bsp_id: if(!is_nil(row.wa_group), do: row.wa_group.bsp_id),
            wakeup_at: BigQuery.format_date(row.wakeup_at, organization_id),
            completed_at: BigQuery.format_date(row.completed_at, organization_id),
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id),
            reason: row.reason
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flow_contexts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("tickets", organization_id, attrs) do
    Logger.info(
      "fetching tickets data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("tickets", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            body: row.body,
            topic: row.topic,
            status: row.status,
            remarks: row.remarks,
            contact_id: row.contact.id,
            contact_name: row.contact.name,
            contact_phone: row.contact.phone,
            user_id: if(!is_nil(row.user), do: row.user.id),
            user_name: if(!is_nil(row.user), do: row.user.name),
            user_phone: if(!is_nil(row.user), do: row.user.phone),
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :tickets, organization_id, attrs))

    :ok
  end

  defp queue_table_data("wa_messages", organization_id, attrs) do
    Logger.info(
      "fetching wa_messages data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    get_query("wa_messages", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            body: row.body,
            type: row.type,
            flow: row.flow,
            inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
            updated_at: format_date_with_millisecond(row.updated_at, organization_id),
            sent_at: BigQuery.format_date(row.sent_at, organization_id),
            uuid: row.uuid,
            status: row.status,
            contact_phone: row.contact.phone,
            contact_name: row.contact.name,
            errors: BigQuery.format_json(row.errors),
            message_broadcast_id: row.message_broadcast_id,
            bsp_status: row.bsp_status,
            wa_group_id: row.wa_group_id,
            wa_group_name: if(!is_nil(row.wa_group), do: row.wa_group.label)
          }
          |> Map.merge(message_media_info(row.media))
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :wa_messages, organization_id, attrs))

    :ok
  end

  defp queue_table_data(stat, organization_id, attrs) when stat in ["stats", "stats_all"] do
    Logger.info(
      "fetching #{stat} data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    stat_atom =
      if stat == "stats",
        do: :stats,
        else: :stats_all

    get_query(stat, organization_id, attrs)
    # for stats_all we specifically want to skip organization_id
    |> Repo.all(skip_organization_id: true)
    |> Enum.reduce(
      [],
      fn row, acc ->
        additional =
          if stat == "stats_all",
            do: %{
              organization_id: row.organization_id,
              organization_name: row.organization.name,
              organization_status: row.organization.status
            },
            else: %{}

        [
          %{
            id: row.id,
            contacts: row.contacts,
            active: row.active,
            optin: row.optin,
            optout: row.optout,
            messages: row.messages,
            inbound: row.inbound,
            outbound: row.outbound,
            hsm: row.hsm,
            flows_started: row.flows_started,
            flows_completed: row.flows_completed,
            users: row.users,
            period: row.period,
            date: Date.to_string(row.date),
            hour: row.hour,
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id),
            conversations: row.conversations
          }
          |> Map.merge(additional)
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, stat_atom, organization_id, attrs))

    :ok
  end

  defp queue_table_data(tracker, organization_id, attrs)
       when tracker in ["trackers", "trackers_all"] do
    Logger.info(
      "fetching #{tracker} data for org_id: #{organization_id} to send on bigquery with attrs: #{inspect(attrs)}"
    )

    tracker_atom =
      if tracker == "trackers",
        do: :trackers,
        else: :trackers_all

    get_query(tracker, organization_id, attrs)
    # for tracker_all we specifically want to skip organization_id
    |> Repo.all(skip_organization_id: true)
    |> Enum.reduce(
      [],
      fn row, acc ->
        additional =
          if tracker == "trackers_all",
            do: %{
              organization_id: row.organization_id,
              organization_name: row.organization.name
            },
            else: %{}

        [
          %{
            id: row.id,
            period: row.period,
            date: Date.to_string(row.date),
            counts: BigQuery.format_json(row.counts),
            inserted_at: BigQuery.format_date(row.inserted_at, organization_id),
            updated_at: BigQuery.format_date(row.updated_at, organization_id)
          }
          |> Map.merge(additional)
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, tracker_atom, organization_id, attrs))

    :ok
  end

  defp queue_table_data(_, _, _), do: :ok

  @spec bq_fields(non_neg_integer) :: map()
  defp bq_fields(org_id) do
    %{
      bq_uuid: Ecto.UUID.generate(),
      bq_inserted_at: format_date_with_millisecond(DateTime.utc_now(), org_id)
    }
  end

  @doc """
  Moving this logic to a different function so that we can reuse it
  for gcs worker also.
  """
  @spec queue_message_media_data(list(), non_neg_integer(), map()) :: :ok
  def queue_message_media_data(media_list, organization_id, attrs) do
    media_list
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          # We are sending nil, as setting is a record type and need to structure the data first(like field)
          %{
            id: row.id,
            caption: row.caption,
            url: row.url,
            source_url: row.source_url,
            content_type: row.content_type,
            gcs_url: row.gcs_url,
            inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
            updated_at: format_date_with_millisecond(row.updated_at, organization_id)
          }
          |> Map.merge(bq_fields(organization_id))
          |> then(&%{json: &1})
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :messages_media, organization_id, attrs))
  end

  @spec get_message_row(atom | map(), non_neg_integer) :: map()
  defp get_message_row(row, organization_id),
    do:
      %{
        id: row.id,
        body: row.body,
        type: row.type,
        flow: row.flow,
        inserted_at: format_date_with_millisecond(row.inserted_at, organization_id),
        updated_at: format_date_with_millisecond(row.updated_at, organization_id),
        sent_at: BigQuery.format_date(row.sent_at, organization_id),
        uuid: row.uuid,
        status: row.status,
        sender_phone: row.sender.phone,
        receiver_phone: row.receiver.phone,
        contact_phone: row.contact.phone,
        contact_name: row.contact.name,
        profile_id: row.profile_id,
        user_phone: if(!is_nil(row.user), do: row.user.phone),
        user_name: if(!is_nil(row.user), do: row.user.name),
        tags_label: Enum.map_join(row.tags, ", ", fn tag -> tag.label end),
        flow_label: row.flow_label,
        flow_uuid: if(!is_nil(row.flow_object), do: row.flow_object.uuid),
        flow_name: if(!is_nil(row.flow_object), do: row.flow_object.name),
        longitude: if(!is_nil(row.location), do: row.location.longitude),
        latitude: if(!is_nil(row.location), do: row.location.latitude),
        errors: BigQuery.format_json(row.errors),
        message_broadcast_id: row.message_broadcast_id,
        bsp_status: row.bsp_status,
        group_id: row.group_id,
        group_name: if(!is_nil(row.group), do: row.group.label)
      }
      |> Map.merge(message_media_info(row.media))
      |> Map.merge(message_template_info(row))

  @spec message_media_info(any()) :: map()
  defp message_media_info(nil),
    do: %{
      media_id: nil,
      media_url: nil,
      gcs_url: nil
    }

  defp message_media_info(media),
    do: %{
      media_id: media.id,
      media_url: media.url,
      gcs_url: media.gcs_url
    }

  ## have to right this function since the above one is too long and credo is giving a warning

  @spec message_template_info(atom | map()) :: map()
  defp message_template_info(row),
    do: %{
      is_hsm: row.is_hsm,
      template_uuid: if(!is_nil(row.template), do: row.template.uuid),
      interactive_template_id: row.interactive_template_id,
      context_message_id: row.context_message_id
    }

  @spec make_job(list(), atom(), non_neg_integer, map()) :: any
  defp make_job(data, table, organization_id, %{action: :insert} = attrs)
       when data in [%{}, nil, []] do
    table = Atom.to_string(table)

    if is_integer(attrs[:max_id]) == true,
      do: Jobs.update_bigquery_job(organization_id, table, %{table_id: attrs[:max_id]})
  end

  defp make_job(data, table, organization_id, %{action: :update} = attrs)
       when data in [%{}, nil, []] do
    table = Atom.to_string(table)

    if is_nil(attrs[:last_updated_at]) == false,
      do:
        Jobs.update_bigquery_job(organization_id, table, %{
          last_updated_at: attrs[:last_updated_at]
        })
  end

  defp make_job(data, table, organization_id, attrs) do
    Logger.info(
      "making a new job for org_id: #{organization_id} table: #{table} to send on bigquery with max id: #{inspect(attrs)}"
    )

    table = Atom.to_string(table)
    max_id = attrs[:max_id]

    last_updated_at =
      if is_nil(attrs[:last_updated_at]) do
        Logger.error(
          "last_updated_at is NIL for #{organization_id} and table: #{table}  Setting DB to one day older."
        )

        Timex.now()
        |> Timex.shift(days: -1)
        |> Timex.to_datetime()
      else
        attrs[:last_updated_at]
      end

    BigQuery.make_insert_query(data, table, organization_id,
      max_id: max_id,
      last_updated_at: last_updated_at
    )
  end

  @spec apply_action_clause(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp apply_action_clause(query, %{action: :insert, max_id: max_id, min_id: min_id} = _attrs),
    do: query |> where([m], m.id >= ^min_id and m.id <= ^max_id)

  defp apply_action_clause(
         query,
         %{
           action: :update,
           last_updated_at: last_updated_at,
           table_last_updated_at: table_last_updated_at
         } = _attrs
       ),
       do:
         query
         |> where(
           [tb],
           tb.updated_at > ^table_last_updated_at and tb.updated_at <= ^last_updated_at
         )
         |> where(
           [tb],
           ## Adding clause so that we don't pick the newly inserted rows.
           fragment("DATE_PART('seconds', age(?, ?))::integer", tb.updated_at, tb.inserted_at) > 0
         )

  defp apply_action_clause(query, _attrs), do: query

  @spec get_query(String.t(), non_neg_integer, map()) :: Ecto.Queryable.t()
  defp get_query("messages", organization_id, attrs),
    do:
      Message
      |> where([m], m.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([
        :tags,
        :receiver,
        :sender,
        :contact,
        :user,
        :media,
        :flow_object,
        :location,
        :template,
        :group
      ])

  defp get_query("message_conversations", organization_id, attrs),
    do:
      MessageConversation
      |> join(:left, [mc], m in Message, as: :m, on: mc.message_id == m.id)
      |> join(:left, [m: m], c in Contact, as: :c, on: m.contact_id == c.id)
      |> select([mc, m, c], %{
        conversation_id: mc.conversation_id,
        deduction_type: mc.deduction_type,
        inserted_at: mc.inserted_at,
        updated_at: mc.updated_at,
        is_billable: mc.is_billable,
        payload: mc.payload,
        phone: c.phone,
        message_id: m.id,
        id: mc.id
      })
      |> where([mc], mc.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([mc], [mc.inserted_at, mc.id])

  defp get_query("message_broadcast_contacts", organization_id, attrs),
    do:
      MessageBroadcastContact
      |> join(:left, [mbc], c in Contact, as: :c, on: mbc.contact_id == c.id)
      |> select([mbc, c], %{
        id: mbc.id,
        message_broadcast_id: mbc.id,
        phone: c.phone,
        status: mbc.status,
        processed_at: mbc.processed_at,
        inserted_at: mbc.inserted_at,
        updated_at: mbc.updated_at
      })
      |> where([mbc], mbc.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([mbc], [mbc.inserted_at, mbc.id])

  defp get_query("message_broadcasts", organization_id, attrs),
    do:
      MessageBroadcast
      |> join(:left, [mb], f in Flow, as: :m, on: mb.flow_id == f.id)
      |> join(:left, [mb], u in User, as: :u, on: mb.user_id == u.id)
      |> join(:left, [mb], g in Group, as: :g, on: mb.group_id == g.id)
      |> select([mb, f, u, g], %{
        id: mb.id,
        flow_id: f.id,
        flow_name: f.name,
        user_id: u.id,
        user_phone: u.phone,
        group_id: g.id,
        group_name: g.label,
        broadcast_type: mb.type,
        message_params: mb.message_params,
        started_at: mb.started_at,
        completed_at: mb.completed_at,
        inserted_at: mb.inserted_at,
        updated_at: mb.updated_at
      })
      |> where([mb], mb.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([mb], [mb.inserted_at, mb.id])

  defp get_query("contacts", organization_id, attrs),
    do:
      Contact
      |> where([m], m.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:language, :tags, :groups, :user])

  defp get_query("contact_histories", organization_id, attrs),
    do:
      ContactHistory
      |> where([c], c.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([c], [c.inserted_at, c.id])
      |> preload([:contact])

  defp get_query("profiles", organization_id, attrs),
    # We are creating a query here with the fields which are required instead of loading all the data.
    do:
      Profile
      |> where([p], p.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([p], [p.inserted_at, p.id])
      |> preload([:language, :contact])

  defp get_query("flows", organization_id, attrs),
    do:
      FlowRevision
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> where([f], f.status in ["published", "archived"])
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, flow: [:tag]])

  defp get_query("flow_results", organization_id, attrs),
    do:
      FlowResult
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, :contact])

  defp get_query("flow_counts", organization_id, attrs),
    do:
      FlowCount
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow])

  defp get_query("messages_media", organization_id, attrs),
    do:
      MessageMedia
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:organization])

  defp get_query("flow_contexts", organization_id, attrs),
    do:
      Flows.FlowContext
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, :contact, :wa_group])

  defp get_query("tickets", organization_id, attrs),
    do:
      Ticket
      |> where([t], t.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([t], [t.inserted_at, t.id])
      |> preload([:user, :contact])

  defp get_query("stats", organization_id, attrs),
    do:
      Stat
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])

  defp get_query("stats_all", _organization_id, attrs),
    do:
      Stat
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:organization])

  defp get_query("trackers", organization_id, attrs),
    do:
      Tracker
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])

  defp get_query("trackers_all", _organization_id, attrs),
    do:
      Tracker
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:organization])

  defp get_query("wa_messages", organization_id, attrs),
    do:
      WAMessage
      |> where([wm], wm.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([wm], [wm.inserted_at, wm.id])
      |> preload([
        :contact,
        :media,
        :wa_group
      ])
end
