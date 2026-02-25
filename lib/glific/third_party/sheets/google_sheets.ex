defmodule Glific.Sheets.GoogleSheets do
  @moduledoc """
  Glific Google sheet API layer
  """

  alias Glific.Partners

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
end
