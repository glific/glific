defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias Glific.Partners

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
    table_id = table
    token = token(credentials)

    conn = GoogleApi.BigQuery.V2.Connection.new(token.token)
    {:ok, response} = GoogleApi.BigQuery.V2.Api.Datasets.bigquery_datasets_insert(
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
    table(dataset_id, project_id, "contacts")
    table(dataset_id, project_id, "messages")

    :ok
  end

  defp table(dataset_id, project_id, table_id) do
    {:ok, token} = Goth.Token.for_scope("https://www.googleapis.com/auth/cloud-platform")
    conn = GoogleApi.BigQuery.V2.Connection.new(token.token)
    {:ok, response} = GoogleApi.BigQuery.V2.Api.Tables.bigquery_tables_insert(
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
          fields: [
          %{
              name: "type",
              type: "STRING",
              mode: "REQUIRED"
          },
          %{
              name: "flow",
              type: "STRING",
              mode: "REQUIRED"
          },
          %{
            name: "tags",
            type: "RECORD",
            mode: "REPEATED",
            fields: [
                %{
                    name: "label",
                    type: "STRING",
                    mode: "REQUIRED"
                }
            ]
          }
          ]
        }
      }
      ],
      []
    )
    response
  end
end
