defmodule Glific.BigQuery.BigQueryWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a bigquery Worker Job to deliver the message to
  the bigquery servers

  We centralize both the cron job and the worker job in one module
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
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs,
    Messages.Message,
    Partners,
    Repo,
    Stats.Stat
  }

  @doc """
  This is called from the cron job on a regular schedule. we sweep the messages table
  and queue them up for delivery to bigquery
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services["bigquery"]

    if credential do
      Logger.info("Found bigquery credentials for org_id: #{organization_id}")

      Jobs.get_bigquery_jobs(organization_id)
      |> Enum.each(&insert_for_table(&1, organization_id))
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
      make_job_to_remove_duplicate("contacts", organization_id)
      make_job_to_remove_duplicate("messages", organization_id)
      make_job_to_remove_duplicate("flow_results", organization_id)
    end

    :ok
  end

  @spec format_date_with_milisecond(DateTime.t(), non_neg_integer()) :: String.t()
  defp format_date_with_milisecond(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}{ss}")
  end

  @spec insert_max_id(String.t(), non_neg_integer, non_neg_integer) :: non_neg_integer
  defp insert_max_id(table_name, table_id, organization_id) do
    Logger.info("Checking for bigquery job: #{table_name}, org_id: #{organization_id}")

    max_id =
      BigQuery.get_table_struct(table_name)
      |> where([m], m.id > ^table_id)
      |> add_organization_id(table_name, organization_id)
      |> order_by([m], asc: m.id)
      |> limit(500)
      |> Repo.aggregate(:max, :id, skip_organization_id: true)

    if is_nil(max_id),
      do: table_id,
      else: max_id
  end

  @spec insert_last_updated(String.t(), DateTime.t(), non_neg_integer) :: DateTime.t()
  defp insert_last_updated(table_name, table_last_updated_at, organization_id) do
    Logger.info(
      "Checking for bigquery job for last update: #{table_name}, org_id: #{organization_id}"
    )

    max_last_update =
      BigQuery.get_table_struct(table_name)
      |> where([m], m.updated_at > ^table_last_updated_at)
      |> add_organization_id(table_name, organization_id)
      |> order_by([m], asc: m.id)
      |> limit(500)
      |> Repo.aggregate(:max, :updated_at, skip_organization_id: true)

    if is_nil(max_last_update),
      do: table_last_updated_at,
      else: max_last_update
  end

  @spec insert_for_table(BigQuery.BigQueryJob.t() | nil, non_neg_integer) :: :ok | nil
  defp insert_for_table(nil, _), do: nil

  defp insert_for_table(
         %{table: table, table_id: table_id, last_updated_at: table_last_updated_at} = _job,
         organization_id
       ) do
    insert_new_records(table, table_id, organization_id)
    insert_updated_records(table, table_last_updated_at, organization_id)
    :ok
  end

  @spec insert_new_records(binary, non_neg_integer, non_neg_integer) :: :ok
  defp insert_new_records(table, table_id, organization_id) do
    max_id = insert_max_id(table, table_id, organization_id)

    if max_id > table_id,
      do:
        queue_table_data(table, organization_id, %{
          min_id: table_id,
          max_id: max_id,
          action: :insert
        })

    :ok
  end

  @spec insert_updated_records(binary, DateTime.t(), non_neg_integer) :: :ok
  defp insert_updated_records(table, table_last_updated_at, organization_id) do
    last_updated_at = insert_last_updated(table, table_last_updated_at, organization_id)

    if last_updated_at > table_last_updated_at,
      do:
        queue_table_data(table, organization_id, %{
          action: :update,
          max_id: nil,
          last_updated_at: last_updated_at
        })
  end

  @spec add_organization_id(Ecto.Query.t(), String.t(), non_neg_integer) :: Ecto.Query.t()
  defp add_organization_id(query, "stats_all", _organization_id),
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
      "fetching data for messages to send on bigquery attrs: #{inspect(attrs)}, org_id: #{
        organization_id
      }"
    )

    get_query("messages", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce([], fn row, acc ->
      [
        row
        |> get_message_row(organization_id)
        |> BigQuery.format_data_for_bigquery("messages")
        | acc
      ]
    end)
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :messages, organization_id, attrs))

    :ok
  end

  defp queue_table_data("contacts", organization_id, attrs) do
    Logger.info(
      "fetching data for contacts to send on bigquery attrs: #{inspect(attrs)} , org_id: #{
        organization_id
      }"
    )

    get_query("contacts", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        if Contacts.is_simulator_contact?(row.phone),
          do: acc,
          else: [
            # We are sending nil, as setting is a record type and need to structure the data first(like field)
            %{
              id: row.id,
              bq_uuid: Ecto.UUID.generate(),
              name: row.name,
              phone: row.phone,
              provider_status: row.bsp_status,
              status: row.status,
              language: row.language.label,
              optin_time: BigQuery.format_date(row.optin_time, organization_id),
              optout_time: BigQuery.format_date(row.optout_time, organization_id),
              contact_optin_method: row.optin_method,
              last_message_at: BigQuery.format_date(row.last_message_at, organization_id),
              inserted_at: format_date_with_milisecond(row.inserted_at, organization_id),
              updated_at: format_date_with_milisecond(row.updated_at, organization_id),
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
              tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end)
            }
            |> BigQuery.format_data_for_bigquery("contacts")
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :contacts, organization_id, attrs))

    :ok
  end

  defp queue_table_data("flows", organization_id, attrs) do
    Logger.info(
      "fetching data for flows to send on bigquery attrs: #{inspect(attrs)}, org_id: #{
        organization_id
      }"
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
            inserted_at: format_date_with_milisecond(row.inserted_at, organization_id),
            updated_at: format_date_with_milisecond(row.updated_at, organization_id),
            keywords: BigQuery.format_json(row.flow.keywords),
            status: row.status,
            revision: BigQuery.format_json(row.definition)
          }
          |> BigQuery.format_data_for_bigquery("flows")
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
      "fetching data for flow_results to send on bigquery attrs: #{inspect(attrs)}, org_id: #{
        organization_id
      }"
    )

    get_query("flow_results", organization_id, attrs)
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn row, acc ->
        if Contacts.is_simulator_contact?(row.contact.phone),
          do: acc,
          else: [
            %{
              id: row.id,
              bq_uuid: Ecto.UUID.generate(),
              name: row.flow.name,
              uuid: row.flow.uuid,
              inserted_at: format_date_with_milisecond(row.inserted_at, organization_id),
              updated_at: format_date_with_milisecond(row.updated_at, organization_id),
              results: BigQuery.format_json(row.results),
              contact_phone: row.contact.phone,
              contact_name: row.contact.name,
              flow_version: row.flow_version,
              flow_context_id: row.flow_context_id
            }
            |> BigQuery.format_data_for_bigquery("flow_results")
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flow_results, organization_id, attrs))

    :ok
  end

  defp queue_table_data(stat, organization_id, attrs) when stat in ["stats", "stats_all"] do
    Logger.info(
      "fetching data for #{stat} to send on bigquery attrs: #{inspect(attrs)}, org_id: #{
        organization_id
      }"
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
              organization_name: row.organization.name
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
            updated_at: BigQuery.format_date(row.updated_at, organization_id)
          }
          |> Map.merge(additional)
          |> BigQuery.format_data_for_bigquery(stat)
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, stat_atom, organization_id, attrs))

    :ok
  end

  defp queue_table_data(_, _, _), do: :ok

  defp get_message_row(row, organization_id),
    do: %{
      id: row.id,
      bq_uuid: Ecto.UUID.generate(),
      body: row.body,
      type: row.type,
      flow: row.flow,
      inserted_at: format_date_with_milisecond(row.inserted_at, organization_id),
      updated_at: format_date_with_milisecond(row.updated_at, organization_id),
      sent_at: BigQuery.format_date(row.sent_at, organization_id),
      uuid: row.uuid,
      status: row.status,
      sender_phone: row.sender.phone,
      receiver_phone: row.receiver.phone,
      contact_phone: row.contact.phone,
      contact_name: row.contact.name,
      user_phone: if(!is_nil(row.user), do: row.user.phone),
      user_name: if(!is_nil(row.user), do: row.user.name),
      tags_label: Enum.map(row.tags, fn tag -> tag.label end) |> Enum.join(", "),
      flow_label: row.flow_label,
      media_url: if(!is_nil(row.media), do: row.media.url),
      flow_uuid: if(!is_nil(row.flow_object), do: row.flow_object.uuid),
      flow_name: if(!is_nil(row.flow_object), do: row.flow_object.name),
      longitude: if(!is_nil(row.location), do: row.location.longitude),
      latitude: if(!is_nil(row.location), do: row.location.latitude),
      gcs_url: if(!is_nil(row.media), do: row.media.gcs_url)
    }

  @spec make_job(list(), atom(), non_neg_integer, map()) :: :ok
  defp make_job(data, table, organization_id, %{action: :insert} = attrs)
       when data in [%{}, nil, []] do
    table = Atom.to_string(table)

    if is_integer(attrs[:max_id]) == true,
      do: Jobs.update_bigquery_job(organization_id, table, %{table_id: attrs[:max_id]})

    :ok
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
      "making a new job for #{table} to send on bigquery org_id: #{organization_id} with max id: #{
        inspect(attrs)
      }"
    )

    __MODULE__.new(%{
      data: data,
      table: table,
      organization_id: organization_id,
      max_id: attrs[:max_id],
      last_updated_at: attrs[:last_updated_at]
    })
    |> Oban.insert()

    :ok
  end

  @spec make_job_to_remove_duplicate(String.t(), non_neg_integer) :: :ok
  defp make_job_to_remove_duplicate(table, organization_id) do
    Logger.info("removing duplicates for the table #{table} and org_id: #{organization_id}")

    __MODULE__.new(%{
      table: table,
      organization_id: organization_id,
      remove_duplicates: true
    })
    |> Oban.insert()

    :ok
  end

  @spec apply_action_clause(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp apply_action_clause(query, %{action: :insert, max_id: max_id, min_id: min_id} = _attrs),
    do: query |> where([m], m.id > ^min_id and m.id <= ^max_id)

  defp apply_action_clause(query, %{action: :update, last_updated_at: last_updated_at} = _attrs),
    do:
      query
      |> where([tb], tb.updated_at >= ^last_updated_at)
      |> where(
        [tb],
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
      |> preload([:tags, :receiver, :sender, :contact, :user, :media, :flow_object, :location])

  defp get_query("contacts", organization_id, attrs),
    do:
      Contact
      |> where([m], m.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:language, :tags, :groups, :user])

  defp get_query("flows", organization_id, attrs),
    do:
      FlowRevision
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> where([f], f.status in ["published", "archived"])
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow])

  defp get_query("flow_results", organization_id, attrs),
    do:
      FlowResult
      |> where([f], f.organization_id == ^organization_id)
      |> apply_action_clause(attrs)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, :contact])

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
      ),
      do: BigQuery.make_job_to_remove_duplicate(table, organization_id)

  def perform(
        %Oban.Job{
          args: %{
            "data" => data,
            "table" => table,
            "organization_id" => organization_id,
            "max_id" => max_id,
            "last_updated_at" => last_updated_at
          }
        } = _job
      ),
      do:
        BigQuery.make_insert_query(data, table, organization_id,
          max_id: max_id,
          last_updated_at: last_updated_at
        )
end
