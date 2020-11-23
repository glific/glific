defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias Glific.{
    BigquerySchema,
    Partners,
    Repo
  }

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
    Api.Jobs,
    Api.Tables,
    Connection
  }

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec bigquery_dataset(String.t(), non_neg_integer) :: :ok
  def bigquery_dataset(dataset_id, organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["bigquery"]
    |> case do
      nil ->
        nil

      credentials ->
        project_id = credentials.secrets["project_id"]
        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)

        case create_dataset(conn, project_id, dataset_id) do
          {:ok, _} ->
            table(BigquerySchema.contact_schema(), conn, dataset_id, project_id, "contacts")
            table(BigquerySchema.message_schema(), conn, dataset_id, project_id, "messages")
            contacts_messages_view(conn, dataset_id, project_id)

          {:error, _} ->
            # when organization re-activates the credentials, update with new schema
            alter_bigquery_tables(dataset_id, organization_id)

            nil
        end
    end

    :ok
  end

  @doc """
  Alter bigquery table schema,
  if required this function should be called from iex
  """
  @spec alter_bigquery_tables(String.t(), non_neg_integer) :: :ok
  def alter_bigquery_tables(dataset_id, organization_id) do
    organization = Partners.organization(organization_id)

    credentials = organization.services["bigquery"]

    project_id = credentials.secrets["project_id"]
    token = Partners.get_goth_token(organization_id, "bigquery")
    conn = Connection.new(token.token)

    case Datasets.bigquery_datasets_get(conn, project_id, dataset_id) do
      {:ok, _} ->
        alter_table(BigquerySchema.contact_schema(), conn, dataset_id, project_id, "contacts")
        alter_table(BigquerySchema.message_schema(), conn, dataset_id, project_id, "messages")
        alter_contacts_messages_view(conn, dataset_id, project_id)

      {:error, _} ->
        nil
    end

    :ok
  end

  def update_contact(phone_no, updated_values, organization_id) do
    organization = Partners.organization(organization_id)|> Repo.preload(:contact)
    dataset_id = organization.contact.phone
    organization.services["bigquery"]
    |> case do
      nil ->
        nil
      credentials ->
        project_id = credentials.secrets["project_id"]
        sql = "UPDATE `#{dataset_id}.contacts` SET #{format_update_values(updated_values)} WHERE phone= #{phone_no}"
        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)
        {:ok, response} = Jobs.bigquery_jobs_query(
          conn,
          project_id,
          [body: %{ query: sql, useLegacySql: false}]
        )
        IO.inspect("response")
        IO.inspect(response)
    end
    :ok
  end

  defp format_update_values(map) do
    Map.keys(map)
    |> Enum.map(fn key -> " #{key} = #{map[key]}" end)
    |> Enum.join(",")
  end


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

  defp table(schema, conn, dataset_id, project_id, table_id) do
    {:ok, response} =
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

    response
  end

  defp alter_table(schema, conn, dataset_id, project_id, table_id) do
    {:ok, response} =
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

    response
  end

  defp contacts_messages_view(conn, dataset_id, project_id) do
    {:ok, response} =
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

    response
  end

  defp alter_contacts_messages_view(conn, dataset_id, project_id) do
    {:ok, response} =
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

    response
  end


end
