defmodule Glific.BigQuery do
  @moduledoc """
  Glific BigQuery Dataset and table creation
  """

  require Logger
  use Publicist

  alias Glific.{
    BigQuery.BigQueryJob,
    BigQuery.Schema,
    Contacts.Contact,
    Contacts.ContactHistory,
    Flows,
    Flows.FlowCount,
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs,
    Messages.Message,
    Messages.MessageConversation,
    Messages.MessageMedia,
    Partners,
    Partners.Saas,
    Profiles.Profile,
    Repo,
    Stats.Stat
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
    "contacts" => :contact_schema,
    "flows" => :flow_schema,
    "flow_results" => :flow_result_schema,
    "stats" => :stats_schema,
    "flow_counts" => :flow_count_schema,
    "messages_media" => :messages_media_schema,
    "flow_contexts" => :flow_context_schema,
    "profiles" => :profile_schema,
    "contact_histories" => :contact_history_schema,
    "message_conversations" => :message_conversation_schema
  }

  defp bigquery_tables(organization_id) do
    if organization_id == Saas.organization_id(),
      do: Map.put(@bigquery_tables, "stats_all", :stats_all_schema),
      else: @bigquery_tables
  end

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec sync_schema_with_bigquery(non_neg_integer) :: {:ok, any} | {:error, any}
  def sync_schema_with_bigquery(organization_id) do
    fetch_bigquery_credentials(organization_id)
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} ->
        case create_dataset(conn, project_id, dataset_id) do
          {:ok, _} ->
            do_refresh_the_schema(organization_id, %{
              conn: conn,
              dataset_id: dataset_id,
              project_id: project_id
            })

          {:error, response} ->
            handle_sync_errors(response, organization_id, %{
              conn: conn,
              dataset_id: dataset_id,
              project_id: project_id
            })
        end

      {:error, error} ->
        {:error, error}

      _ ->
        {:ok, "bigquery is not active"}
    end
  end

  @doc false
  @spec fetch_bigquery_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_bigquery_credentials(organization_id) do
    organization = Partners.organization(organization_id)
    org_contact = organization.contact

    organization.services["bigquery"]
    |> case do
      nil ->
        nil

      credentials ->
        decode_bigquery_credential(credentials, org_contact, organization_id)
    end
  end

  @doc """
  Decoding the credential for bigquery
  """
  @spec decode_bigquery_credential(map(), map(), non_neg_integer) :: {:ok, any} | {:error, any}
  def decode_bigquery_credential(
        credentials,
        org_contact,
        organization_id
      ) do
    case Jason.decode(credentials.secrets["service_account"]) do
      {:ok, service_account} ->
        project_id = service_account["project_id"]
        token = Partners.get_goth_token(organization_id, "bigquery")

        if is_nil(token) do
          token
        else
          conn = Connection.new(token.token)
          {:ok, %{conn: conn, project_id: project_id, dataset_id: org_contact.phone}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @table_lookup %{
    "messages" => Message,
    "contacts" => Contact,
    "flow_results" => FlowResult,
    "flows" => FlowRevision,
    "stats" => Stat,
    "stats_all" => Stat,
    "flow_counts" => FlowCount,
    "messages_media" => MessageMedia,
    "flow_contexts" => Flows.FlowContext,
    "profiles" => Profile,
    "contact_histories" => ContactHistory,
    "message_conversations" => MessageConversation
  }

  # @spec get_table_struct(String.t()) :: Message.t() | Contact.t() | FlowResult.t() | FlowRevision.t()
  @doc false
  @spec get_table_struct(String.t()) :: atom()
  def get_table_struct(table_name),
    do: Map.fetch!(@table_lookup, table_name)

  @doc """
  Refresh the bigquery schema and update all the older versions.
  """
  @spec do_refresh_the_schema(non_neg_integer, map()) ::
          {:error, Tesla.Env.t()} | {:ok, Tesla.Env.t()}
  def do_refresh_the_schema(
        organization_id,
        %{conn: conn, dataset_id: dataset_id, project_id: project_id} = _cred
      ) do
    Logger.info("refresh BigQuery schema for org_id: #{organization_id}")
    insert_bigquery_jobs(organization_id)
    create_tables(conn, organization_id, dataset_id, project_id)
    alter_tables(conn, organization_id, dataset_id, project_id)
    contacts_messages_view(conn, dataset_id, project_id)
    alter_contacts_messages_view(conn, dataset_id, project_id)
    flat_fields_procedure(conn, dataset_id, project_id)
  end

  @doc false
  @spec insert_bigquery_jobs(non_neg_integer) :: :ok
  def insert_bigquery_jobs(organization_id) do
    organization_id
    |> bigquery_tables()
    |> Map.keys()
    |> Enum.each(&create_bigquery_job(&1, organization_id))

    :ok
  end

  @doc false
  @spec create_bigquery_job(String.t(), non_neg_integer) :: :ok
  defp create_bigquery_job(table_name, organization_id) do
    Repo.fetch_by(BigQueryJob, %{table: table_name, organization_id: organization_id})
    |> case do
      {:ok, bigquery_job} ->
        bigquery_job

      _ ->
        %BigQueryJob{
          table: table_name,
          table_id: 0,
          organization_id: organization_id,
          last_updated_at: DateTime.utc_now()
        }
        |> Repo.insert!()
    end

    :ok
  end

  @spec handle_sync_errors(map(), non_neg_integer, map()) :: {:ok, any()}
  defp handle_sync_errors(response, organization_id, attrs) do
    Jason.decode(response.body)
    |> case do
      {:ok, data} ->
        error = data["error"]

        if error["status"] == "ALREADY_EXISTS" do
          do_refresh_the_schema(organization_id, attrs)
        end

        if error["status"] == "PERMISSION_DENIED",
          do:
            Partners.disable_credential(
              organization_id,
              "bigquery",
              "Account does not have sufficient permissions to create data set to BigQuery."
            )

        {:ok, data}

      _ ->
        raise("Error while sync data with bigquery. #{inspect(response)}")
    end
  end

  ## Creating a view with un nested fields from contacts
  @spec flat_fields_procedure(Tesla.Client.t(), String.t(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp flat_fields_procedure(conn, dataset_id, project_id) do
    routine_id = "flat_fields"
    definition = Schema.flat_fields_procedure(project_id, dataset_id)

    {:ok, _res} =
      create_or_update_procedure(
        %{conn: conn, dataset_id: dataset_id, project_id: project_id},
        routine_id,
        definition
      )
  end

  @spec create_or_update_procedure(map(), String.t(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp create_or_update_procedure(
         %{conn: conn, dataset_id: dataset_id, project_id: project_id} = _cred,
         routine_id,
         definition
       ) do
    body = [
      body: %{
        routineReference: %{routineId: routine_id, datasetId: dataset_id, projectId: project_id},
        routineType: "PROCEDURE",
        definitionBody: definition
      }
    ]

    with {:error, _response} <-
           Routines.bigquery_routines_insert(conn, project_id, dataset_id, body),
         do: Routines.bigquery_routines_update(conn, project_id, dataset_id, routine_id, body)
  end

  @spec create_tables(Tesla.Client.t(), non_neg_integer, binary, binary) :: :ok
  defp create_tables(conn, organization_id, dataset_id, project_id) do
    organization_id
    |> bigquery_tables()
    |> Enum.each(fn {table_id, schema_fn} ->
      apply(Schema, schema_fn, [])
      |> create_table(%{
        conn: conn,
        dataset_id: dataset_id,
        project_id: project_id,
        table_id: table_id
      })
    end)
  end

  @doc """
  Alter bigquery table schema,
  if required this function should be called from iex
  """
  @spec alter_tables(Tesla.Client.t(), non_neg_integer, String.t(), String.t()) :: :ok
  def alter_tables(conn, organization_id, dataset_id, project_id) do
    case Datasets.bigquery_datasets_get(conn, project_id, dataset_id) do
      {:ok, _} ->
        organization_id
        |> bigquery_tables()
        |> Enum.each(fn {table_id, schema_fn} ->
          apply(Schema, schema_fn, [])
          |> alter_table(%{
            conn: conn,
            dataset_id: dataset_id,
            project_id: project_id,
            table_id: table_id
          })
        end)

      {:error, _} ->
        nil
    end

    :ok
  end

  @doc """
  Format dates for the bigquery.
  """
  @spec format_date(DateTime.t() | nil, non_neg_integer()) :: String.t()
  def format_date(nil, _),
    do: nil

  def format_date(date, organization_id) when is_binary(date) do
    timezone = Partners.organization(organization_id).timezone

    Timex.parse(date, "{RFC3339z}")
    |> elem(1)
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")
  end

  def format_date(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")
  end

  @doc """
  Format all the json values
  """
  @spec format_json(map() | nil) :: iodata
  def format_json(nil), do: nil

  def format_json(definition) do
    Jason.encode(definition)
    |> case do
      {:ok, data} -> data
      _ -> nil
    end
  end

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

  @spec create_table(list(), map()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp create_table(
         schema,
         %{conn: conn, dataset_id: dataset_id, project_id: project_id, table_id: table_id} = _cred
       ) do
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

  @spec alter_table(list(), map()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
  defp alter_table(
         schema,
         %{conn: conn, dataset_id: dataset_id, project_id: project_id, table_id: table_id} = _cred
       ) do
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
            query: """
            SELECT messages.id, contact_phone, phone, name, optin_time. language,
              flow_label, messages.tags_label, messages.inserted_at, media_url
            FROM `#{project_id}.#{dataset_id}.messages` AS messages
            JOIN `#{project_id}.#{dataset_id}.contacts` AS contacts
              ON messages.contact_phone = contacts.phone
            """,
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
    Insert rows in the bigquery
  """
  @spec make_insert_query(map() | list, String.t(), non_neg_integer, Keyword.t()) :: :ok
  def make_insert_query(%{json: data}, _table, _organization_id, _max_id)
      when data in [[], nil, %{}],
      do: :ok

  def make_insert_query(data, table, organization_id, attrs) do
    max_id = Keyword.get(attrs, :max_id)
    last_updated_at = Keyword.get(attrs, :last_updated_at)

    Logger.info(
      "insert data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{Enum.count(data)}"
    )

    fetch_bigquery_credentials(organization_id)
    |> do_make_insert_query(organization_id, data,
      table: table,
      max_id: max_id,
      last_updated_at: last_updated_at
    )
    |> handle_insert_query_response(organization_id,
      table: table,
      max_id: max_id,
      last_updated_at: last_updated_at
    )

    :ok
  end

  @spec do_make_insert_query(tuple(), non_neg_integer, list(), Keyword.t()) ::
          {:ok, any()} | {:error, any()}
  defp do_make_insert_query(
         {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}},
         organization_id,
         data,
         opts
       ) do
    table = Keyword.get(opts, :table)

    Logger.info(
      "inserting data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{Enum.count(data)}"
    )

    Tabledata.bigquery_tabledata_insert_all(
      conn,
      project_id,
      dataset_id,
      table,
      [body: %{rows: data}],
      []
    )
  end

  @spec handle_insert_query_response(tuple(), non_neg_integer, Keyword.t()) :: :ok
  defp handle_insert_query_response({:ok, res}, organization_id, opts) do
    table = Keyword.get(opts, :table)
    max_id = Keyword.get(opts, :max_id)
    last_updated_at = Keyword.get(opts, :last_updated_at)

    cond do
      res.insertErrors != nil ->
        raise("BigQuery Insert Error for table #{table} with res: #{inspect(res)}")

      ## Max id will be nil or 0 in case of update statement.
      max_id not in [nil, 0] ->
        Jobs.update_bigquery_job(organization_id, table, %{table_id: max_id})

        Logger.info(
          "New Data has been inserted to bigquery successfully org_id: #{organization_id}, table: #{table}, res: #{inspect(res)}"
        )

      last_updated_at not in [nil, 0] ->
        Jobs.update_bigquery_job(organization_id, table, %{last_updated_at: last_updated_at})

        Logger.info(
          "Updated Data has been inserted to bigquery successfully org_id: #{organization_id}, last_updated_at: #{last_updated_at} table: #{table}, res: #{inspect(res)}"
        )

      true ->
        Logger.info("Count not found the operation for bigquery insert and update")
    end

    :ok
  end

  defp handle_insert_query_response({:error, response}, organization_id, opts) do
    table = Keyword.get(opts, :table)

    Logger.info(
      "Error while inserting the data to bigquery. org_id: #{organization_id}, table: #{table}, response: #{inspect(response)}"
    )

    bigquery_error_status(response)
    |> case do
      "NOT_FOUND" ->
        sync_schema_with_bigquery(organization_id)

      "PERMISSION_DENIED" ->
        Partners.disable_credential(
          organization_id,
          "bigquery",
          "Account does not have sufficient permissions to insert data to BigQuery."
        )

      "TIMEOUT" ->
        Logger.info("Timeout while inserting the data. #{inspect(response)}")

      _ ->
        raise("BigQuery Insert Error for table #{table} #{inspect(response)}")
    end
  end

  @spec bigquery_error_status(any()) :: String.t() | atom()
  defp bigquery_error_status(response) do
    with true <- is_map(response),
         true <- Map.has_key?(response, :body),
         {:ok, error} <- Jason.decode(response.body) do
      error["error"]["status"]
    else
      _ ->
        if is_atom(response) do
          "TIMEOUT"
        else
          Logger.info("Bigquery status error #{inspect(response)}")
          :unknown
        end
    end
  end

  @doc """
    Merge delta and main tables.
  """
  @spec make_job_to_remove_duplicate(String.t(), non_neg_integer) :: :ok
  def make_job_to_remove_duplicate(table, organization_id) do
    fetch_bigquery_credentials(organization_id)
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = credentials} ->
        Logger.info(
          "remove duplicates for  #{table} table on bigquery, org_id: #{organization_id}"
        )

        sql = generate_duplicate_removal_query(table, credentials, organization_id)

        ## timeout takes some time to delete the old records. So increasing the timeout limit.
        GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
          body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
        )
        |> handle_duplicate_removal_job_error(table, credentials, organization_id)

      _ ->
        :ok
    end
  end

  @spec generate_duplicate_removal_query(String.t(), map(), non_neg_integer) :: String.t()
  defp generate_duplicate_removal_query(table, credentials, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    """
    DELETE FROM `#{credentials.dataset_id}.#{table}`
    WHERE struct(id, updated_at, bq_uuid) IN (
      SELECT STRUCT(id, updated_at, bq_uuid)  FROM (
        SELECT id, updated_at, bq_uuid, ROW_NUMBER() OVER (
          PARTITION BY delta.id ORDER BY delta.updated_at DESC
        ) AS rn
        FROM `#{credentials.dataset_id}.#{table}` delta
        WHERE updated_at < DATETIME(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR),
          '#{timezone}')) a WHERE a.rn <> 1 ORDER BY id);
    """
  end

  @spec handle_duplicate_removal_job_error(tuple() | nil, String.t(), map(), non_neg_integer) ::
          :ok
  defp handle_duplicate_removal_job_error({:ok, _response}, table, _credentials, organization_id),
    do:
      Logger.info(
        "duplicate entries have been removed from #{table} on bigquery for org_id: #{organization_id}"
      )

  ## Since we don't care about the delete query results, let's skip notifying this to AppSignal.
  defp handle_duplicate_removal_job_error({:error, error}, table, _, _) do
    Logger.error(
      "Error while removing duplicate entries from the table #{table} on bigquery. #{inspect(error)}"
    )
  end
end
