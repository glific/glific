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
    V2.Api.Tabledata
  }

  @simulater_phone "9876543210"
  @update_minutes -90

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
      do: update_biquery_tables(organization_id),
      else: :ok
  end

  @spec update_biquery_tables(non_neg_integer) :: :ok
  defp update_biquery_tables(organization_id) do
    queue_table_data("update_flow_results", organization_id, 0, 0)
    queue_table_data("update_contacts", organization_id, 0, 0)
    :ok
  end

  @spec perform_for_table(Jobs.BigqueryJob.t() | nil, non_neg_integer) :: :ok | nil
  defp perform_for_table(nil, _), do: nil

  defp perform_for_table(bigquery_job, organization_id) do
    table_id = bigquery_job.table_id

    max_id =
      Bigquery.get_table_struct(bigquery_job.table)
      |> select([m], max(m.id))
      |> where([m], m.organization_id == ^organization_id and m.id > ^table_id)
      |> limit(100)
      |> Repo.one()

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
    |> preload([:tags, :receiver, :sender, :contact, :user, :media])
    |> Repo.all()
    |> Enum.reduce([], fn row, acc ->
      tags_label = Enum.map(row.tags, fn tag -> tag.label end) |> Enum.join(", ")

      bq_message_row =
        %{
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
          tags_label: tags_label,
          flow_label: row.flow_label,
          media_url: if(!is_nil(row.media), do: row.media.url)
        }
        |> format_data_for_bigquery("messages")

      [bq_message_row | acc]
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
        [
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
            groups: Enum.map(row.groups, fn group -> %{label: group.label} end),
            tags: Enum.map(row.tags, fn tag -> %{label: tag.label} end)
          }
          |> format_data_for_bigquery("contacts")
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
        [
          %{
            id: row.flow.id,
            name: row.flow.name,
            uuid: row.flow.uuid,
            inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
            updated_at: Bigquery.format_date(row.updated_at, organization_id),
            results: format_json(row.results),
            contact_phone: row.contact.phone,
            contact_name: row.contact.name,
            flow_version: row.flow_version,
            flow_context_id: row.flow_context_id
          }
          |> format_data_for_bigquery("flow_results")
          | acc
        ]
      end
    )
    |> Enum.reject(fn flow_result -> flow_result.contact_phone == @simulater_phone end)
    |> make_job(:flow_results, organization_id, max_id)

    :ok
  end

  defp queue_table_data("update_flow_results", organization_id, _, _) do
    query =
      FlowResult
      |> where([fr], fr.organization_id == ^organization_id)
      |> where([fr], fr.updated_at >= ^Timex.shift(Timex.now(), minutes: @update_minutes))
      |> preload([:flow, :contact])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.flow.id,
            inserted_at: Bigquery.format_date(row.inserted_at, organization_id),
            updated_at: Bigquery.format_date(row.updated_at, organization_id),
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
    |> Enum.chunk_every(10)
    |> Enum.each(&make_job(&1, :update_flow_results, organization_id, 0))

    :ok
  end

  defp queue_table_data("update_contacts", organization_id, _, _) do
    query =
      Contact
      |> where([fr], fr.organization_id == ^organization_id)
      |> where([fr], fr.updated_at >= ^Timex.shift(Timex.now(), minutes: @update_minutes))
      |> preload([:language, :groups])

    Repo.all(query)
    |> Enum.reduce(
      [],
      fn row, acc ->
        [
          %{
            id: row.id,
            name: row.name,
            phone: row.phone,
            status: row.status,
            language: row.language.label,
            optin_time: Bigquery.format_date(row.optin_time, organization_id),
            optout_time: Bigquery.format_date(row.optout_time, organization_id),
            groups: Enum.map(row.groups, fn group -> %{label: group.label} end),
            fields:
              Enum.map(row.fields, fn {_key, field} ->
                %{
                  label: field["label"] || "unknown",
                  type: field["type"] || "unknown",
                  value: field["value"] || "unknown",
                  inserted_at: field["inserted_at"]
                }
              end)
          }
          | acc
        ]
      end
    )
    |> Enum.reject(fn contact -> contact.phone == @simulater_phone end)
    |> Enum.chunk_every(10)
    |> Enum.each(&make_job(&1, :update_contacts, organization_id, 0))

    :ok
  end

  defp queue_table_data(_, _, _, _), do: :ok

  @spec format_json(map()) :: iodata
  defp format_json(definition) do
    {:ok, data} = Jason.encode(definition)
    data
  end

  @spec make_job(any(), any(), non_neg_integer, non_neg_integer) :: :ok
  defp make_job(data, _, _, _) when data in [%{}, nil], do: :ok

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

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker

  @spec perform(Oban.Job.t()) :: :ok | {:error, :string}
  def perform(
        %Oban.Job{
          args: %{
            "data" => data,
            "table" => table,
            "organization_id" => organization_id,
            "max_id" => _max_id
          }
        } = job
      )
      when table in ["update_flow_results", "update_contacts"],
      do: make_update_query(data, organization_id, table, job)

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
      do: make_insert_query(data, table, organization_id, job, max_id)

  @spec format_data_for_bigquery(map(), String.t()) :: map()
  defp format_data_for_bigquery(flow, "update_flow_results") do
    %{
      id: flow["id"],
      results: flow["results"],
      contact_phone: flow["contact_phone"],
      flow_context_id: flow["flow_context_id"]
    }
  end

  defp format_data_for_bigquery(data, _table),
    do: %{json: data}

  @spec make_insert_query(list(), String.t(), non_neg_integer, Oban.Job.t(), non_neg_integer) ::
          :ok
  defp make_insert_query(data, table, organization_id, job, max_id) do
    Bigquery.fetch_bigquery_credentials(organization_id)
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} ->
        Tabledata.bigquery_tabledata_insert_all(
          conn,
          project_id,
          dataset_id,
          table,
          [body: %{rows: data}],
          []
        )
        |> case do
          {:ok, _} ->
            Jobs.update_bigquery_job(organization_id, table, %{table_id: max_id})
            :ok

          {:error, response} ->
            handle_insert_error(table, dataset_id, organization_id, response, job)
        end

      _ ->
        %{url: nil, id: nil, email: nil}
    end

    :ok
  end

  @spec make_update_query(list(), non_neg_integer, String.t(), Oban.Job.t()) :: :ok
  defp make_update_query(data, organization_id, table, _job) do
    Bigquery.fetch_bigquery_credentials(organization_id)
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} ->
        data
        |> Enum.each(fn row ->
          sql = generate_update_sql_query(row, table, dataset_id, organization_id)

          GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
            body: %{query: sql, useLegacySql: false}
          )
          |> handle_update_response()
        end)

      _ ->
        %{url: nil, id: nil, email: nil}
    end
  end

  @spec generate_update_sql_query(map(), String.t(), String.t(), non_neg_integer()) :: String.t()
  defp generate_update_sql_query(flow_result, "update_flow_results", dataset_id, _organization_id) do
    "UPDATE `#{dataset_id}.flow_results` SET results = '#{flow_result["results"]}' WHERE contact_phone= '#{
      flow_result["contact_phone"]
    }' AND id = #{flow_result["id"]} AND flow_context_id =  #{flow_result["flow_context_id"]}"
  end

  defp generate_update_sql_query(contact, "update_contacts", dataset_id, organization_id) do
    contact_fields_to_update =
      ["fileds", "name", "optout_time", "optin_time", "language"]
      |> get_contact_values_to_update(contact, %{}, organization_id)
      |> Enum.map(fn {column, value} -> "#{column} = #{value}" end)
      |> Enum.join(",")

    "UPDATE `#{dataset_id}.contacts` SET #{contact_fields_to_update} WHERE phone= '#{
      contact["phone"]
    }'"
  end

  defp generate_update_sql_query(_, _, _, _), do: nil

  defp get_contact_values_to_update(["fileds" | tail], contact, acc, org_id) do
    if is_nil(contact["fileds"]) do
      get_contact_values_to_update(tail, contact, acc, org_id)
    else
      formatted_field_values = Bigquery.format_contact_field_values(contact["fields"], org_id)
      acc = Map.put(acc, "fileds", formatted_field_values)
      get_contact_values_to_update(tail, contact, acc, org_id)
    end
  end

  defp get_contact_values_to_update([column | tail], contact, acc, org_id) do
    if is_nil(contact[column]) do
      get_contact_values_to_update(tail, contact, acc, org_id)
    else
      acc = Map.put(acc, column, contact[column])
      get_contact_values_to_update(tail, contact, acc, org_id)
    end
  end

  defp get_contact_values_to_update([], _, acc, _), do: acc

  @spec handle_insert_error(String.t(), String.t(), non_neg_integer, any(), Oban.Job.t()) :: :ok
  defp handle_insert_error(table, dataset_id, organization_id, response, _job) do
    if should_retry_job?(response) do
      Bigquery.sync_schema_with_bigquery(dataset_id, organization_id)
      :ok
    else
      raise("Bigquery Insert Error for table #{table}  #{response}")
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

  @spec handle_update_response(tuple() | nil) :: any()
  defp handle_update_response({:ok, response}),
    do: response |> IO.inspect()

  defp handle_update_response({:error, error}),
    do: error |> IO.inspect()
end
