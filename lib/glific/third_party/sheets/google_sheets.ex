defmodule Glific.Sheets.GoogleSheets do
  @moduledoc """
  Glific Google sheet API layer
  """

  alias GoogleApi.Sheets.V4.{
    Connection,
    Spreadsheets
  }

  @scopes [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly"
  ]

  def test(org_id) do
    spreadsheet_id = "161lpwhhxGyc-DwBkyVn25XMvPVuv1r1LL3udgye3cYE"

    insert_new_row(org_id, spreadsheet_id, %{
      range: "A:C",
      data: [["1", "2", "3"], ["4", "5", "6"]]
    })
  end

  def insert_new_row(org_id, spreadsheet_id, %{range: range, data: data} = _params) do
    {:ok, %{conn: conn}} = fetch_credentials(org_id)

    params = [
      valueInputOption: "USER_ENTERED",
      body: %{majorDimension: "ROWS", values: data}
    ]

    {:ok, response} =
      Spreadsheets.sheets_spreadsheets_values_append(conn, spreadsheet_id, range, params)

    response
  end

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)
    org_contact = organization.contact

    organization.services["bigquery"]
    |> case do
      nil ->
        {:ok, "Google API is not active"}

      credentials ->
        decode_credential(credentials, org_contact, organization_id)
    end
  end

  @doc """
  Decoding the credential for bigquery
  """
  @spec decode_credential(map(), map(), non_neg_integer) :: {:ok, any} | {:error, any}
  def decode_credential(credentials, org_contact, organization_id) do
    case Jason.decode(credentials.secrets["service_account"]) do
      {:ok, _service_account} ->
        token = Partners.get_goth_token(organization_id, "bigquery", scopes: @scopes)

        if is_nil(token),
          do: {:error, "Error fetching token with Service Account JSON"},
          else: {:ok, %{conn: Connection.new(token.token)}}

      {:error, _error} ->
        {:error, "Invalid Service Account JSON"}
    end
  end
end
