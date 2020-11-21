defmodule Glific.Bigquery do
  @moduledoc """
  Glific Bigquery Dataset and table creation
  """

  alias GoogleApi.BigQuery.V2.{
    Api.Jobs,
    Connection
  }
  def sync_query(project_id, attr, value, valuen, organization_id) do
    # Fetch access token
    sql = "UPDATE `demo.same` SET #{attr}= #{valuen} WHERE #{attr}= #{value}"
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
end
