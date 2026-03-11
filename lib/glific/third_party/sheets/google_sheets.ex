defmodule Glific.Sheets.GoogleSheets do
  @moduledoc """
  Glific Google sheet API layer
  """

  alias Glific.Partners
  alias Glific.Sheets
  alias Glific.Sheets.ApiClient

  alias GoogleApi.Sheets.V4.{
    Api.Spreadsheets,
    Connection
  }

  @scopes [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly"
  ]

  @doc """
  Get headers (first row) from the spreadsheet.
  """
  @spec get_headers(non_neg_integer(), String.t()) :: {:ok, list(String.t())} | {:error, any()}
  def get_headers(org_id, spreadsheet_id) do
    with {:ok, %{conn: conn}} <- fetch_credentials(org_id) do
      case Spreadsheets.sheets_spreadsheets_values_get(conn, spreadsheet_id, "1:1") do
        {:ok, %{values: [headers | _]}} when is_list(headers) ->
          {:ok, headers}

        {:ok, %{values: nil}} ->
          {:error, "No headers found in the spreadsheet"}

        {:ok, _} ->
          {:error, "Invalid header format in the spreadsheet"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Insert new row to the spreadsheet.
  """
  @spec insert_row(non_neg_integer(), String.t(), map()) :: {:ok, any()} | {:error, any()}
  def insert_row(org_id, spreadsheet_id, %{range: range, data: data} = _params) do
    with {:ok, %{conn: conn}} <- fetch_credentials(org_id) do
      Glific.Metrics.increment("Sheets Write", org_id)

      params = [
        valueInputOption: "USER_ENTERED",
        body: %{majorDimension: "ROWS", values: data}
      ]

      Spreadsheets.sheets_spreadsheets_values_append(conn, spreadsheet_id, range, params)
    end
  end

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["google_sheets"]
    |> case do
      nil ->
        {:error, "Google API is not active"}

      credentials ->
        decode_credential(credentials, organization_id)
    end
  end

  @doc """
  Decoding the credential for google sheets
  """
  @spec decode_credential(map(), non_neg_integer) :: {:ok, any} | {:error, any}
  def decode_credential(credentials, organization_id) do
    case Jason.decode(credentials.secrets["service_account"]) do
      {:ok, _service_account} ->
        token = Partners.get_goth_token(organization_id, "google_sheets", scopes: @scopes)

        if is_nil(token),
          do: {:error, "Error fetching token with Service Account JSON"},
          else: {:ok, %{conn: Connection.new(token.token)}}

      {:error, _error} ->
        {:error, "Invalid Service Account JSON"}
    end
  end

  @doc """
  Read all rows from the spreadsheet.
  Tries authenticated access first; falls back to public CSV export if credentials
  are unavailable or the API call fails.
  Returns a list of `{:ok, map()}` rows where each map has header names as keys.
  """
  @spec read_sheet_data(non_neg_integer(), String.t()) :: {:ok, list({:ok, map()})}
  def read_sheet_data(org_id, sheet_url) do
    spreadsheet_id = Sheets.extract_spreadsheet_id(sheet_url)

    with {:ok, %{conn: conn}} <- fetch_credentials(org_id),
         {:ok, %{values: values}} when not is_nil(values) <-
           Spreadsheets.sheets_spreadsheets_values_get(conn, spreadsheet_id, "A:ZZ") do
      {:ok, convert_rows_to_csv_format(values)}
    else
      _ -> {:ok, ApiClient.get_csv_content(url: sheet_url) |> Enum.to_list()}
    end
  end

  @doc """
  Converts the Google Sheets API response (list of lists) into the
  `{:ok, map}` format expected by `run_sync_transaction/3`.
  The first list is treated as headers; subsequent lists are data rows.

  ## Examples

      iex> convert_rows_to_csv_format([["key", "age"], ["1", "22"]])
      [{:ok, %{"key" => "1", "age" => "22"}}]

  """
  @spec convert_rows_to_csv_format(list(list(String.t()))) :: list({:ok, map()})
  def convert_rows_to_csv_format([]), do: []

  def convert_rows_to_csv_format([headers | rows]) do
    Enum.map(rows, fn row ->
      padded_row = row ++ List.duplicate("", max(0, length(headers) - length(row)))

      row_map =
        headers
        |> Enum.zip(padded_row)
        |> Map.new()

      {:ok, row_map}
    end)
  end
end
