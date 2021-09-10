defmodule Glific.Clients.Avanti do
  @moduledoc """
  Fetches data from Plio Bigquery dataset to send reports to users
  """
  alias GoogleApi.BigQuery.V2.Api.Jobs

  @plio %{
    "dataset" => "haryana_sandbox",
    "analytics_table" => "plio_summary_stats",
    "teachers_table" => "school_profile"
  }
  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("check_if_existing_teacher", fields) do
    phone = fields["phone"] |> String.trim() |> String.trim("91")

    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :teachers) do
      data
      |> Enum.reduce(%{found: false}, fn teacher, acc ->
        if teacher["mobile_no"] == phone, do: acc |> Map.merge(%{found: true}), else: acc
      end)
    end
  end

  def webhook("fetch_report", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :analytics) do
      data
    end
  end

  # returns data queried from bigquery in the form %{data: data, is_valid: true}
  # or returns error as %{is_valid: false, message: error_message}
  @spec fetch_bigquery_data(map(), atom()) :: map()
  defp fetch_bigquery_data(fields, query_type) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        with sql <- get_report_sql(query_type),
             {:ok, response} <-
               Jobs.bigquery_jobs_query(conn, project_id,
                 body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
               ) do
          data =
            response.rows
            |> Enum.map(fn row ->
              row.f
              |> Enum.with_index()
              |> Enum.reduce(%{}, fn {cell, i}, acc ->
                acc |> Map.put_new("#{Enum.at(response.schema.fields, i).name}", cell.v)
              end)
            end)

          %{is_valid: true, data: data}
        else
          _ -> %{is_valid: false, message: "Permission issue while fetching data"}
        end

      _ ->
        %{is_valid: false, message: "Credentials not valid"}
    end
  end

  # returns query that need to be run in bigquery instance
  @spec get_report_sql(atom()) :: String.t()
  defp get_report_sql(:analytics) do
    time =
      DateTime.utc_now()
      |> Timex.shift(days: -3)
      |> Timex.format!("{YYYY}-{0M}-{0D} {h24}:{m}:{s}")

    """
    SELECT plio_name, viewers, avg_accuracy_percent, avg_watch_time  FROM `#{@plio["dataset"]}.#{@plio["analytics_table"]}` where first_sent_date > '#{time}' ;
    """
  end

  defp get_report_sql(:teachers) do
    """
    SELECT mobile_no FROM `#{@plio["dataset"]}.#{@plio["teachers_table"]}` ;
    """
  end
end
