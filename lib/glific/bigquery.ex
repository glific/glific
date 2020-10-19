defmodule Glific.Bigquery do
  @moduledoc """
  Glific.Bigquery.make_dataset("HALO", 1)

  Glific Bigquery Dataset and table creation
  """

  alias Glific.Partners
  alias Glific.BigquerySchema

  alias GoogleApi.BigQuery.V2.{
    Api.Tabledata,
    Api.Datasets,
    Api.Tables,
    Connection
  }

  @spec token(map()) :: any()
  defp token(credentials) do
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

  @spec make_dataset(String.t(), non_neg_integer) :: :ok
  def make_dataset(dataset_id, organization_id) do
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
    {:ok, response} = Datasets.bigquery_datasets_insert(
      conn,
      project_id,
      [body: %{
        datasetReference: %{
          datasetId: dataset_id,
          projectId: project_id
        }
      }
      ],
      []
    )

    table(BigquerySchema.contact_schema, token, dataset_id, project_id, "contacts")
    table(BigquerySchema.message_schema, token, dataset_id, project_id, "messages")

    response
  end

  defp table(schema, token, dataset_id, project_id, table_id) do
    conn = Connection.new(token.token)
    {:ok, response} = Tables.bigquery_tables_insert(
      conn,
      project_id,
      dataset_id,
      [body: %{
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
