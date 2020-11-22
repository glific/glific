defmodule Glific.BigqueryUpdate do
  @moduledoc """
  Glific Bigquery field updation
  """
  alias Glific.Partners
  alias GoogleApi.BigQuery.V2.{
    Api.Jobs,
    Connection,
  }

  @doc """
  Updating existing field in a table
  Glific.BigqueryUpdate.sync_query("phone", 8888, 8881, 1)
  """
  def sync_query(field, old_value, new_value, organization_id) do
    organization = Partners.organization(organization_id)
    organization.services["bigquery"]
    |> case do
      nil ->
        nil
      credentials ->
        project_id = credentials.secrets["project_id"]
        sql = "UPDATE `demo.same` SET #{field}= #{new_value} WHERE #{field}= #{old_value}"
        token = Partners.get_goth_token(organization_id, "bigquery")
        conn = Connection.new(token.token)
        # Make the API request
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
end
