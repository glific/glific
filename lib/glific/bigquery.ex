defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias Glific.{
    BigquerySchema,
    Contacts.Contact,
    Flows.FlowResult,
    Flows.FlowRevision,
    Jobs.BigqueryJob,
    Messages.Message,
    Partners,
    Repo
  }

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
    Api.Routines,
    Api.Tables,
    Connection
  }

  @bigquery_tables %{
    "messages" => :message_schema,
    "contacts" => :contact_schema,
    "flows" => :flow_schema,
    "flow_results" => :flow_result_schema
  }

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec sync_schema_with_bigquery(String.t(), non_neg_integer) :: :ok
  def sync_schema_with_bigquery(_dataset_id, organization_id) do
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
    organization =
      Partners.organization(organization_id)
      |> Repo.preload(:contact)

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
      "contacts" -> Contact
      "flows" -> FlowRevision
      "flow_results" -> FlowResult
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
    insert_bigquery_jobs(organization_id)
    create_tables(conn, dataset_id, project_id)
    alter_tables(conn, dataset_id, project_id)
    contacts_messages_view(conn, dataset_id, project_id)
    alter_contacts_messages_view(conn, dataset_id, project_id)
    flat_fields_procedure(conn, dataset_id, project_id)
  end

  @doc false
  @spec insert_bigquery_jobs(non_neg_integer) :: :ok
  def insert_bigquery_jobs(organization_id),
    do:
      @bigquery_tables
      |> Map.keys()
      |> Enum.each(&create_bigquery_job(&1, organization_id))

  @doc false
  @spec create_bigquery_job(String.t(), non_neg_integer) :: :ok
  defp create_bigquery_job(table_name, organization_id) do
    Repo.fetch_by(BigqueryJob, %{table: table_name, organization_id: organization_id})
    |> case do
      {:ok, bigquery_job} ->
        bigquery_job

      _ ->
        %BigqueryJob{}
        |> BigqueryJob.changeset(%{table: table_name, organization_id: organization_id})
        |> Repo.insert()
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

  @spec create_tables(Tesla.Client.t(), String.t(), String.t()) ::
          {:ok, GoogleApi.BigQuery.V2.Model.Table.t()} | {:ok, Tesla.Env.t()} | {:error, any()}
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
  def alter_tables(conn, project_id, dataset_id) do
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

  @doc """
  Format contact field values for the bigquery.
  """

  @spec format_contact_field_values(list() | any(), integer()) :: any()
  def format_contact_field_values(contact_fields, org_id) when is_list(contact_fields) do
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

  def format_contact_field_values(field, _org_id), do: field

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
end
