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
    iex> Glific.BigqueryUpdate.sync_query("same", 9997274468, %{"phone" => 809709, "name" => "PANKAJ2"}, 1)
  """
  def sync_query(table_name, phone_no, values, organization_id) do
    organization = Partners.organization(organization_id)|> Repo.preload(:contact)
    dataset_id = organization.contact.phone
    organization.services["bigquery"]
    |> case do
      nil ->
        nil
      credentials ->
        project_id = credentials.secrets["project_id"]
        sql = "UPDATE `#{dataset_id}.#{table_name}` SET #{format_update_values(values)} WHERE phone= #{phone_no}"
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
    |> Enum.map(fn key -> " #{key} = #{get_key(map[key])}" end)
    |> Enum.join(",")
  end

  defp get_key(value) when is_binary(value), do: "'#{value}'"
  defp get_key(value), do: value

end
