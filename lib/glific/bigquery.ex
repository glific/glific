defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias Glific.BigquerySchema
  alias Glific.Partners

  alias GoogleApi.BigQuery.V2.{
    Api.Datasets,
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
        %{url: nil, id: nil, email: nil}

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
            nil
        end
    end

    :ok
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
end
