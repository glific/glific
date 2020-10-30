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
  Generating Goth token
  """
  @spec token(map()) :: any()
  def token(credentials) do
    config =
      case Jason.decode(credentials.secrets["service_account"]) do
        {:ok, config} -> config
        _ -> :error
      end

    Goth.Config.add_config(config)

    {:ok, token} =
      Goth.Token.for_scope({credentials.secrets["project_email"], credentials.keys["url"]})

    token
  end

  @doc """
  Creating a dataset with messages and contacts as tables
  """
  @spec bigquery_dataset(String.t(), non_neg_integer) :: :ok
  def bigquery_dataset(dataset_id, organization_id) do
    organization = Partners.organization(organization_id)

    credentials =
      organization.services["bigquery"]
      |> case do
        nil -> %{url: nil, id: nil, email: nil}
        credentials -> credentials
      end

    project_id = credentials.secrets["project_id"]
    token = token(credentials)
    conn = Connection.new(token.token)

    case create_dataset(conn, project_id, dataset_id) do
      {:ok, _} ->
        table(BigquerySchema.contact_schema(), conn, dataset_id, project_id, "contacts")
        table(BigquerySchema.message_schema(), conn, dataset_id, project_id, "messages")

      {:error, _} ->
        nil
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
end
