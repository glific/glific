defmodule Glific.BigqueryUpdate do
  @moduledoc """
  Glific Bigquery field updation
  """
  alias Glific.{
    Partners,
    Repo
  }
  alias GoogleApi.BigQuery.V2.{
    Api.Jobs,
    Connection,
  }

  @doc """
  Updating existing field in a table
    iex> Glific.BigqueryUpdate.sync_query("name", "same", "'AKHIL23'", "'Akhileshn'", 1)
  """
  def sync_query(field, table_name, old_value, new_value, organization_id) do
    organization = Partners.organization(organization_id)|> Repo.preload(:contact)
    dataset_id = organization.contact.phone
    organization.services["bigquery"]
    |> case do
      nil ->
        nil
      credentials ->
        project_id = credentials.secrets["project_id"]
        sql = get_query(dataset_id, table_name, field, new_value, old_value)
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
  defp get_query(dataset_id, table_name, field, new_value, old_value) do
    sql = "UPDATE `#{dataset_id}.#{table_name}` SET #{field}= #{new_value} WHERE #{field}= #{old_value}"
  end
end
