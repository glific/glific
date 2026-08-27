defmodule Glific.Sheets.ApiClient do
  @moduledoc """
  Http API client to interact with Gupshup
  """

  @csv_export_base_url "https://docs.google.com/spreadsheets/d"

  @doc """
  Get the CSV content for a spreadsheet's public export URL.
  """
  @spec get_csv_content(String.t(), keyword()) :: Keyword.t()
  def get_csv_content(spreadsheet_id, query_params \\ [])

  def get_csv_content(spreadsheet_id, query_params) when is_binary(spreadsheet_id) do
    query_string = URI.encode_query([{:format, "csv"} | query_params])

    {:ok, response} =
      get_tesla_middlewares()
      |> Tesla.client()
      |> Tesla.get("/:spreadsheet_id/export?#{query_string}",
        opts: [path_params: [spreadsheet_id: spreadsheet_id]]
      )

    {:ok, stream} = StringIO.open(response.body)

    IO.binstream(stream, :line)
    |> CSV.decode(headers: true, field_transform: &String.trim/1, escape_max_lines: 50)
  end

  def get_csv_content(_spreadsheet_id, _query_params), do: [ok: %{}]

  @spec get_tesla_middlewares :: list()
  defp get_tesla_middlewares do
    [
      {Tesla.Middleware.BaseUrl, @csv_export_base_url},
      Tesla.Middleware.FollowRedirects,
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.PathParams,
      {Tesla.Middleware.Telemetry, metadata: %{provider: "google_sheets", sampling_scale: 10}}
    ] ++
      Glific.get_tesla_retry_middleware()
  end
end
