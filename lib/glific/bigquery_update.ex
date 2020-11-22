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
        sql = "UPDATE `#{dataset_id}.#{table_name}` SET #{field}= #{new_value} WHERE #{field}= #{old_value}"
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
end
