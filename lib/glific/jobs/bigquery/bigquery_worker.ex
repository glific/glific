defmodule Glific.Jobs.BigQueryWorker do
  @moduledoc """
  Process the message table for each organization. Chunk number of messages
  in groups of 128 and create a bigquery Worker Job to deliver the message to
  the bigquery servers

  We centralize both the cron job and the worker job in one module
  """

  import Ecto.Query

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    priority: 0

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

  alias GoogleApi.BigQuery.{
    V2.Api.Tabledata,
    V2.Connection
  }

  @simulater_phone "9876543210"
  @reschedule_time 120
  @update_minutes 30

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
      |> Enum.each(&perform_for_table(&1, organization_id))

      :ok
    else
      :ok
    end
  end

  @doc """
  This is called from the cron job on a regular schedule. We updates existing tables
  """
  @spec periodic_updates(non_neg_integer) :: :ok
  def periodic_updates(organization_id) do
    organization = Partners.organization(organization_id)
    credential = organization.services["bigquery"]

    if credential,
      do: update_flow_results(organization_id),
      else: :ok
  end

  defp update_flow_results(organization_id) do
    query =
      FlowResult
      |> where([fr], fr.organization_id == ^organization_id)
      |> where([fr], fr.updated_at <= ^Timex.shift(Timex.now(), minutes: @update_minutes))
      |> preload([:flow, :contact])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.flow.id,
            inserted_at: format_date(row.inserted_at, organization_id),
            updated_at: format_date(row.updated_at, organization_id),
            results: format_json(row.results),
            contact_phone: row.contact.phone,
            flow_version: row.flow_version,
            flow_context_id: row.flow_context_id
          }
          | acc
        ]
      end
    )
    |> Enum.reject(fn flow_result -> flow_result.contact_phone == @simulater_phone end)
    |> Enum.chunk_every(5)
    |> Enum.each(&make_job(&1, "update_flow_results", organization_id, 1))
  end

  @spec perform_for_table(Jobs.BigqueryJob.t() | nil, non_neg_integer) :: :ok | nil
  defp perform_for_table(nil, _), do: nil

  defp perform_for_table(bigquery_job, organization_id) do
    table_id = bigquery_job.table_id

    max_id =
      get_table_struct(bigquery_job.table)
      |> select([m], max(m.id))
      |> where([m], m.organization_id == ^organization_id)
      |> Repo.one()

    if max_id > table_id do
      Jobs.update_bigquery_job(bigquery_job, %{table_id: max_id})
      queue_table_data(bigquery_job.table, organization_id, table_id, max_id)
    end

    :ok
  end

  @spec queue_table_data(String.t(), non_neg_integer, non_neg_integer, non_neg_integer) :: :ok
  defp queue_table_data("messages", organization_id, min_id, max_id) do
    query =
      Message
      |> where([m], m.organization_id == ^organization_id)
      |> where([m], m.id > ^min_id and m.id <= ^max_id)
      |> order_by([m], [m.inserted_at, m.id])
      |> preload([:tags, :receiver, :sender, :contact, :user, :media])

    query =
      case Repo.fetch_by(Contact, %{phone: @simulater_phone, organization_id: organization_id}) do
        {:ok, simulator_contact} ->
          query
          |> where([m], m.contact_id != ^simulator_contact.id)

        {:error, _} ->
          query
      end

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        tags_label =
          Enum.map(row.tags, fn tag -> tag.label end)
          |> Enum.join(", ")

        message_row = %{
          type: row.type,
          user_id: row.contact_id,
          message: row.body,
          inserted_at: format_date(row.inserted_at, organization_id),
          sent_at: format_date(row.sent_at, organization_id),
          uuid: row.uuid,
          id: row.id,
          flow: row.flow,
          status: row.status,
          sender_phone: row.sender.phone,
          receiver_phone: row.receiver.phone,
          contact_phone: row.contact.phone,
          contact_name: row.contact.name,
          user_phone: if(!is_nil(row.user), do: row.user.phone),
          user_name: if(!is_nil(row.user), do: row.user.name),
          media: media_url(row.media),
          tags_label: tags_label,
          flow_label: row.flow_label
        }

        [message_row | acc]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, "messages", organization_id, 1))
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
        [
          %{
            id: row.id,
            name: row.name,
            phone: row.phone,
            provider_status: row.bsp_status,
            status: row.status,
            language: row.language.label,
            optin_time: format_date(row.optin_time, organization_id),
            optout_time: format_date(row.optout_time, organization_id),
            last_message_at: format_date(row.last_message_at, organization_id),
            inserted_at: format_date(row.inserted_at, organization_id),
            fields:
              Enum.map(row.fields, fn {_key, field} ->
                %{
                  label: field["label"],
                  inserted_at: format_date(field["inserted_at"], organization_id),
                  type: field["type"],
                  value: field["value"]
                }
              end),
            settings: row.settings,
            groups: Enum.map(row.groups, fn group -> %{label: group.label} end),
            tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end)
          }
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, "contacts", organization_id, 1))
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
            inserted_at: format_date(row.inserted_at, organization_id),
            updated_at: format_date(row.updated_at, organization_id),
            keywords: format_json(row.flow.keywords),
            status: row.status,
            revision: format_json(row.definition)
          }
          | acc
        ]
      end
    )
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, "flows", organization_id, 1))
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
        [
          %{
            id: row.flow.id,
            name: row.flow.name,
            uuid: row.flow.uuid,
            inserted_at: format_date(row.inserted_at, organization_id),
            updated_at: format_date(row.updated_at, organization_id),
            results: format_json(row.results),
            contact_phone: row.contact.phone,
            contact_name: row.contact.name,
            flow_version: row.flow_version
          }
          | acc
        ]
      end
    )
    |> Enum.reject(fn flow_result -> flow_result.contact_phone == @simulater_phone end)
    |> Enum.chunk_every(100)
    |> Enum.each(&make_job(&1, "flow_results", organization_id, 1))
  end

  defp queue_table_data(_, _, _, _), do: nil

  @spec format_json(map()) :: iodata
  defp format_json(definition) do
    {:ok, data} = Jason.encode(definition)
    data
  end

  @spec make_job(list(), String.t(), non_neg_integer, non_neg_integer) :: :ok | nil
  defp make_job(data, "messages", organization_id, schedule_in) do
    __MODULE__.new(%{organization_id: organization_id, messages: data}, schedule_in: schedule_in)
    |> Oban.insert()

    :ok
  end

  defp make_job(data, "contacts", organization_id, schedule_in) do
    __MODULE__.new(%{organization_id: organization_id, contacts: data}, schedule_in: schedule_in)
    |> Oban.insert()
  end

  defp make_job(data, "flows", organization_id, schedule_in) do
    __MODULE__.new(%{organization_id: organization_id, flows: data},
      schedule_in: schedule_in
    )
    |> Oban.insert()
  end

  defp make_job(data, "flow_results", organization_id, schedule_in) do
    __MODULE__.new(%{organization_id: organization_id, flow_results: data},
      schedule_in: schedule_in
    )
    |> Oban.insert()
  end

  defp make_job(data, "update_flow_results", organization_id, schedule_in) do
    __MODULE__.new(%{organization_id: organization_id, update_flow_results: data},
      schedule_in: schedule_in
    )
    |> Oban.insert()
  end

  defp make_job(_, _, _, _), do: nil

  @spec get_table_struct(String.t()) :: any()
  defp get_table_struct(table) do
    case table do
      "messages" -> Message
      "contacts" -> Contact
      "flows" -> FlowRevision
      "flow_results" -> FlowResult
      "update_flow_results" -> FlowResult
      _ -> ""
    end
  end

  defp media_url(nil), do: nil
  defp media_url(media), do: media.url

  @spec format_date(DateTime.t() | nil, non_neg_integer()) :: any()
  defp format_date(nil, _),
    do: nil

  defp format_date(date, organization_id) when is_binary(date) do
    timezone = Partners.organization(organization_id).timezone

    Timex.parse(date, "{RFC3339z}")
    |> elem(1)
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  defp format_date(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(
        %Oban.Job{args: %{"messages" => messages, "organization_id" => organization_id}} = job
      ) do
    messages
    |> Enum.map(fn msg -> format_data_for_bigquery("messages", msg) end)
    |> make_insert_query("messages", organization_id, job)
  end

  def perform(
        %Oban.Job{args: %{"contacts" => contacts, "organization_id" => organization_id}} = job
      ) do
    contacts
    |> Enum.map(fn msg -> format_data_for_bigquery("contacts", msg) end)
    |> make_insert_query("contacts", organization_id, job)
  end

  def perform(%Oban.Job{args: %{"flows" => flows, "organization_id" => organization_id}} = job) do
    flows
    |> Enum.map(fn msg -> format_data_for_bigquery("flows", msg) end)
    |> make_insert_query("flows", organization_id, job)
  end

  def perform(
        %Oban.Job{
          args: %{"flow_results" => flow_results, "organization_id" => organization_id}
        } = job
      ) do
    flow_results
    |> Enum.map(fn msg -> format_data_for_bigquery("flow_results", msg) end)
    |> make_insert_query("flow_results", organization_id, job)
  end

  def perform(
        %Oban.Job{
          args: %{
            "update_flow_results" => update_flow_results,
            "organization_id" => organization_id
          }
        } = job
      ) do
    update_flow_results
    |> Enum.map(fn fr -> format_data_for_bigquery("update_flow_results", fr) end)
    |> make_update_query(organization_id, job)
  end

  @spec format_data_for_bigquery(String.t(), map()) :: map()
  defp format_data_for_bigquery("messages", msg) do
    %{
      json: %{
        id: msg["id"],
        body: msg["message"],
        type: msg["type"],
        flow: msg["flow"],
        inserted_at: msg["inserted_at"],
        sent_at: msg["sent_at"],
        uuid: msg["uuid"],
        status: msg["status"],
        sender_phone: msg["sender_phone"],
        receiver_phone: msg["receiver_phone"],
        contact_phone: msg["contact_phone"],
        contact_name: msg["contact_name"],
        user_phone: msg["user_phone"],
        user_name: msg["user_name"],
        tags_label: msg["tags_label"],
        flow_label: msg["flow_label"],
        media_url: msg["media"]
      }
    }
  end

  defp format_data_for_bigquery("contacts", contact) do
    %{
      json: %{
        id: contact["id"],
        name: contact["name"],
        phone: contact["phone"],
        provider_status: contact["provider_status"],
        status: contact["status"],
        language: contact["language"],
        optin_time: contact["optin_time"],
        optout_time: contact["optout_time"],
        last_message_at: contact["last_message_at"],
        inserted_at: contact["inserted_at"],
        fields: contact["fields"],
        settings: contact["settings"],
        groups: contact["groups"],
        tags: contact["tags"]
      }
    }
  end

  defp format_data_for_bigquery("flows", flow) do
    %{
      json: %{
        id: flow["id"],
        name: flow["name"],
        uuid: flow["uuid"],
        inserted_at: flow["inserted_at"],
        updated_at: flow["updated_at"],
        keywords: flow["keywords"],
        status: flow["status"],
        revision: flow["revision"]
      }
    }
  end

  defp format_data_for_bigquery("flow_results", flow) do
    %{
      json: %{
        id: flow["id"],
        name: flow["name"],
        uuid: flow["uuid"],
        inserted_at: flow["inserted_at"],
        updated_at: flow["updated_at"],
        results: flow["results"],
        contact_phone: flow["contact_phone"],
        contact_name: flow["contact_name"],
        flow_version: flow["flow_version"],
        flow_context_id: flow["flow_context_id"],
      }
    }
  end

  defp format_data_for_bigquery("update_flow_results", flow) do
    %{
      id: flow["id"],
      results: flow["results"],
      contact_phone: flow["contact_phone"],
      flow_context_id: flow["flow_context_id"],
    }
  end

  defp format_data_for_bigquery(_, _), do: %{}

  @spec make_insert_query(list(), String.t(), non_neg_integer, Oban.Job.t()) :: :ok
  defp make_insert_query(data, table, organization_id, job) do
    organization =
      Partners.organization(organization_id)
      |> Repo.preload(:contact)

    credentials =
      organization.services["bigquery"]
      |> case do
        nil -> %{url: nil, id: nil, email: nil}
        credentials -> credentials
      end

    {:ok, secrets} = Jason.decode(credentials.secrets["service_account"])
    project_id = secrets["project_id"]
    dataset_id = organization.contact.phone
    table_id = table
    token = Partners.get_goth_token(organization_id, "bigquery")
    conn = Connection.new(token.token)
    # In case of error response error will be stored in the oban job
    Tabledata.bigquery_tabledata_insert_all(
      conn,
      project_id,
      dataset_id,
      table_id,
      [body: %{rows: data}],
      []
    )
    |> case do
      {:ok, _} ->
        :ok

      {:error, response} ->
        {:ok, error} = Jason.decode(response.body)
        handle_insert_error(table, dataset_id, organization_id, error, job)
    end

    :ok
  end

  @spec make_update_query(list(), non_neg_integer, Oban.Job.t()) :: :ok
  defp make_update_query(data, organization_id, _job) do
    organization =
      Partners.organization(organization_id)
      |> Repo.preload(:contact)

    credentials =
      organization.services["bigquery"]
      |> case do
        nil -> %{url: nil, id: nil, email: nil}
        credentials -> credentials
      end

    {:ok, secrets} = Jason.decode(credentials.secrets["service_account"])
    project_id = secrets["project_id"]
    dataset_id = organization.contact.phone
    token = Partners.get_goth_token(organization_id, "bigquery")
    conn = Connection.new(token.token)

    data
    |> Enum.each(fn flow_result ->
      sql =
        "UPDATE `#{dataset_id}.flow_results` SET results = '#{flow_result.results}' WHERE contact_phone= '#{
          flow_result.contact_phone
        }' AND id = #{flow_result.id} AND flow_context_id =  #{flow_result.flow_context_id} "

      GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
        body: %{query: sql, useLegacySql: false}
      )
      |> case do
        {:ok, response} -> response
        {:error, _} -> nil
      end
    end)
  end

  @spec handle_insert_error(String.t(), String.t(), non_neg_integer, map(), Oban.Job.t()) :: :ok
  defp handle_insert_error(table, dataset_id, organization_id, error, job) do
    error = error["error"]

    if error["status"] == "NOT_FOUND" do
      Bigquery.bigquery_dataset(dataset_id, organization_id)
      make_job(job.args[table], table, organization_id, @reschedule_time)
    end

    :ok
  end
end
