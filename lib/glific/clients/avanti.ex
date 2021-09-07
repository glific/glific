defmodule Glific.Clients.Avanti do
  @moduledoc """
  Fetches data from Plio Bigquery dataset to send reports to users
  """
  alias Glific.{
    Contacts,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Repo
  }

  @plio %{
    "dataset" => "917302307943",
    "table" => "flows"
  }

  def webhook("fetch_report", fields) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        sql = get_sql()

        with {:ok, response} <-
               GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
                 body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
               ) do
          response.rows
          |> Enum.map(fn row ->
            row.f
            |> Enum.with_index()
            |> Enum.reduce(%{}, fn {cell, i}, acc ->
              acc
              |> Map.put_new("#{Enum.at(response.schema.fields, i).name}", cell.v)
            end)
          end)
        else
          _ -> %{is_valid: false, message: "Permission issue while fetching data"}
        end

      _ ->
        %{is_valid: false, message: "Credentials not valid"}
    end
  end

  defp get_sql do
    time =
      DateTime.utc_now()
      |> Timex.shift(days: -6)
      |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")

    """
    SELECT name, uuid FROM `#{@plio["dataset"]}.#{@plio["table"]}` where inserted_at > '#{time}' ;
    """
  end
end
