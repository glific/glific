defmodule Glific.Jobs.BigQueryWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a bigquery Worker Job to deliver the message to
  the bigquery servers

  We centralize both the cron job and the worker job in one module
  """

  import Ecto.Query

  use Oban.Worker,
    queue: :bigquery,
    max_attempts: 1,
    priority: 1

  alias Glific.{
    Bigquery,
    Contacts.Contact,
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs,
    Messages.Message,
    Partners,
    Repo
  }

  @simulater_phone "9876543210"
  @update_minutes -1

  @doc """
  This is called from the cron job on a regular schedule. we sweep the messages table
  and queue them up for delivery to bigquery
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services["bigquery"]

    if credential do
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
      make_merge_job("contacts", organization_id)
      # make_merge_job("messages", organization_id)
      # make_merge_job("flow_results", organization_id)
    end

    :ok
  end

  @spec insert_for_table(Jobs.BigqueryJob.t() | nil, non_neg_integer) :: :ok | nil
  defp insert_for_table(nil, _), do: nil

  defp insert_for_table(%{table: table} = _bigquery_job, organization_id)
       when table in ["messages_delta", "contacts_delta", "flow_results_delta"],
       do: queue_table_data(table, organization_id, 0, 0)

  defp insert_for_table(bigquery_job, organization_id) do
    table_id = bigquery_job.table_id

    data =
      Bigquery.get_table_struct(bigquery_job.table)
      |> select([m], m.id)
      |> where([m], m.organization_id == ^organization_id and m.id > ^table_id)
      |> order_by([m], asc: m.id)
      |> limit(100)
      |> Repo.all()

    max_id = if is_list(data), do: List.last(data), else: table_id

    cond do
      is_nil(max_id) ->
        nil

      max_id > table_id ->
        queue_table_data(bigquery_job.table, organization_id, table_id, max_id)

      true ->
        nil
    end

    :ok
  end

  @spec queue_table_data(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  defp queue_table_data("messages", organization_id, min_id, max_id) do
    Message
    |> where([m], m.organization_id == ^organization_id)
    |> where([m], m.id > ^min_id and m.id <= ^max_id)
    |> order_by([m], [m.inserted_at, m.id])
    |> preload([:tags, :receiver, :sender, :contact, :user, :media, :flow_object, :location])
    |> Repo.all()
    |> Enum.reduce([], fn row, acc ->
      if is_simulator_contact?(row.contact.phone),
        do: acc,
        else: [
          row
          |> get_message_row(organization_id)
          |> Bigquery.format_data_for_bigquery("messages")
          | acc
        ]
    end)
    |> make_job(:messages, organization_id, max_id)

    :ok
  end

  defp queue_table_data("contacts", organization_id, min_id, max_id) do
    query =
      Contact
      |> where([m], m.organization_id == ^organization_id)
      |> where([m], m.phone != @simulater_phone)
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:language, :tags, :groups])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        if is_simulator_contact?(row.phone),
          do: acc,
          else: [
            %{
              id: row.id,
              name: row.name,
              phone: row.phone,
              provider_status: row.bsp_status,
              status: row.status,
              language: row.language.label,
              optin_time: Bigquery.format_date(row.optin_time, organization_id),
              optout_time: Bigquery.format_date(row.optout_time, organization_id),
              last_message_at: Bigquery.format_date(row.last_message_at, organization_id),
              inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
              updated_at: Bigquery.format_date(row.updated_at, organization_id),
              fields:
                Enum.map(row.fields, fn {_key, field} ->
                  %{
                    label: field["label"],
                    inserted_at: Bigquery.format_date(field["inserted_at"], organization_id),
                    type: field["type"],
                    value: field["value"]
                  }
                end),
              settings: row.settings,
              groups:
                Enum.map(row.groups, fn group ->
                  %{label: group.label, description: group.description}
                end),
              tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end)
            }
            |> Bigquery.format_data_for_bigquery("contacts")
            | acc
          ]
      end
    )
    |> make_job(:contacts, organization_id, max_id)

    :ok
  end

  defp queue_table_data("flows", organization_id, min_id, max_id) do
    query =
      FlowRevision
      |> where([f], f.organization_id == ^organization_id)
      |> where([f], f.id > ^min_id and f.id <= ^max_id)
      |> where([f], f.id > ^min_id and f.id <= ^max_id)
      |> where([f], f.status in ["published", "archived"])
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.flow.id,
            name: row.flow.name,
            uuid: row.flow.uuid,
            inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
            updated_at: Bigquery.format_date(row.updated_at, organization_id),
            keywords: Bigquery.format_json(row.flow.keywords),
            status: row.status,
            revision: Bigquery.format_json(row.definition)
          }
          |> Bigquery.format_data_for_bigquery("flows")
          | acc
        ]
      end
    )
    |> make_job(:flows, organization_id, max_id)

    :ok
  end

  defp queue_table_data("flow_results", organization_id, min_id, max_id) do
    query =
      FlowResult
      |> where([f], f.organization_id == ^organization_id)
      |> where([f], f.id > ^min_id and f.id <= ^max_id)
      |> where([f], f.id > ^min_id and f.id <= ^max_id)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, :contact])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        if is_simulator_contact?(row.contact.phone),
          do: acc,
          else: [
            %{
              id: row.flow.id,
              name: row.flow.name,
              uuid: row.flow.uuid,
              inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
              updated_at: Bigquery.format_date(row.updated_at, organization_id),
              results: Bigquery.format_json(row.results),
              contact_phone: row.contact.phone,
              contact_name: row.contact.name,
              flow_version: row.flow_version,
              flow_context_id: row.flow_context_id
            }
            |> Bigquery.format_data_for_bigquery("flow_results")
            | acc
          ]
      end
    )
    |> make_job(:flow_results, organization_id, max_id)

    :ok
  end

  ## Insert update query.
  defp queue_table_data("messages_delta", organization_id, _min_id, _max_id) do
    Message
    |> where([m], m.organization_id == ^organization_id)
    |> where([fr], fr.updated_at >= ^Timex.shift(Timex.now(), minutes: @update_minutes))
    |> where([fr], fr.updated_at != fr.inserted_at)
    |> order_by([m], [m.inserted_at, m.id])
    |> preload([:tags, :receiver, :sender, :contact, :user, :media, :flow_object, :location])
    |> Repo.all()
    |> Enum.reduce([], fn row, acc ->
      if is_simulator_contact?(row.contact.phone),
        do: acc,
        else: [
          %{
            id: row.id,
            type: row.type,
            sent_at: Bigquery.format_date(row.sent_at, organization_id),
            status: row.status,
            contact_phone: row.contact.phone,
            tags_label: Enum.map(row.tags, fn tag -> tag.label end) |> Enum.join(", "),
            flow_label: row.flow_label,
            flow_uuid: if(!is_nil(row.flow_object), do: row.flow_object.uuid),
            flow_name: if(!is_nil(row.flow_object), do: row.flow_object.name)
          }
          |> Bigquery.format_data_for_bigquery("messages_delta")
          | acc
        ]
    end)
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :messages_delta, organization_id, 0))

    :ok
  end

  defp queue_table_data("contacts_delta", organization_id, _min_id, _max_id) do
    query =
      Contact
      |> where([fr], fr.organization_id == ^organization_id)
      |> where([fr], fr.updated_at >= ^Timex.shift(Timex.now(), minutes: @update_minutes))
      |> where([fr], fr.updated_at != fr.inserted_at)
      |> where([m], m.phone != @simulater_phone)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:language, :tags, :groups])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        if is_simulator_contact?(row.phone),
          do: acc,
          else: [
            %{
              id: row.id,
              phone: row.phone,
              provider_status: row.bsp_status,
              status: row.status,
              language: row.language.label,
              optin_time: Bigquery.format_date(row.optin_time, organization_id),
              optout_time: Bigquery.format_date(row.optout_time, organization_id),
              last_message_at: Bigquery.format_date(row.last_message_at, organization_id),
              updated_at: Bigquery.format_date(row.updated_at, organization_id),
              fields:
                Enum.map(row.fields, fn {_key, field} ->
                  %{
                    label: field["label"],
                    inserted_at: Bigquery.format_date(field["inserted_at"], organization_id),
                    type: field["type"],
                    value: field["value"]
                  }
                end),
              settings: row.settings,
              groups:
                Enum.map(row.groups, fn group ->
                  %{label: group.label, description: group.description}
                end),
              tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end)
            }
            |> Bigquery.format_data_for_bigquery("contacts")
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :contacts_delta, organization_id, 0))

    :ok
  end

  defp queue_table_data("flow_results_delta", organization_id, _min_id, _max_id) do
    query =
      FlowResult
      |> where([fr], fr.organization_id == ^organization_id)
      |> where([fr], fr.updated_at >= ^Timex.shift(Timex.now(), minutes: @update_minutes))
      |> where([fr], fr.updated_at != fr.inserted_at)
      |> order_by([f], [f.inserted_at, f.id])
      |> preload([:flow, :contact])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        if is_simulator_contact?(row.contact.phone),
          do: acc,
          else: [
            %{
              id: row.flow.id,
              uuid: row.flow.uuid,
              results: Bigquery.format_json(row.results),
              contact_phone: row.contact.phone,
              flow_context_id: row.flow_context_id
            }
            |> Bigquery.format_data_for_bigquery("flow_results_delta")
            | acc
          ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, :flow_results_delta, organization_id, 0))

    :ok
  end

  defp queue_table_data(_, _, _, _), do: :ok

  defp get_message_row(row, organization_id),
    do: %{
      id: row.id,
      body: row.body,
      type: row.type,
      flow: row.flow,
      inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
      sent_at: Bigquery.format_date(row.sent_at, organization_id),
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
      latitude: if(!is_nil(row.location), do: row.location.latitude)
    }

  @spec is_simulator_contact?(String.t()) :: boolean
  defp is_simulator_contact?(phone), do: @simulater_phone == phone

  @spec make_job(any(), any(), non_neg_integer, non_neg_integer) :: :ok
  defp make_job(data, _, _, _) when data in [%{}, nil, []], do: :ok

  defp make_job(data, table, organization_id, max_id) do
    __MODULE__.new(%{
      data: data,
      table: table,
      organization_id: organization_id,
      max_id: max_id
    })
    |> Oban.insert()

    :ok
  end

  @spec make_merge_job(any(), non_neg_integer) :: :ok
  defp make_merge_job(table, organization_id) do
    __MODULE__.new(%{
      table: table,
      organization_id: organization_id,
      merge_table: true
    })
    |> Oban.insert()

    :ok
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker

  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(
        %Oban.Job{
          args: %{"table" => table, "organization_id" => organization_id, "merge_table" => true}
        } = _job
      ),
      do: Bigquery.make_merge_job(table, organization_id)

  def perform(
        %Oban.Job{
          args: %{
            "data" => data,
            "table" => table,
            "organization_id" => organization_id,
            "max_id" => max_id
          }
        } = job
      ),
      do: Bigquery.make_insert_query(data, table, organization_id, job, max_id)
end
