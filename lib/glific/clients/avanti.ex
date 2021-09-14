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
    phone = clean_phone(fields)

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
      |> List.first()
      |> Map.merge(%{is_valid: true})
    end
  end

  # returns data queried from bigquery in the form %{data: data, is_valid: true}
  # or returns error as %{is_valid: false, message: error_message}
  @spec fetch_bigquery_data(map(), atom()) :: map()
  defp fetch_bigquery_data(fields, query_type) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        with sql <- get_report_sql(query_type, fields),
             {:ok, %{totalRows: totalRows} = response} <-
               Jobs.bigquery_jobs_query(conn, project_id,
                 body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
               ),
             true <- totalRows != "0" do
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
          _ -> %{is_valid: false, message: "No data found for phone: #{fields["phone"]}"}
        end

      _ ->
        %{is_valid: false, message: "Credentials not valid"}
    end
  end

  # returns query that need to be run in bigquery instance
  @spec get_report_sql(atom(), map()) :: String.t()
  defp get_report_sql(:analytics, fields) do
    phone = clean_phone(fields)

    """
    SELECT * FROM `#{@plio["dataset"]}.#{@plio["analytics_table"]}` where faculty_mobile_no = '#{
      phone
    }' ORDER BY first_sent_date DESC LIMIT 1;
    """
  end

  defp get_report_sql(:teachers, _fields) do
    """
    SELECT mobile_no FROM `#{@plio["dataset"]}.#{@plio["teachers_table"]}` ;
    """
  end

  @spec clean_phone(map()) :: String.t()
  defp clean_phone(fields) do
    length = fields["phone"] |> String.trim() |> String.length()
    fields["phone"] |> String.trim() |> String.slice(length - 10, length)
  end
end
