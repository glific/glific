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
  @gcs_url "https://storage.googleapis.com/reports-af/haryana/sandbox/teacher_reports/"
  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """

  @spec webhook(String.t(), map()) :: map()
  def webhook("get_gcs_reports", fields) do
    phone = clean_phone(fields)
    {:ok, now} = "Asia/Kolkata" |> DateTime.now()
    date = now |> DateTime.to_date()

    numeric_sequence =
      if fields["reports_count"] == "1",
        do: "",
        else: fields["reports_count"]

    url = @gcs_url <> "#{phone}_#{date}_#{numeric_sequence}.pdf"
    %{url: url}
  end

  def webhook("process_reports", fields) do
    count = fields["count"] |> Glific.parse_maybe_integer() |> elem(1)

    reports = Jason.decode!(fields["reports"])
    report = reports[fields["count"]]

    report
    |> Map.put(:is_valid, true)
    |> Map.put(:count, count - 1)
  end

  def webhook("check_if_existing_teacher", fields) do
    phone = clean_phone(fields)

    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :teachers) do
      data
      |> Enum.reduce(%{found: false}, fn teacher, acc ->
        if teacher["mobile_no"] == phone,
          do: acc |> Map.merge(%{found: true, faculty_name: teacher["faculty_name"]}),
          else: acc
      end)
    end
  end

  def webhook("fetch_reports", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :analytics) do
      indexed_report =
        data
        |> Enum.with_index(1)
        |> Enum.reduce(%{}, fn {report, index}, acc -> Map.put(acc, index, report) end)

      count = data |> length()
      reports = Jason.encode!(indexed_report)

      %{is_valid: true, count: count, reports: reports}
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
             {:ok, %{totalRows: total_rows} = response} <-
               Jobs.bigquery_jobs_query(conn, project_id,
                 body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
               ),
             true <- total_rows != "0" do
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
    SELECT * FROM `#{@plio["dataset"]}.#{@plio["analytics_table"]}`
    WHERE faculty_mobile_no = '#{phone}'
    ORDER BY first_sent_date DESC;
    """
  end

  defp get_report_sql(:teachers, _fields) do
    """
    SELECT mobile_no, faculty_name
    FROM `#{@plio["dataset"]}.#{@plio["teachers_table"]}` ;
    """
  end

  @spec clean_phone(map()) :: String.t()
  defp clean_phone(fields) do
    phone = String.trim(fields["phone"])
    length = String.length(phone)
    String.slice(phone, length - 10, length)
  end
end
