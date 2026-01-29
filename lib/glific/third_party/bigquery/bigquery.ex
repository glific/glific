defmodule Glific.BigQuery do
  @moduledoc """
  Glific BigQuery Dataset and table creation
  """

  require Logger
  use Publicist

  import Ecto.Query, warn: false

  alias Glific.{
    BigQuery.BigQueryJob,
    BigQuery.Schema,
    Certificates.CertificateTemplate,
    Certificates.IssuedCertificate,
    Contacts.Contact,
    Contacts.ContactHistory,
    Contacts.ContactsField,
    Flows,
    Flows.FlowCount,
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.MessageBroadcast,
    Flows.MessageBroadcastContact,
    Groups.ContactGroup,
    Groups.ContactWAGroup,
    Groups.Group,
    Groups.WAGroup,
    Groups.WAGroupsCollection,
    Jobs,
    Messages.Message,
    Messages.MessageConversation,
    Messages.MessageMedia,
    Partners,
    Partners.Saas,
    Profiles.Profile,
    Registrations.Registration,
    Repo,
    Searches.SavedSearch,
    Stats.Stat,
    Tags.Tag,
    Templates.InteractiveTemplate,
    Templates.SessionTemplate,
    Tickets.Ticket,
    Trackers.Tracker,
    TrialUsers,
    WAGroup.WAMessage,
    WAGroup.WaReaction,
    WhatsappForms.WhatsappForm,
    WhatsappForms.WhatsappFormResponse
  }

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
    Api.Routines,
    Api.Tabledata,
    Api.Tables,
    Connection
  }

  @bigquery_tables %{
    "contacts" => :contact_schema,
    "contact_histories" => :contact_history_schema,
    "contacts_fields" => :contact_fields_schema,
    "contacts_groups" => :contact_groups_schema,
    "contacts_wa_groups" => :contacts_wa_group_schema,
    "flow_contexts" => :flow_context_schema,
    "flow_counts" => :flow_count_schema,
    "flow_labels" => :flow_label_schema,
    "flow_results" => :flow_result_schema,
    "flows" => :flow_schema,
    "groups" => :group_schema,
    "interactive_templates" => :interactive_templates_schema,
    "message_broadcasts" => :message_broadcasts_schema,
    "message_broadcast_contacts" => :message_broadcast_contacts_schema,
    "message_conversations" => :message_conversation_schema,
    "messages" => :message_schema,
    "messages_media" => :messages_media_schema,
    "profiles" => :profile_schema,
    "stats" => :stats_schema,
    "saved_searches" => :saved_search_schema,
    "speed_sends" => :speed_send_schema,
    "tags" => :tag_schema,
    "tickets" => :ticket_schema,
    "trackers" => :trackers_schema,
    "wa_groups" => :wa_group_schema,
    "wa_groups_collections" => :wa_groups_collection_schema,
    "wa_messages" => :wa_message_schema,
    "wa_reactions" => :wa_reactions_schema,
    "whatsapp_forms" => :whatsapp_form_schema,
    "whatsapp_forms_responses" => :whatsapp_form_response_schema,
    "certificate_templates" => :certificate_templates_schema,
    "issued_certificates" => :issued_certificates_schema,
    "trial_users" => :trial_user_schema
  }

  @spec bigquery_tables(any) :: %{optional(<<_::40, _::_*8>>) => atom}
  defp bigquery_tables(organization_id) do
    if organization_id == Saas.organization_id() do
      Map.merge(@bigquery_tables, %{
        "stats_all" => :stats_all_schema,
        "trackers_all" => :trackers_all_schema
      })
    else
      @bigquery_tables
    end
  end

  @doc """
  Ignore the tables for updates operations
  """
  @spec ignore_updates_for_table() :: list()
  def ignore_updates_for_table do
    [
      "contact_histories",
      "flow_labels",
      "flows",
      "message_conversations",
      "stats",
      "stats_all",
      "tags"
    ]
  end

  @doc """
    Returns the status if the bigquery is enabled for
    organization.
  """
  @spec active?(non_neg_integer()) :: boolean()
  def active?(org_id) do
    organization = Partners.organization(org_id)
    not is_nil(organization.services["bigquery"])
  end

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec sync_schema_with_bigquery(non_neg_integer) :: {:ok, any} | {:error, any}
  def sync_schema_with_bigquery(organization_id) do
    with {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} <-
           fetch_bigquery_credentials(organization_id) do
      case create_dataset(conn, project_id, dataset_id) do
        {:ok, _} ->
          do_refresh_the_schema(organization_id, %{
            conn: conn,
            dataset_id: dataset_id,
            project_id: project_id
          })

          {:ok, "Refreshing Bigquery Schema"}

        {:error, response} ->
          handle_sync_errors(response, organization_id, %{
            conn: conn,
            dataset_id: dataset_id,
            project_id: project_id
          })
      end
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
        {:ok, "BigQuery is not active"}

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
          {:error, "Error fetching token with Service Account JSON"}
        else
          conn = Connection.new(token.token)
          {:ok, %{conn: conn, project_id: project_id, dataset_id: org_contact.phone}}
        end

      {:error, _error} ->
        {:error, "Invalid Service Account JSON"}
    end
  end

  @table_lookup %{
    "contact_histories" => ContactHistory,
    "contacts" => Contact,
    "contacts_fields" => ContactsField,
    "contacts_groups" => ContactGroup,
    "contacts_wa_groups" => ContactWAGroup,
    "flow_contexts" => Flows.FlowContext,
    "flow_counts" => FlowCount,
    "flow_labels" => Flows.FlowLabel,
    "flow_results" => FlowResult,
    "flows" => FlowRevision,
    "groups" => Group,
    "interactive_templates" => InteractiveTemplate,
    "message_broadcast_contacts" => MessageBroadcastContact,
    "message_broadcasts" => MessageBroadcast,
    "message_conversations" => MessageConversation,
    "messages" => Message,
    "messages_media" => MessageMedia,
    "profiles" => Profile,
    "stats" => Stat,
    "stats_all" => Stat,
    "saved_searches" => SavedSearch,
    "speed_sends" => SessionTemplate,
    "tags" => Tag,
    "tickets" => Ticket,
    "trackers" => Tracker,
    "trackers_all" => Tracker,
    "wa_groups" => WAGroup,
    "wa_groups_collections" => WAGroupsCollection,
    "wa_messages" => WAMessage,
    "wa_reactions" => WaReaction,
    "whatsapp_forms" => WhatsappForm,
    "whatsapp_forms_responses" => WhatsappFormResponse,
    "certificate_templates" => CertificateTemplate,
    "issued_certificates" => IssuedCertificate
  }

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

        case error["status"] do
          "ALREADY_EXISTS" ->
            do_refresh_the_schema(organization_id, attrs)
            {:ok, "Refreshing Bigquery Schema"}

          "PERMISSION_DENIED" ->
            {:error,
             "Account does not have sufficient permissions to create dataset to BigQuery."}

          _ ->
            {:error,
             "Account deactivated with error code #{error["code"]} status #{error["status"]}"}
        end

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
          Task.async(fn ->
            Repo.put_process_state(organization_id)

            apply(Schema, schema_fn, [])
            |> alter_table(%{
              conn: conn,
              dataset_id: dataset_id,
              project_id: project_id,
              table_id: table_id
            })
          end)
        end)

      {:error, _} ->
        nil
    end

    :ok
  end

  @doc """
  Format dates for the bigquery.
  """
  @spec format_date(DateTime.t() | nil, non_neg_integer()) :: String.t() | nil
  def format_date(nil, _),
    do: nil

  def format_date(date, organization_id) when is_binary(date) do
    timezone = Partners.organization(organization_id).timezone

    # We try to parse a string into date or datetime, since there
    # were cases where we have seen both formats, which is weird.
    # This will handle that until we can find the RCA.

    with {:error, _} <- Timex.parse(date, "{RFC3339z}"),
         {:error, _} <- Timex.parse(date, "{YYYY}-{0M}-{D}") do
      nil
    else
      {:ok, %DateTime{} = datetime} -> format_datetime(datetime, timezone)
      {:ok, %NaiveDateTime{} = datetime} -> format_datetime(datetime, timezone)
    end
  end

  def format_date(date, organization_id) do
    timezone = Partners.organization(organization_id).timezone
    format_datetime(date, timezone)
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
      "Insert data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{Enum.count(data)}"
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
      "Inserting data to bigquery for org_id: #{organization_id}, table: #{table}, rows_count: #{Enum.count(data)}"
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
          "New Data has been inserted to bigquery successfully org_id: #{organization_id}, table: #{table}, max_id: #{max_id}, res: #{inspect(res)}"
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

    {error, message} = bigquery_error_status(response)

    error
    |> case do
      "NOT_FOUND" ->
        sync_schema_with_bigquery(organization_id)

      "PERMISSION_DENIED" ->
        Partners.disable_credential(
          organization_id,
          "bigquery",
          message
        )

      "TIMEOUT" ->
        Logger.info("Timeout while inserting the data. #{inspect(response)}")

      _ ->
        raise("BigQuery Insert Error for table #{table} #{inspect(response)}")
    end
  end

  @spec bigquery_error_status(any()) :: {String.t() | atom(), String.t()}
  defp bigquery_error_status(response) do
    with true <- is_map(response),
         true <- Map.has_key?(response, :body),
         {:ok, error} <- Jason.decode(response.body) do
      [bq_error] = [error["error"]["errors"]]
      {error["error"]["status"], get_in(bq_error, [Access.at(0), "message"])}
    else
      _ ->
        if is_atom(response) do
          {"TIMEOUT", "TIMEOUT"}
        else
          Logger.info("Bigquery status error #{inspect(response)}")
          {:unknown, "UNKNOWN ERROR"}
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
        Logger.info("Remove duplicates on bigquery for org_id: #{organization_id} table:#{table}")

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
        "Duplicate entries have been removed for org_id: #{organization_id} from #{table} on bigquery "
      )

  ## Since we don't care about the delete query results, let's skip notifying this to AppSignal.
  defp handle_duplicate_removal_job_error({:error, error}, table, _, _) do
    Logger.error(
      "Error while removing duplicate entries from the table #{table} on bigquery. #{inspect(error)}"
    )
  end

  @doc """
    Syncing registration details to BQ instance
  """
  @spec sync_registration_details(non_neg_integer) :: {:ok, any()} | {:error, any()}
  def sync_registration_details(organization_id) do
    with {:ok, %{conn: conn, project_id: project_id, dataset_id: dataset_id}} <-
           fetch_bigquery_credentials(organization_id),
         {:ok, registration_data} <- fetch_registration_details(organization_id) do
      # creating table in BQ
      create_table(Schema.registration_schema(), %{
        conn: conn,
        dataset_id: dataset_id,
        project_id: project_id,
        table_id: "registration"
      })
      |> case do
        {:ok, _} ->
          Logger.info("Created registration table for org_id: #{organization_id}")

        {:error, %{body: body}} ->
          error = Jason.decode!(body)

          if error["error"]["status"] == "ALREADY_EXISTS" do
            Logger.info("Deleting old registration data in BQ for org_id: #{organization_id}")

            sql = "TRUNCATE TABLE `#{dataset_id}.registration`"

            GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
              body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
            )
          end
      end

      # syncing data to BQ
      do_sync_registration_details(conn, project_id, dataset_id, registration_data)
      |> case do
        {:ok, _} ->
          "Synced registration details"

        error ->
          Logger.error(
            "Error while syncing registration details for org_id: #{organization_id} #{inspect(error)}"
          )

          "Error while syncing details"
      end
    end
  end

  @spec do_sync_registration_details(Tesla.Env.client(), String.t(), String.t(), map()) ::
          {:ok, any()} | {:error, any()}
  defp do_sync_registration_details(conn, project_id, dataset_id, registration_data) do
    Tabledata.bigquery_tabledata_insert_all(
      conn,
      project_id,
      dataset_id,
      "registration",
      [
        body: %{
          rows: [
            %{
              json: %{
                org_details: format_json(registration_data.org_details),
                platform_details: format_json(registration_data.platform_details),
                finance_poc: format_json(registration_data.finance_poc),
                submitter: format_json(registration_data.submitter),
                signing_authority: format_json(registration_data.signing_authority),
                billing_frequency: registration_data.billing_frequency,
                ip_address: registration_data.ip_address,
                has_submitted: registration_data.has_submitted,
                terms_agreed: registration_data.terms_agreed,
                support_staff_account: registration_data.support_staff_account,
                is_disputed: registration_data.is_disputed,
                inserted_at: registration_data.inserted_at
              }
            }
          ]
        }
      ],
      []
    )
  end

  # fetching data from db for organization_id
  @spec fetch_registration_details(non_neg_integer) :: {:ok, map()} | {:error, String.t()}
  defp fetch_registration_details(organization_id) do
    data =
      Registration
      |> select([r], %{
        org_details: r.org_details,
        platform_details: r.platform_details,
        billing_frequency: r.billing_frequency,
        finance_poc: r.finance_poc,
        submitter: r.submitter,
        signing_authority: r.signing_authority,
        ip_address: r.ip_address,
        has_submitted: r.has_submitted,
        terms_agreed: r.terms_agreed,
        support_staff_account: r.support_staff_account,
        is_disputed: r.is_disputed,
        inserted_at: r.inserted_at
      })
      |> where([r], r.organization_id == ^organization_id)
      |> Repo.one()

    if is_nil(data),
      do: {:error, "Registration details for org_id: #{organization_id} not found"},
      else: {:ok, data}
  end

  @spec format_datetime(DateTime.t() | NaiveDateTime.t(), String.t()) :: String.t() | no_return()
  defp format_datetime(date, timezone) do
    date
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")
  end
end
