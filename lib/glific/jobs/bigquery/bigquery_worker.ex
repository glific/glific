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
  @update_minutes 90

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

    if credential,
      do: update_flow_results(organization_id),
      else: :ok
  end

  # need to add an order by and limit here, so we are sending chunks of 1K at a time
  @spec update_flow_results(non_neg_integer) :: :ok
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
    |> Enum.each(&make_job(&1, "update_flow_results", organization_id))
  end

  @spec perform_for_table(Jobs.BigqueryJob.t() | nil, non_neg_integer) :: :ok | nil
  defp perform_for_table(nil, _), do: nil

  defp perform_for_table(bigquery_job, organization_id) do
    table_id = bigquery_job.table_id

    max_id =
      get_table_struct(bigquery_job.table)
      |> select([m], max(m.id))
      |> where([m], m.organization_id == ^organization_id)
      |> where[[m], m.id > table_id]
      |> limit(100)
      |> Repo.one()

    if max_id > table_id,
    do:queue_table_data(bigquery_job.table, organization_id, table_id, max_id)

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
      |> Repo.all()
      |> Enum.reduce( [], fn row, acc ->
          tags_label = Enum.map(row.tags, fn tag -> tag.label end) |> Enum.join(", ")
          bq_message_row = %{
          id: row.id,
          body: row.body,
          type: row.type,
          flow: row.flow,
          inserted_at: format_date(row.inserted_at, organization_id),
          sent_at: format_date(row.sent_at, organization_id),
          uuid: row.uuid,
          status: row.status,
          sender_phone: row.sender.phone,
          receiver_phone: row.receiver.phone,
          contact_phone: row.contact.phone,
          contact_name: row.contact.name,
          user_phone: if(!is_nil(row.user), do: row.user.phone),
          user_name: if(!is_nil(row.user), do: row.user.name),
          tags_label: tags_label,
          flow_label: row.flow_label
          media_url: media_url(row.media)
        }
        |> format_data_for_bigquery("messages")

        [bq_message_row | acc]
      end
    )
    |> make_job(:messages, organization_id, max_id)
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
            fields: Enum.map(row.fields, fn {_key, field} ->
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
          |> format_data_for_bigquery("contacts")
          | acc
        ]
      end
    )
    |> make_job(contacts, organization_id, max_id)
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
          |> format_data_for_bigquery("flows")
          | acc
        ]
      end
    )
    |> make_job(:flows, organization_id, max_id)
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
            flow_version: row.flow_version,
            flow_context_id: row.flow_context_id
          } |> format_data_for_bigquery("flow_results")
          | acc
        ]
      end
    )
    |> Enum.reject(fn flow_result -> flow_result.contact_phone == @simulater_phone end)
    |> make_job(:flow_resultsm organization_id, max_id)
  end

  defp queue_table_data(_, _, _, _), do: nil

  @spec format_json(map()) :: iodata
  defp format_json(definition) do
    {:ok, data} = Jason.encode(definition)
    data
  end

  @spec make_job(list(), String.t(), non_neg_integer, non_neg_integer) :: :ok | nil
  defp make_job(data, table, organization_id, max_id) do
    __MODULE__.new(%{
        table => data,
        organization_id: organization_id,
        max_id: max_id
      })
    |> Oban.insert
    :ok
  end

  defp make_job(data, "update_flow_results", organization_id) do
    __MODULE__.new(%{organization_id: organization_id, update_flow_results: data})
    |> Oban.insert()
  end

  defp make_job(_, _, _, _), do: nil

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "update_flow_results" => update_flow_results,
            "organization_id" => organization_id,
            "max_id" => max_id
          }
        } = job
      ), do:
        update_flow_results
        |> Enum.map(fn fr -> format_data_for_bigquery(fr, "update_flow_results") end)
        |> make_update_query(organization_id, job)


  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(%Oban.Job{args: %{table => data, "organization_id" => organization_id, "max_id" => max_id }} = job),
  do: make_insert_query(data, table, organization_id, job, max_id)


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
  defp format_date(nil, _), do: nil

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

  @spec format_data_for_bigquery(map(), String.t()) :: map()
  defp format_data_for_bigquery(data, table),
  do:%{json: msg}

  defp format_data_for_bigquery(flow, "update_flow_results") do
    %{
      id: flow["id"],
      results: flow["results"],
      contact_phone: flow["contact_phone"],
      flow_context_id: flow["flow_context_id"]
    }
  end

  defp format_data_for_bigquery(_, _), do: %{}

  @spec make_insert_query(list(), String.t(), non_neg_integer, Oban.Job.t()) :: :ok
  defp make_insert_query(data, table, organization_id, job, max_id) do
    organization =
      Partners.organization(organization_id)
      |> Repo.preload(:contact)

    credentials =
      organization.services["bigquery"]
      |> case do
        nil -> %{url: nil, id: nil, email: nil}
        credentials -> credentials
      end

    {:ok, service_account} = Jason.decode(credentials.secrets["service_account"])
    project_id = service_account["project_id"]
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
        Jobs.update_bigquery_job(bigquery_job, %{table_id: max_id})
        :ok

      {:error, response} ->
        handle_insert_error(table, dataset_id, organization_id, response, job)
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

  @spec handle_insert_error(String.t(), String.t(), non_neg_integer, any(), Oban.Job.t()) :: :ok
  defp handle_insert_error(table, dataset_id, organization_id, response, job) do
    if should_retry_job?(response) do
      Bigquery.sync_schema_with_bigquery(dataset_id, organization_id)
      :ok
    else
      raise("Bigquery Insert Error #{response}")
    end
  end

  @spec should_retry_job?(any()) :: boolean()
  defp should_retry_job?(response) do
    with true <- Map.has_key?(response, :body),
         {:ok, error} <- Jason.decode(response.body),
         true <- error["status"] == "NOT_FOUND" do
      true
    else
      _ -> false
    end
  end
end
