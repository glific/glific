defmodule Glific.Sheets do
  @moduledoc """
  The Sheets context
  """

  import Ecto.Query, warn: false
  require Logger

  alias Ecto.Multi

  alias Glific.{
    Flows.Action,
    Flows.FlowContext,
    Flows.MessageVarParser,
    Messages,
    Notifications,
    Repo,
    Sheets.GoogleSheets,
    Sheets.Sheet,
    Sheets.SheetData,
    Sheets.Worker
  }

  # zero width unicode characters
  @invisible_unicode_range ~r/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{206F}\x{FEFF}]/u
  @doc """
  Creates a sheet

  ## Examples

      iex> create_sheet(%{field: value})
      {:ok, %Sheet{}}

      iex> create_sheet(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_sheet(map()) :: {:ok, Sheet.t()} | {:error, any()}
  def create_sheet(attrs) do
    with {:ok, true} <- validate_sheet(attrs),
         {:ok, sheet} <-
           %Sheet{}
           |> Sheet.changeset(attrs)
           |> Repo.insert() do
      sync_sheet_data(sheet)
    end
  end

  @spec validate_sheet(map()) :: {:ok, true} | {:error, String.t()}
  defp validate_sheet(%{url: url, type: type} = attrs)
       when not is_nil(url) and type in ["WRITE", "ALL"] do
    case GoogleSheets.fetch_credentials(attrs.organization_id) do
      {:ok, _credentials} ->
        check_edit_access(attrs)

      {:error, "Google API is not active"} ->
        {:error, "Please add the credentials for google sheet from the settings menu"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_sheet(%{type: "READ", url: url} = attrs) when not is_nil(url) do
    case GoogleSheets.fetch_credentials(attrs.organization_id) do
      {:ok, _} ->
        spreadsheet_id = extract_spreadsheet_id(url)
        check_read_access(attrs.organization_id, spreadsheet_id)

      {:error, "Google API is not active"} ->
        check_public_access(url)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_sheet(_), do: {:error, "Invalid sheet URL"}

  @spec check_edit_access(map()) :: {:ok, true} | {:error, String.t()}
  defp check_edit_access(attrs) do
    spreadsheet_id = extract_spreadsheet_id(attrs.url)

    GoogleSheets.insert_row(attrs.organization_id, spreadsheet_id, %{
      range: "A1",
      data: [[]]
    })
    |> case do
      {:ok, _} ->
        {:ok, true}

      {:error, %Tesla.Env{status: 403}} ->
        {:error,
         "No edit access to the Google Sheet. Please ensure the service account has editor permissions."}

      {:error, %Tesla.Env{status: 404}} ->
        {:error,
         "Google Sheet not found. Please ensure the URL is correct and the service account has access."}

      {:error, reason} ->
        {:error, "Failed to verify edit access: #{inspect(reason)}"}
    end
  end

  @spec check_read_access(non_neg_integer(), String.t()) :: {:ok, true} | {:error, String.t()}
  defp check_read_access(org_id, spreadsheet_id) do
    case GoogleSheets.get_headers(org_id, spreadsheet_id) do
      {:ok, _headers} ->
        {:ok, true}

      {:error, %Tesla.Env{status: 403}} ->
        {:error,
         "No read access to the Google Sheet. Please ensure the service account has viewer permissions."}

      {:error, %Tesla.Env{status: 404}} ->
        {:error,
         "Google Sheet not found. Please ensure the URL is correct and the service account has access."}

      {:error, reason} ->
        {:error, "Failed to verify read access: #{inspect(reason)}"}
    end
  end

  @spec check_public_access(String.t()) :: {:ok, true} | {:error, String.t()}
  defp check_public_access(url) do
    client = Tesla.client([{Tesla.Middleware.FollowRedirects, max_redirects: 5}])

    header_url =
      try do
        build_export_url(url) <> "&range=A1:ZZ1"
      rescue
        MatchError -> url
      end

    case Tesla.get(client, header_url) do
      {:ok, %Tesla.Env{status: status}} when status in 200..399 ->
        {:ok, true}

      _ ->
        {:error,
         "Please double-check the URL and make sure the sharing access for the sheet is at least set to 'Anyone with the link' can view."}
    end
  end

  @doc """
  Updates a sheet.

  ## Examples

      iex> update_sheet(sheet, %{field: new_value})
      {:ok, %Sheet{}}

      iex> update_sheet(sheet, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_sheet(Sheet.t(), map()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def update_sheet(%Sheet{} = sheet, attrs) do
    validated_result =
      if Map.has_key?(attrs, :url) do
        validate_sheet(attrs)
      else
        {:ok, true}
      end

    with {:ok, true} <- validated_result,
         {:ok, sheet} <-
           sheet
           |> Sheet.changeset(attrs)
           |> Repo.update() do
      # incase we update the url. Let's resync the sheet data.
      if Map.has_key?(attrs, :url), do: sync_sheet_data(sheet), else: {:ok, sheet}
    end
  end

  @doc """
  Deletes a sheet.

  ## Examples

      iex> delete_sheet(sheet)
      {:ok, %Sheet{}}

      iex> delete_sheet(sheet)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_sheet(Sheet.t()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def delete_sheet(%Sheet{} = sheet), do: Repo.delete(sheet)

  @doc """
  Gets a single sheet.

  Raises `Ecto.NoResultsError` if the Sheet does not exist.

  ## Examples

      iex> get_sheet!(123)
      %Sheet{}

      iex> get_sheet!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_sheet!(integer) :: Sheet.t()
  def get_sheet!(id), do: Repo.get!(Sheet, id)

  @doc """
  Returns the list of sheets.

  ## Examples

      iex> list_sheets()
      [%Sheet{}, ...]

  """
  @spec list_sheets(map()) :: [Sheet.t()]
  def list_sheets(args),
    do: Repo.list_filter(args, Sheet, &Repo.opts_with_label/2, &filter_with/2)

  @doc """
  Return the count of sheets, using the same filter as list_sheets
  """
  @spec count_sheets(map()) :: integer
  def count_sheets(args),
    do: Repo.count_filter(args, Sheet, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:is_active, is_active}, query ->
        from(q in query, where: q.is_active == ^is_active)

      {:type, type}, query ->
        from(q in query, where: ilike(q.type, ^"%#{type}%"))

      _, query ->
        query
    end)
  end

  @doc """
  Sync a sheet
  """
  @spec sync_sheet_data(Sheet.t()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def sync_sheet_data(%{type: "WRITE"} = sheet), do: {:ok, sheet}

  def sync_sheet_data(sheet) do
    Glific.Metrics.increment("Sheets Read")

    last_synced_at = DateTime.truncate(DateTime.utc_now(), :second)
    export_url = build_export_url(sheet.url)

    sync_result =
      with {:ok, rows} <- GoogleSheets.read_sheet_data(sheet.organization_id, export_url),
           {:ok, decoded_rows} <- decode_all_csv_rows(rows),
           {:ok, sync_result} <- run_sync_transaction(sheet, last_synced_at, decoded_rows) do
        sync_result
      else
        {:error, reason} ->
          handle_sync_failure(sheet, inspect(reason))
      end

    sync_status = report_sync_result(sync_result.sync_successful?, sheet)
    sheet_data_count = count_sheet_data(sheet.id)

    sheet
    |> update_sheet(%{
      last_synced_at: last_synced_at,
      sheet_data_count: sheet_data_count,
      sync_status: sync_status,
      failure_reason: sync_result.error_message
    })
    |> case do
      {:ok, updated_sheet} ->
        # Enqueue background job for media validation if sync was successful
        if sync_result.sync_successful? do
          Worker.make_media_validation_job(updated_sheet)
        end

        {:ok, updated_sheet}

      error ->
        error
    end
  end

  @doc """
  Extracts the spreadsheet ID from a Google Sheets URL.
  """
  @spec extract_spreadsheet_id(String.t()) :: String.t()
  def extract_spreadsheet_id(sheet_url) do
    sheet_url
    |> String.replace("https://docs.google.com/spreadsheets/d/", "")
    |> String.split("/")
    |> List.first()
  end

  @spec build_export_url(String.t()) :: String.t()
  defp build_export_url(sheet_url) do
    # https://developers.google.com/sheets/api/guides/concepts#spreadsheet_id
    [base_url, _gid] = String.split(sheet_url, ["edit", "view", "comment"])
    {:ok, uri} = URI.new(sheet_url)

    gid = uri.fragment || ""
    export_url = base_url <> "export?format=csv&" <> gid
    String.trim_trailing(export_url, "&")
  end

  @spec report_sync_result(boolean(), Sheet.t()) :: :success | :failed
  defp report_sync_result(true, _sheet) do
    Glific.Metrics.increment("Google Sheets Sync Success")
    :success
  end

  defp report_sync_result(false, sheet) do
    create_sync_fail_notification(sheet)
    Glific.Metrics.increment("Google Sheets Sync Failed")
    :failed
  end

  @spec count_sheet_data(integer()) :: integer()
  defp count_sheet_data(sheet_id) do
    SheetData
    |> where([sd], sd.sheet_id == ^sheet_id)
    |> Repo.aggregate(:count)
  end

  @spec decode_all_csv_rows(list({:ok, map()} | {:error, term()})) ::
          {:ok, [map()]} | {:error, String.t()}
  defp decode_all_csv_rows(csv_content_list) do
    result =
      Enum.reduce_while(csv_content_list, {:ok, []}, fn
        {:ok, row}, {:ok, acc} ->
          {:cont, {:ok, [row | acc]}}

        {:error, err}, _ ->
          err_string = inspect(err)

          # This is because we currently don't parse Tesla sheet download errors and instead let the code flow into
          # CSV.decode() which causes errors because then the contet is html which is not csv compatible.
          # This is a temporary fix to handle the errors gracefully. We need to parse the Tesla sheet download errors and pass them to CSV.decode
          # so that we can handle the errors gracefully.
          sanitized_message =
            if String.contains?(err_string, "Escape sequence started on line") or
                 String.contains?(err_string, "Stray escape character on line") do
              "Sheet is not accessible or not found."
            else
              err_string
            end

          {:halt, {:error, sanitized_message}}
      end)

    case result do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _} = err -> err
    end
  end

  @spec run_sync_transaction(Sheet.t(), DateTime.t(), [map()]) :: map()
  defp run_sync_transaction(sheet, last_synced_at, decoded_rows) do
    delete_query = from(sd in SheetData, where: sd.sheet_id == ^sheet.id)

    Multi.new()
    |> Multi.delete_all(:delete_sheet_data, delete_query)
    |> Multi.run(:validate_headers, fn _, _ -> validate_headers(decoded_rows) end)
    |> Multi.run(:process_sheet_data, fn _, _ ->
      process_sheet_data(decoded_rows, sheet, last_synced_at)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        %{sync_successful?: true, error_message: nil}

      {:error, :delete_sheet_data, reason, _changes} ->
        %{sync_successful?: false, error_message: error_reason_to_string(reason)}

      {:error, :validate_headers, message, _} when is_binary(message) ->
        %{sync_successful?: false, error_message: message}

      {:error, :process_sheet_data, message, _} when is_binary(message) ->
        %{sync_successful?: false, error_message: message}

      {:error, _, other, _} ->
        %{sync_successful?: false, error_message: error_reason_to_string(other)}
    end
  end

  @spec error_reason_to_string(term()) :: String.t()
  defp error_reason_to_string(msg) when is_binary(msg), do: msg
  defp error_reason_to_string(%Ecto.Changeset{} = cs), do: generate_error_message(cs)
  defp error_reason_to_string(other), do: inspect(other)

  @spec validate_headers([map()]) :: {:ok, true} | {:error, String.t()}
  defp validate_headers([]), do: {:error, "Unknown error or empty content"}

  defp validate_headers([first_row | _]) do
    if Enum.all?(Map.values(first_row), &(!is_list(&1))) do
      {:ok, true}
    else
      {:error, "Repeated or missing headers"}
    end
  end

  @spec process_sheet_data([map()], Sheet.t(), DateTime.t()) ::
          {:ok, nil} | {:error, String.t()}
  defp process_sheet_data(decoded_rows, sheet, last_synced_at) do
    chunk_size = Application.get_env(:glific, :sheets_chunk_size)

    decoded_rows
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce_while({:ok, nil}, fn chunk, _ ->
      with {:ok, rows_to_insert} <- build_chunk_rows(chunk, sheet, last_synced_at),
           {:ok, _} <- insert_sheet_data_rows(rows_to_insert) do
        {:cont, {:ok, nil}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @spec build_chunk_rows([map()], Sheet.t(), DateTime.t()) ::
          {:ok, list(map())} | {:error, String.t()}
  defp build_chunk_rows(chunk, sheet, last_synced_at) do
    chunk
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      row_values = clean_row_keys_and_values(row)

      case prepare_sheet_data_attrs(row_values, sheet, last_synced_at) do
        {:error, changeset} ->
          {:halt, {:error, generate_error_message(changeset)}}

        valid_attrs ->
          {:cont, {:ok, [valid_attrs | acc]}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _} = error -> error
    end
  end

  @spec insert_sheet_data_rows(list(map())) :: {:ok, integer()} | {:error, String.t()}
  defp insert_sheet_data_rows([]), do: {:ok, 0}

  defp insert_sheet_data_rows(rows_to_insert) do
    case Repo.insert_all(SheetData, rows_to_insert, on_conflict: :nothing) do
      {count, _} when count == length(rows_to_insert) ->
        {:ok, count}

      {count, _} ->
        {:error,
         "Failed to insert all rows likely due to duplicate keys: expected #{length(rows_to_insert)}, got #{count}"}
    end
  end

  @spec log_sync_failure(Sheet.t(), String.t()) :: :ok
  defp log_sync_failure(sheet, reason) do
    Logger.error(
      "Sheet sync failed. \n Reason: #{reason}, org id: #{sheet.organization_id}, sheet_id: #{sheet.id}"
    )

    :ok
  end

  @spec prepare_sheet_data_attrs(map(), Sheet.t(), DateTime.t()) ::
          map() | {:error, Ecto.Changeset.t()}
  defp prepare_sheet_data_attrs(values, sheet, last_synced_at) do
    SheetData.prepare_insert_all_attrs(%{
      key: values["key"],
      row_data: values,
      sheet_id: sheet.id,
      organization_id: sheet.organization_id,
      last_synced_at: last_synced_at
    })
  end

  @spec clean_row_keys_and_values(map()) :: map()
  defp clean_row_keys_and_values(row) do
    Enum.reduce(row, %{}, fn {key, value}, acc ->
      clean_key =
        key
        |> String.downcase()
        |> String.replace(" ", "_")
        |> trim_value()

      Map.put(acc, clean_key, trim_value(value))
    end)
  end

  @doc """
  Creates a sheet

  ## Examples

      iex> create_sheet_data(%{field: value})
      {:ok, %Sheet{}}

      iex> create_sheet_data(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_sheet_data(map()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def create_sheet_data(attrs) do
    %SheetData{}
    |> SheetData.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a sheet data

  ## Examples

      iex> update_sheet_data(sheet_data, %{field: new_value})
      {:ok, %SheetData{}}

      iex> update_sheet_data(sheet_data, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_sheet_data(SheetData.t(), map()) ::
          {:ok, SheetData.t()} | {:error, Ecto.Changeset.t()}
  def update_sheet_data(%SheetData{} = sheet_data, attrs) do
    sheet_data
    |> SheetData.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Execute a sheet action
  """
  @spec execute(Action.t() | any(), FlowContext.t()) :: {FlowContext.t(), Messages.Message.t()}
  def execute(%{action_type: "WRITE"} = action, context) do
    spreadsheet_id = extract_spreadsheet_id(action.url)

    fields = FlowContext.get_vars_to_parse(context)

    row_data =
      action.row_data
      |> Enum.map(&MessageVarParser.parse(&1, fields))

    GoogleSheets.insert_row(context.organization_id, spreadsheet_id, %{
      range: action.range,
      data: [row_data]
    })
    |> case do
      {:ok, _response} ->
        {context, Messages.create_temp_message(context.organization_id, "Success")}

      {:error, error} ->
        Notifications.create_notification(%{
          category: "Flow",
          message: format_notification_message(spreadsheet_id, error),
          severity: Notifications.types().warning,
          organization_id: context.organization_id,
          entity: %{
            contact_id: context.contact_id,
            flow_id: context.flow_id,
            flow_uuid: context.flow.uuid,
            name: context.flow.name
          }
        })

        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def execute(action, context) do
    with {:ok, loaded_sheet} <-
           Repo.fetch_by(SheetData, %{
             sheet_id: action.sheet_id,
             key: FlowContext.parse_context_string(context, action.row),
             organization_id: context.organization_id
           }),
         context <-
           FlowContext.update_results(context, %{action.result_name => loaded_sheet.row_data}) do
      {context, Messages.create_temp_message(context.organization_id, "Success")}
    else
      _ ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  @doc """
  Sync all the sheets of the organization
  """
  @spec sync_organization_sheets(integer(), boolean()) :: :ok
  def sync_organization_sheets(organization_id, is_active \\ true) do
    Sheet
    |> where([sh], sh.organization_id == ^organization_id)
    |> where([sh], sh.auto_sync == true)
    |> where([sh], sh.is_active == ^is_active)
    |> where([sh], sh.type in ["ALL", "READ"])
    |> Repo.all()
    |> Enum.each(fn sheet ->
      # catching the error and logging since we don't know what error is happening here..
      try do
        sync_sheet_data(sheet)
      rescue
        err ->
          Logger.error(
            "Error while syncing google sheet, org id: #{sheet.organization_id}, sheet_id: #{sheet.id} due to #{inspect(err)}"
          )

          create_sync_fail_notification(sheet)
      end
    end)
  end

  @spec create_sync_fail_notification(Sheet.t()) :: :ok
  defp create_sync_fail_notification(sheet) do
    Notifications.create_notification(%{
      category: "Google sheets",
      message: "Google sheet sync failed",
      severity: Notifications.types().warning,
      organization_id: sheet.organization_id,
      entity: %{url: sheet.url, id: sheet.id, name: sheet.label}
    })

    :ok
  end

  @spec trim_value(any()) :: any()
  defp trim_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(@invisible_unicode_range, "")
  end

  defp trim_value(value), do: value

  @spec format_notification_message(String.t(), any()) :: String.t()
  defp format_notification_message(_, %Tesla.Env{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} -> message
      _ -> body
    end
  end

  defp format_notification_message(spreadsheet_id, %Tesla.Env{status: status} = env) do
    cond do
      status in 400..499 ->
        "Invalid request, please check the spreadsheet id"

      status in 500..599 ->
        "Failed to write to the spreadsheet, please retry after some time"

      true ->
        Logger.error(
          "Error while inserting row to the spreadsheet, spreadsheet id: #{spreadsheet_id}, error: #{inspect(env)}"
        )

        "Unknown error occurred, please reach out to support"
    end
  end

  defp format_notification_message(spreadsheet_id, error) do
    Logger.error(
      "Error while inserting row to the spreadsheet, spreadsheet id: #{spreadsheet_id}, error: #{inspect(error)}"
    )

    "Unknown error occurred, please reach out to support"
  end

  @spec generate_error_message(Ecto.Changeset.t()) :: String.t()
  defp generate_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
    |> Enum.map_join(", ", &format_field_error(&1, changeset))
  end

  @spec format_error({String.t(), Keyword.t()}) :: String.t()
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  @spec format_field_error({atom(), list(String.t())}, Ecto.Changeset.t()) :: String.t()
  defp format_field_error({field, message}, changeset) do
    field_name = field |> Atom.to_string() |> String.capitalize()

    case Map.get(changeset.changes, field) do
      nil -> "#{field_name}: #{message}"
      value -> "#{field_name}: #{message} (Value: #{value})"
    end
  end
end
