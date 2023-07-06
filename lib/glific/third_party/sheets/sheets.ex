defmodule Glific.Sheets do
  @moduledoc """
  The Sheets context
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Flows.Action,
    Flows.FlowContext,
    Flows.MessageVarParser,
    Messages,
    Repo,
    Sheets.ApiClient,
    Sheets.GoogleSheets,
    Sheets.Sheet,
    Sheets.SheetData
  }

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
  defp validate_sheet(%{type: "WRITE"} = attrs) do
    GoogleSheets.fetch_credentials(attrs.organization_id)
    |> case do
      {:ok, _credentials} ->
        {:ok, true}

      {:error, _error} ->
        {:error, "Please add the credentials for google sheet from the settings menu"}
    end
  end

  defp validate_sheet(attrs) do
    Tesla.get(attrs.url)
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
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
    with {:ok, sheet} <-
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

    [sheet_url, gid] = String.split(sheet.url, ["edit", "view", "comment"])

    last_synced_at = DateTime.utc_now()
    export_url = sheet_url <> "export?format=csv&&" <> String.replace(gid, "#", "")

    SheetData
    |> where([sd], sd.sheet_id == ^sheet.id)
    |> Repo.delete_all()

    media_warnings =
      ApiClient.get_csv_content(url: export_url)
      |> Enum.reduce(%{}, fn {_, row}, acc ->
        parsed_rows = parse_row_values(row)

        %{
          ## we can also think in case we need first column.
          key: row["Key"],
          row_data: parsed_rows.values,
          sheet_id: sheet.id,
          organization_id: sheet.organization_id,
          last_synced_at: last_synced_at
        }
        |> create_sheet_data()

        Map.merge(acc, parsed_rows.errors)
      end)

    remove_stale_sheet_data(sheet, last_synced_at)

    sheet_data_count =
      SheetData
      |> where([sd], sd.sheet_id == ^sheet.id)
      |> Repo.aggregate(:count)

    ## we can move this to top of the function also. We can change that later.
    update_sheet(sheet, %{last_synced_at: last_synced_at, sheet_data_count: sheet_data_count})
    |> append_warnings(media_warnings)
  end

  defp append_warnings({:error, _error} = sheet, _media_warnings), do: sheet

  defp append_warnings({:ok, updated_sheet} = _sheet, media_warnings) do
    updated_sheet
    |> Map.put(:warnings, media_warnings)
    |> then(&{:ok, &1})
  end

  @spec parse_row_values(map()) :: map()
  defp parse_row_values(row) do
    clean_row_values =
      Enum.reduce(row, %{}, fn {key, value}, acc ->
        key = key |> String.downcase() |> String.replace(" ", "_")
        Map.put(acc, key, value)
      end)

    errors =
      clean_row_values
      |> Enum.reduce(%{}, fn {_key, value}, acc ->
        {media_type, _media} = Messages.get_media_type_from_url(value, log_error: false)

        with true <- media_type != :text,
             %{is_valid: is_valid, message: message} <-
               Glific.Messages.validate_media(value, Atom.to_string(media_type)),
             false <- is_valid do
          Map.put(acc, value, message)
        else
          _ -> acc
        end
      end)

    %{values: clean_row_values, errors: errors}
  end

  ## We are removing all the rows which are not refreshed in the last sync.
  ## We are assuming that these rows have been deleted from the sheet also.
  @spec remove_stale_sheet_data(Sheet.t(), DateTime.t()) :: {integer(), nil | [term()]}
  defp remove_stale_sheet_data(sheet, last_synced_at) do
    Repo.delete_all(
      from(sd in SheetData,
        where:
          sd.organization_id == ^sheet.organization_id and sd.sheet_id == ^sheet.id and
            sd.last_synced_at != ^last_synced_at
      )
    )
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
    spreadsheet_id =
      action.url
      |> String.replace("https://docs.google.com/spreadsheets/d/", "")
      |> String.split("/")
      |> List.first()

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

      {:error, _response} ->
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
  def sync_organization_sheets(organization_id, is_active \\ true) do
    Sheet
    |> where([sh], sh.organization_id == ^organization_id)
    |> where([sh], sh.is_active == ^is_active)
    |> where([sh], sh.type in ["ALL", "READ"])
    |> Repo.all()
    |> Enum.each(fn sheet ->
      sync_sheet_data(sheet)
    end)
  end
end
