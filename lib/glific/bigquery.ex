defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  require Logger
  use Publicist

  alias Glific.{
    BigquerySchema,
    Contacts.Contact,
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs,
    Jobs.BigqueryJob,
    Messages.Message,
    Notifications,
    Partners,
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
    "stats" => :stats_schema
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

  # @spec get_table_struct(String.t()) :: Message.t() | Contact.t() | FlowResult.t() | FlowRevision.t()
  @doc false
  @spec get_table_struct(String.t()) :: any()
  def get_table_struct(table) do
    case table do
      "messages" -> Message
      "contacts" -> Contact
      "flow_results" -> FlowResult
      "flows" -> FlowRevision
      "stats" -> Stat
      "messages_delta" -> Message
      "contacts_delta" -> Contact
      "flow_results_delta" -> FlowResult
    end
  end

  @doc """
  Refresh the biquery schema and update all the older versions.
  """
  @spec do_refresh_the_schema(non_neg_integer, map()) ::
          {:error, Tesla.Env.t()} | {:ok, Tesla.Env.t()}
  def do_refresh_the_schema(
        organization_id,
        %{conn: conn, dataset_id: dataset_id, project_id: project_id} = _cred
      ) do
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

  @spec handle_sync_errors(map(), non_neg_integer, map()) :: :ok
  defp handle_sync_errors(response, organization_id, attrs) do
    Jason.decode(response.body)
    |> case do
      {:ok, data} ->
        error = data["error"]

        if error["status"] == "ALREADY_EXISTS" do
          do_refresh_the_schema(organization_id, attrs)
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
  @spec alter_tables(Tesla.Client.t(), String.t(), String.t()) :: :ok
  def alter_tables(conn, dataset_id, project_id) do
    case Datasets.bigquery_datasets_get(conn, project_id, dataset_id) do
      {:ok, _} ->
        @bigquery_tables
        |> Enum.each(fn {table_id, _schema} ->
          apply(BigquerySchema, @bigquery_tables[table_id], [])
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
  @spec make_insert_query(map() | list, String.t(), non_neg_integer, non_neg_integer) :: :ok
  def make_insert_query(%{json: data}, _table, _organization_id, _max_id)
      when data in [[], nil, %{}],
      do: :ok

  def make_insert_query(data, table, organization_id, max_id) do
    Logger.info(
      "insert data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{
        Enum.count(data)
      }"
    )

    fetch_bigquery_credentials(organization_id)
    |> do_make_insert_query(organization_id, data, table: table, max_id: max_id)
    |> handle_insert_query_response(organization_id, table: table, max_id: max_id)

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
      "inserting data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{
        Enum.count(data)
      }"
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

    cond do
      res.insertErrors != nil ->
        raise("Bigquery Insert Error for table #{table} with res: #{inspect(res)}")

      ## Max id will be nil or 0 in case of update statement.
      max_id not in [nil, 0] ->
        Jobs.update_bigquery_job(organization_id, table, %{table_id: max_id})

        Logger.info(
          "New Data has been inserted to bigquery successfully org_id: #{organization_id}, table: #{
            table
          }, res: #{inspect(res)}"
        )

      true ->
        Logger.info(
          "Updated Data has been inserted to bigquery successfully org_id: #{organization_id}, table: #{
            table
          }, res: #{inspect(res)}"
        )
    end

    :ok
  end

  defp handle_insert_query_response({:error, response}, organization_id, opts) do
    table = Keyword.get(opts, :table)

    Logger.info(
      "Error while inserting the data to bigquery. org_id: #{organization_id}, table: #{table}, response: #{
        inspect(response)
      }"
    )

    bigquery_error_status(response)
    |> case do
      "NOT_FOUND" ->
        sync_schema_with_bigquery(organization_id)

      "PERMISSION_DENIED" ->
        Partners.disable_credential(organization_id, "bigquery")
        Notifications.create_notification(%{
            category: "Bigquery",
            message: "Billing account is disabled for Bigquery",
            severity: "Error",
            organization_id: organization_id,
            entity: %{
              error: "#{inspect(response)}"
            }
        })


      _ ->
        raise("Bigquery Insert Error for table #{table}  #{response}")
    end
  end

  @spec bigquery_error_status(map()) :: String.t() | atom()
  defp bigquery_error_status(response) do
    with true <- Map.has_key?(response, :body),
         {:ok, error} <- Jason.decode(response.body) do
      error["error"]["status"]
    else
      _ -> :unknown
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

        GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
          body: %{query: sql, useLegacySql: false}
        )
        |> handle_duplicate_removal_job_error(table, credentials, organization_id)

      _ ->
        :ok
    end
  end

  @spec generate_duplicate_removal_query(String.t(), map(), non_neg_integer) :: String.t()
  defp generate_duplicate_removal_query(table, credentials, organization_id) do
    timezone = Partners.organization(organization_id).timezone

    "DELETE FROM `#{credentials.dataset_id}.#{table}` where struct(id, updated_at) in (select STRUCT(id, updated_at)  FROM( SELECT id, updated_at, ROW_NUMBER() OVER (PARTITION BY delta.id ORDER BY delta.updated_at DESC) as rn from `#{
      credentials.dataset_id
    }.#{table}` delta where updated_at < DATETIME(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR), '#{
      timezone
    }')) a where a.rn <> 1 order by id);"
  end

  @spec handle_duplicate_removal_job_error(tuple() | nil, String.t(), map(), non_neg_integer) ::
          :ok
  defp handle_duplicate_removal_job_error({:ok, response}, table, _credentials, organization_id),
    do:
      Logger.info(
        "duplicate entries have been removed from #{table} on bigquery for org_id: #{
          organization_id
        }. #{inspect(response)}"
      )

  defp handle_duplicate_removal_job_error({:error, error}, table, _, _) do
    Logger.error("Error while merging table #{table} on bigquery. #{inspect(error)}")

    raise "Error while removing duplicate entries from the table #{table} on bigquery. #{
            inspect(error)
          }"
  end
end
