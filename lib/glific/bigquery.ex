defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  require Logger

  alias Glific.{
    BigquerySchema,
    Contacts.Contact,
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs,
    Jobs.BigqueryJob,
    Messages.Message,
    Partners,
    Repo
  }

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
    Api.Routines,
    Api.Tabledata,
    Api.Tables,
    Connection
  }

  @bigquery_tables %{
    "messages" => :message_schema,
    "message_delta" => :message_delta_schema,

    "contacts" => :contact_schema,
    "contact_delta" => :contact_delta_schema,

    "flows" => :flow_schema,

    "flow_results" => :flow_result_schema,
    "flow_result_delta" => :flow_result_delta_schema
  }

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec sync_schema_with_bigquery(non_neg_integer) :: :ok
  def sync_schema_with_bigquery(organization_id) do
    fetch_bigquery_credentials(organization_id)
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} ->
        case create_dataset(conn, project_id, dataset_id) do
          {:ok, _} ->
            do_refresh_the_schema(conn, dataset_id, project_id, organization_id)

          {:error, response} ->
            handle_sync_errors(response, conn, dataset_id, project_id, organization_id)
        end

      _ ->
        nil
    end

    :ok
  end

  @doc false
  @spec fetch_bigquery_credentials(non_neg_integer) :: nil | tuple
  def fetch_bigquery_credentials(organization_id) do
    organization = Partners.organization(organization_id)
    org_contact = organization.contact

    organization.services["bigquery"]
    |> case do
      nil ->
        nil

      credentials ->
        {:ok, service_account} = Jason.decode(credentials.secrets["service_account"])
        project_id = service_account["project_id"]
        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)
        {:ok, %{conn: conn, project_id: project_id, dataset_id: org_contact.phone}}
    end
  end

  @doc false
  @spec get_table_struct(String.t()) :: any()
  def get_table_struct(table) do
    case table do
      "messages" -> Message
      "message_delta" -> Message
      "contacts" -> Contact
      "contact_delta" -> Contact
      "flows" -> FlowRevision
      "flow_results" -> FlowResult
      "flow_result_delta" -> FlowResult
      "update_flow_results" -> FlowResult
      _ -> ""
    end
  end

  @doc """
  Refresh the biquery schema and update all the older versions.
  """
  @spec do_refresh_the_schema(Tesla.Client.t(), binary, binary, non_neg_integer) ::
          {:error, Tesla.Env.t()} | {:ok, Tesla.Env.t()}
  def do_refresh_the_schema(conn, dataset_id, project_id, organization_id) do
    Logger.info("refresh Bigquery schema for org_id: #{organization_id}")
    insert_bigquery_jobs(organization_id)
    create_tables(conn, dataset_id, project_id)
    alter_tables(conn, dataset_id, project_id)
    contacts_messages_view(conn, dataset_id, project_id)
    alter_contacts_messages_view(conn, dataset_id, project_id)
    flat_fields_procedure(conn, dataset_id, project_id)
  end

  @doc false
  @spec insert_bigquery_jobs(non_neg_integer) :: :ok
  def insert_bigquery_jobs(organization_id) do
    @bigquery_tables
    |> Map.keys()
    |> Enum.each(&create_bigquery_job(&1, organization_id))

    :ok
  end

  @doc false
  @spec create_bigquery_job(String.t(), non_neg_integer) :: :ok
  defp create_bigquery_job(table_name, organization_id) do
    Repo.fetch_by(BigqueryJob, %{table: table_name, organization_id: organization_id})
    |> case do
      {:ok, bigquery_job} ->
        bigquery_job

      _ ->
        %BigqueryJob{table: table_name, table_id: 0, organization_id: organization_id}
        |> Repo.insert!()
    end

    :ok
  end

  @spec handle_sync_errors(map(), Tesla.Client.t(), String.t(), String.t(), non_neg_integer) ::
          :ok
  defp handle_sync_errors(response, conn, dataset_id, project_id, organization_id) do
    Jason.decode(response.body)
    |> case do
      {:ok, data} ->
        error = data["error"]

        if error["status"] == "ALREADY_EXISTS" do
          do_refresh_the_schema(conn, dataset_id, project_id, organization_id)
        end

      _ ->
        raise("Error while sync data with biquery. #{inspect(response)}")
    end

    :ok
  end

  ## Creating a view with unnested fields from contacts
  @spec flat_fields_procedure(Tesla.Client.t(), String.t(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp flat_fields_procedure(conn, dataset_id, project_id) do
    Routines.bigquery_routines_insert(
      conn,
      project_id,
      dataset_id,
      [
        body: %{
          routineReference: %{
            routineId: "flat_fields",
            datasetId: dataset_id,
            projectId: project_id
          },
          routineType: "PROCEDURE",
          definitionBody: BigquerySchema.flat_fields_procedure(project_id, dataset_id)
        }
      ],
      []
    )
  end

  @spec create_tables(Tesla.Client.t(), binary, binary) :: :ok
  defp create_tables(conn, dataset_id, project_id) do
    @bigquery_tables
    |> Enum.each(fn {table_id, _schema} ->
      apply(BigquerySchema, @bigquery_tables[table_id], [])
      |> create_table(conn, dataset_id, project_id, table_id)
    end)
  end

  @doc """
  Alter bigquery table schema,
  if required this function should be called from iex
  """
  @spec alter_tables(Tesla.Client.t(), String.t(), String.t()) :: :ok
  def alter_tables(conn, dataset_id, project_id) do
    case Datasets.bigquery_datasets_get(conn, project_id, dataset_id) do
      {:ok, _} ->
        @bigquery_tables
        |> Enum.each(fn {table_id, _schema} ->
          apply(BigquerySchema, @bigquery_tables[table_id], [])
          |> alter_table(conn, dataset_id, project_id, table_id)
        end)

      {:error, _} ->
        nil
    end

    :ok
  end

  @spec format_value(map() | any()) :: any()
  defp format_value(value) when is_map(value), do: Map.get(value, :input, "Unknown format")

  defp format_value(value), do: value

  @doc """
  Format dates for the bigquery.
  """

  @spec format_date(DateTime.t() | nil, non_neg_integer()) :: any()
  def format_date(nil, _),
    do: nil

  def format_date(date, organization_id) when is_binary(date) do
    timezone = Partners.organization(organization_id).timezone

    Timex.parse(date, "{RFC3339z}")
    |> elem(1)
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  def format_date(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{M}-{D} {h24}:{m}:{s}")
  end

  @doc """
    Format all the json values
  """
  @spec format_json(map()) :: iodata
  def format_json(definition) do
    Jason.encode(definition)
    |> case do
      {:ok, data} -> data
      _ -> nil
    end
  end

  @doc """
    Format Data for bigquery error
  """
  @spec format_data_for_bigquery(map(), String.t()) :: map()
  def format_data_for_bigquery(data, _table),
    do: %{json: data}

  @spec create_dataset(Tesla.Client.t(), String.t(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Dataset.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp create_dataset(conn, project_id, dataset_id) do
    Datasets.bigquery_datasets_insert(
      conn,
      project_id,
      [
        body: %{
          datasetReference: %{
            datasetId: dataset_id,
            projectId: project_id
          }
        }
      ],
      []
    )
  end

  @spec create_table(list(), Tesla.Client.t(), binary(), binary(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp create_table(schema, conn, dataset_id, project_id, table_id) do
    Tables.bigquery_tables_insert(
      conn,
      project_id,
      dataset_id,
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: table_id
          },
          schema: %{
            fields: schema
          }
        }
      ],
      []
    )
  end

  @spec alter_table(list(), Tesla.Client.t(), binary(), binary(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp alter_table(schema, conn, dataset_id, project_id, table_id) do
    Tables.bigquery_tables_update(
      conn,
      project_id,
      dataset_id,
      table_id,
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: table_id
          },
          schema: %{
            fields: schema
          }
        }
      ],
      []
    )
  end

  @spec contacts_messages_view(Tesla.Client.t(), String.t(), String.t()) ::
          GoogleApi.BigQuery.V2.Model.Table.t() | Tesla.Env.t() | String.t()
  defp contacts_messages_view(conn, dataset_id, project_id) do
    Tables.bigquery_tables_insert(
      conn,
      project_id,
      dataset_id,
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: "contacts_messages"
          },
          view: %{
            query:
              "SELECT messages.id, contact_phone, phone, name, optin_time, language, flow_label, messages.tags_label, messages.inserted_at, media_url
              FROM `#{project_id}.#{dataset_id}.messages` as messages
              JOIN `#{project_id}.#{dataset_id}.contacts` as contacts
              ON messages.contact_phone = contacts.phone",
            useLegacySql: false
          }
        }
      ],
      []
    )
    |> case do
      {:ok, response} -> response
      {:error, _} -> "Error creating a view"
    end
  end

  @spec alter_contacts_messages_view(Tesla.Client.t(), String.t(), String.t()) ::
          GoogleApi.BigQuery.V2.Model.Table.t() | Tesla.Env.t() | String.t()
  defp alter_contacts_messages_view(conn, dataset_id, project_id) do
    Tables.bigquery_tables_update(
      conn,
      project_id,
      dataset_id,
      "contacts_messages",
      [
        body: %{
          tableReference: %{
            datasetId: dataset_id,
            projectId: project_id,
            tableId: "contacts_messages"
          },
          view: %{
            query:
              "SELECT messages.id, uuid, contact_phone, phone, name, optin_time, language, flow_label, messages.tags_label, messages.inserted_at, media_url
              FROM `#{project_id}.#{dataset_id}.messages` as messages
              JOIN `#{project_id}.#{dataset_id}.contacts` as contacts
              ON messages.contact_phone = contacts.phone",
            useLegacySql: false
          }
        }
      ],
      []
    )
    |> case do
      {:ok, response} -> response
      {:error, _} -> "Error creating a view"
    end
  end

  @doc """
    Insert rows in the biqquery
  """
  @spec make_insert_query(list(), String.t(), non_neg_integer, Oban.Job.t(), non_neg_integer) ::
          :ok

  def make_insert_query(%{json: data}, _table, _organization_id, _job, _max_id)
      when data in [[], nil, %{}],
      do: :ok

  def make_insert_query(data, table, organization_id, job, max_id) do
    Logger.info("insert data to bigquery for org_id: #{organization_id}, table: #{table}")

    fetch_bigquery_credentials(organization_id)
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

  @spec handle_insert_error(String.t(), String.t(), non_neg_integer, any(), Oban.Job.t()) :: :ok
  defp handle_insert_error(table, _dataset_id, organization_id, response, _job) do
    Logger.info(
      "Error while inserting the data to bigquery. org_id: #{organization_id}, table: #{table}, response: #{
        inspect(response)
      }"
    )

    if should_retry_job?(response) do
      sync_schema_with_bigquery(organization_id)
      :ok
    else
      raise("Bigquery Insert Error for table #{table}  #{response}")
    end
  end

  @spec should_retry_job?(any()) :: boolean()
  defp should_retry_job?(response) do
    with true <- Map.has_key?(response, :body),
         {:ok, error} <- Jason.decode(response.body),
         true <- error["error"]["status"] == "NOT_FOUND" do
      true
    else
      _ -> false
    end
  end

  @doc """
    Update data on the bigquery
  """
  @spec make_update_query(list(), non_neg_integer, String.t(), Oban.Job.t()) :: :ok
  def make_update_query(data, organization_id, table, _job) do
    Logger.info("update data on bigquery for org_id: #{organization_id}, table: #{table}")

    fetch_bigquery_credentials(organization_id)
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
      ["name", "optout_time", "optin_time", "updated_at", "language", "fields", "groups"]
      |> get_contact_values_to_update(contact, %{}, organization_id)
      |> Enum.map(fn {column, value} -> "#{column} = #{value}" end)
      |> Enum.join(",")

    "UPDATE `#{dataset_id}.contacts` SET #{contact_fields_to_update} WHERE phone= '#{
      contact["phone"]
    }'"
  end

  defp generate_update_sql_query(message, "update_messages", dataset_id, _organization_id) do
    "UPDATE `#{dataset_id}.messages` SET `tags_label` = '#{message["tags_label"]}', `flow_label` =  '#{
      message["flow_label"]
    }', `flow_name` = '#{message["flow_name"]}', `flow_uuid` = '#{message["flow_uuid"]}'  WHERE contact_phone= '#{
      message["contact_phone"]
    }' AND id = #{message["id"]}"
  end

  defp generate_update_sql_query(_, _, _, _), do: nil

  defp get_contact_values_to_update([column | tail], contact, acc, org_id)
       when column in ["fields", "groups"] do
    if is_nil(contact[column]) or contact[column] in [nil, %{}, []] do
      get_contact_values_to_update(tail, contact, acc, org_id)
    else
      formatted_field_values = format_contact_field_values(column, contact[column], org_id)
      acc = Map.put(acc, "`#{column}`", formatted_field_values)
      get_contact_values_to_update(tail, contact, acc, org_id)
    end
  end

  defp get_contact_values_to_update([column | tail], contact, acc, org_id) do
    if is_nil(contact[column]) do
      get_contact_values_to_update(tail, contact, acc, org_id)
    else
      acc = Map.put(acc, column, format_value_for_bq(contact[column]))
      get_contact_values_to_update(tail, contact, acc, org_id)
    end
  end

  defp get_contact_values_to_update([], _, acc, _), do: acc

  @doc """
  Format contact field values for the bigquery.
  """
  @spec format_contact_field_values(String.t(), list() | any(), integer()) :: any()
  def format_contact_field_values("fields", contact_fields, org_id)
      when is_list(contact_fields) do
    values =
      Enum.map(contact_fields, fn contact_field ->
        contact_field = Glific.atomize_keys(contact_field)
        value = format_value(contact_field.value)

        "('#{contact_field.label}', '#{value}', '#{contact_field.type}', '#{
          format_date(contact_field.inserted_at, org_id)
        }')"
      end)

    "[STRUCT<label STRING, value STRING, type STRING, inserted_at DATETIME>#{
      Enum.join(values, ",")
    }]"
  end

  def format_contact_field_values("groups", groups, _org_id) when is_list(groups) do
    values =
      Enum.map(groups, fn group ->
        group = Glific.atomize_keys(group)
        "('#{group.label}', '#{group.description}')"
      end)

    "[STRUCT<label STRING, description STRING>#{Enum.join(values, ",")}]"
  end

  def format_contact_field_values(_, _field, _org_id), do: ""

  @spec format_value_for_bq(any() | String.t()) :: any()
  defp format_value_for_bq(value) when is_binary(value), do: "'#{value}'"
  defp format_value_for_bq(value), do: value

  @spec handle_update_response(tuple() | nil) :: any()
  defp handle_update_response({:ok, response}),
    do: Logger.info("Updated data on bigquery. #{inspect(response)}")

  defp handle_update_response({:error, error}),
    do: Logger.error("Error while updating data on bigquery. #{inspect(error)}")
end
