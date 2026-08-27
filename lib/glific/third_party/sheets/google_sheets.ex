defmodule Glific.Sheets.GoogleSheets do
  @moduledoc """
  Glific Google sheet API layer
  """

  require Logger

  alias Glific.Partners
  import Glific.SafeLog
  alias Glific.Sheets
  alias Glific.Sheets.ApiClient

  @scopes [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly"
  ]

  @sheets_api_base_url "https://sheets.googleapis.com"

  @doc """
  Get headers (first row) from the spreadsheet.
  """
  @spec get_headers(non_neg_integer(), String.t()) :: {:ok, list(String.t())} | {:error, any()}
  def get_headers(org_id, spreadsheet_id) do
    with {:ok, %{conn: conn}} <- fetch_credentials(org_id) do
      case values_get(conn, spreadsheet_id, "1:1") do
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

      values_append(conn, spreadsheet_id, range, data)
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
          else: {:ok, %{conn: build_conn(token.token)}}

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
  @spec read_sheet_data(non_neg_integer(), String.t()) ::
          {:ok, list({:ok, map()})} | {:error, any()}
  def read_sheet_data(org_id, sheet_url) do
    spreadsheet_id = Sheets.extract_spreadsheet_id(sheet_url)
    gid = extract_gid(sheet_url)

    with {:ok, %{conn: conn}} <- fetch_credentials(org_id),
         {:ok, sheet_name} <- find_sheet_name(conn, spreadsheet_id, gid),
         range = "'#{sheet_name}'!A:ZZ",
         {:ok, %{values: values}} when not is_nil(values) <-
           values_get(conn, spreadsheet_id, range),
         {:ok, rows} <- convert_rows_to_csv_format(values) do
      {:ok, rows}
    else
      {:error, "Google API is not active"} ->
        {:ok, ApiClient.get_csv_content(spreadsheet_id, gid: gid) |> Enum.to_list()}

      {:ok, %{values: nil}} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Google Sheets API read failed for #{sheet_url}: #{safe_inspect(reason)}")

        {:error, reason}
    end
  end

  @spec extract_gid(String.t()) :: non_neg_integer()
  defp extract_gid(sheet_url) do
    case Regex.run(~r/[#?&]gid=(\d+)/, sheet_url) do
      [_, gid] -> String.to_integer(gid)
      _ -> 0
    end
  end

  @spec find_sheet_name(Tesla.Client.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp find_sheet_name(conn, spreadsheet_id, gid) do
    case spreadsheets_get(conn, spreadsheet_id) do
      {:ok, %{sheets: sheets}} when is_list(sheets) ->
        case Enum.find(sheets, fn s -> s.properties.sheetId == gid end) do
          nil -> {:error, "Sheet with gid #{gid} not found"}
          sheet -> {:ok, sheet.properties.title}
        end

      _ ->
        {:error, "Failed to fetch spreadsheet metadata"}
    end
  end

  @spec build_conn(String.t()) :: Tesla.Client.t()
  defp build_conn(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, @sheets_api_base_url},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]},
      {Tesla.Middleware.Opts, [recv_timeout: 10_000]},
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.PathParams,
      {Tesla.Middleware.Telemetry, metadata: %{provider: "google_sheets_api"}}
    ]

    Tesla.client(middleware ++ Glific.get_tesla_retry_middleware())
  end

  # The 3 Sheets v4 REST calls we need, hand-rolled with Tesla's BaseUrl +
  # PathParams instead of the generated `google_api_sheets` client: that client
  # resolves spreadsheet_id/range into the URL itself before Tesla's middleware
  # chain runs, so PathParams never sees a template and every spreadsheet
  # fragments AppSignal into its own endpoint entry.
  #
  # `range` is interpolated directly rather than routed through `path_params`:
  # PathParams percent-encodes via `URI.encode_www_form/1`, which turns a space
  # into `+` — wrong for a path segment (sheet/tab names can contain spaces) and
  # different from what the Sheets API expects. Encoding it ourselves with the
  # same rule the generated client used keeps the request byte-for-byte
  # identical; only `spreadsheet_id` (never contains characters that encode
  # differently between the two schemes) goes through `path_params`, which is
  # enough to group AppSignal by spreadsheet.
  @spec spreadsheets_get(Tesla.Client.t(), String.t()) :: {:ok, map()} | {:error, any()}
  defp spreadsheets_get(conn, spreadsheet_id) do
    conn
    |> Tesla.get("/v4/spreadsheets/:spreadsheet_id",
      opts: [path_params: [spreadsheet_id: spreadsheet_id]]
    )
    |> decode_sheets_response()
  end

  @spec values_get(Tesla.Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  defp values_get(conn, spreadsheet_id, range) do
    conn
    |> Tesla.get("/v4/spreadsheets/:spreadsheet_id/values/#{encode_range(range)}",
      opts: [path_params: [spreadsheet_id: spreadsheet_id]]
    )
    |> decode_sheets_response()
    |> put_default_values_key()
  end

  @spec put_default_values_key({:ok, map() | nil} | {:error, any()}) ::
          {:ok, map()} | {:error, any()}
  defp put_default_values_key({:ok, nil}), do: {:ok, %{values: nil}}
  defp put_default_values_key({:ok, response}), do: {:ok, Map.put_new(response, :values, nil)}
  defp put_default_values_key(error), do: error

  @spec values_append(Tesla.Client.t(), String.t(), String.t(), list(list())) ::
          {:ok, map()} | {:error, any()}
  defp values_append(conn, spreadsheet_id, range, values) do
    body = Jason.encode!(%{majorDimension: "ROWS", values: values})

    conn
    |> Tesla.post(
      "/v4/spreadsheets/:spreadsheet_id/values/#{encode_range(range)}:append",
      body,
      query: [valueInputOption: "USER_ENTERED"],
      headers: [{"content-type", "application/json"}],
      opts: [path_params: [spreadsheet_id: spreadsheet_id]]
    )
    |> decode_sheets_response()
  end

  @spec encode_range(String.t()) :: String.t()
  defp encode_range(range), do: URI.encode(range, &(URI.char_unreserved?(&1) || &1 == ?/))

  @spec decode_sheets_response(Tesla.Env.result()) :: {:ok, map() | nil} | {:error, any()}
  defp decode_sheets_response({:error, reason}), do: {:error, reason}

  defp decode_sheets_response({:ok, %Tesla.Env{status: status} = env})
       when status < 200 or status >= 300,
       do: {:error, env}

  defp decode_sheets_response({:ok, %Tesla.Env{body: body}}) when body in [nil, ""],
    do: {:ok, nil}

  defp decode_sheets_response({:ok, %Tesla.Env{body: body}}) when is_binary(body),
    do: Jason.decode(body, keys: :atoms)

  defp decode_sheets_response({:ok, %Tesla.Env{body: body}}), do: {:ok, body}

  @doc """
  Converts the Google Sheets API response (list of lists) into the
  `{:ok, map}` format expected by `run_sync_transaction/3`.
  The first list is treated as headers; subsequent lists are data rows.

  ## Examples

      iex> convert_rows_to_csv_format([["key", "age"], ["1", "22"]])
      {:ok, [{:ok, %{"key" => "1", "age" => "22"}}]}

  """
  @spec convert_rows_to_csv_format(list(list(String.t()))) ::
          {:ok, list({:ok, map()})} | {:error, String.t()}
  def convert_rows_to_csv_format([]), do: {:ok, []}

  def convert_rows_to_csv_format([headers | rows]) do
    trimmed_headers = Enum.map(headers, &String.trim/1)

    if Enum.any?(trimmed_headers, &(&1 == "")) or
         length(trimmed_headers) != length(Enum.uniq(trimmed_headers)) do
      {:error, "Repeated or missing headers"}
    else
      rows =
        Enum.map(rows, fn row ->
          padded_row =
            row
            |> Enum.map(&String.trim/1)
            |> then(&(&1 ++ List.duplicate("", max(0, length(trimmed_headers) - length(&1)))))

          row_map = trimmed_headers |> Enum.zip(padded_row) |> Map.new()
          {:ok, row_map}
        end)

      {:ok, rows}
    end
  end
end
