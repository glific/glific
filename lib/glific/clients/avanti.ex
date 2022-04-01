defmodule Glific.Clients.Avanti do
  @moduledoc """
  Fetches data from Plio Bigquery dataset to send reports to users
  """
  alias GoogleApi.BigQuery.V2.Api.Jobs

  @plio %{
    "dataset" => "haryana_sandbox",
    "analytics_table" => "plio_summary_stats",
    "teachers_table" => "school_profile",
    "student_table" => "student_data",
    "class_nudges" => "live_class_nudges"
  }
  @gcs_url "https://storage.googleapis.com/reports-af/haryana/sandbox/teacher_reports/"

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("get_gcs_reports", fields) do
    url =
      @gcs_url <>
        clean_phone(fields) <>
        "_" <>
        fields["plio_uuid"] <>
        "_" <>
        "#{Timex.today("Asia/Kolkata")}" <>
        ".pdf"

    url
    |> Glific.Messages.validate_media("document")
    |> Map.put(:url, url)
  end

  def webhook("process_reports", fields), do: parse_query_data(fields["count"], fields["reports"])

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

  def webhook("send_nudge", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :class_nudges) do
      data |> List.first()
    end
  end

  def webhook("check_if_existing_student", fields) do
    phone = clean_phone(fields)

    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :students) do
      data
      |> Enum.reduce(%{found: false}, fn student, acc ->
        if student["students_mobile_no"] == phone,
          do: acc |> Map.merge(%{found: true, student_name: student["student_name"]}),
          else: acc
      end)
    end
  end

  def webhook("fetch_reports", fields) do
    with %{is_valid: true, data: data} <- fetch_bigquery_data(fields, :analytics) do
      {indexed_report, key_map} = get_multi_query_data(data)

      key_map
      |> Map.put(:reports, Jason.encode!(indexed_report))
    end
  end

  def webhook("get_single_query_data", fields) do
    with %{is_valid: true, data: data} <- fetch_dynamic_bigquery_data(fields) do
      data
      |> List.first()
      |> Map.merge(%{found: true})
    end
  end

  def webhook("get_multi_query_data", fields) do
    with %{is_valid: true, data: data} <- fetch_dynamic_bigquery_data(fields) do
      {indexed_report, key_map} = get_multi_query_data(data)

      key_map
      |> Map.put(:multi_data, Jason.encode!(indexed_report))
    end
  end

  def webhook("parse_query_data", fields),
    do: parse_query_data(fields["count"], fields["multi_data"])

  def webhook("clean_phone", fields), do: %{phone: clean_phone(fields)}

  defp get_multi_query_data(data) do
    indexed_report =
      data
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {report, index}, acc -> Map.put(acc, index, report) end)

    {indexed_report,
     %{
       is_valid: true,
       count: length(data)
     }}
  end

  defp parse_query_data(count, data) do
    counter = count |> Glific.parse_maybe_integer() |> elem(1)

    data
    |> Jason.decode!()
    |> Map.get(count)
    |> Map.put(:is_valid, true)
    |> Map.put(:count, counter - 1)
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

  defp get_report_sql(:students, _fields) do
    """
    SELECT students_mobile_no, student_name
    FROM `#{@plio["dataset"]}.#{@plio["student_table"]}` ;
    """
  end

  defp get_report_sql(:class_nudges, fields) do
    phone = clean_phone(fields)

    """
    SELECT grade, main_batch_faculty, main_batch_timings, main_batch_link, main_batch_timings, additional_batch_timings, additional_batch_link
    FROM `#{@plio["dataset"]}.#{@plio["class_nudges"]}`
    WHERE students_mobile_no = '#{phone}' ;
    """
  end

  @spec clean_phone(map()) :: String.t()
  defp clean_phone(fields) do
    phone = String.trim(fields["phone"])
    length = String.length(phone)
    String.slice(phone, length - 10, length)
  end

  defp fetch_dynamic_bigquery_data(fields) do
    Glific.BigQuery.fetch_bigquery_credentials(fields["organization_id"])
    |> case do
      {:ok, %{conn: conn, project_id: project_id, dataset_id: _dataset_id} = _credentials} ->
        with sql <- get_report_dynamic_sql(fields),
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

  defp get_report_dynamic_sql(fields) do
    columns = fields["table_columns"]
    tablename = fields["table_name"] |> String.trim()

    if Map.has_key?(fields, "condition") && String.length(fields["condition"]) != 0 do
      condition = fields["condition"] |> String.trim()
      "SELECT #{columns} FROM `#{@plio["dataset"]}.#{tablename}` WHERE #{condition} ;"
    else
      "SELECT #{columns} FROM `#{@plio["dataset"]}.#{tablename}`;"
    end
  end
end
