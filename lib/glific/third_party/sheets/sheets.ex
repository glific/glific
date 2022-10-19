defmodule Glific.Sheets do
  @moduledoc """
  The Sheets context
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Flows.FlowContext,
    Messages,
    Repo,
    Sheets.ApiClient,
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
  @spec create_sheet(map()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def create_sheet(attrs) do
    with {:ok, sheet} <-
           %Sheet{}
           |> Sheet.changeset(attrs)
           |> Repo.insert() do
      sync_sheet_data(sheet)
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
        from q in query, where: q.is_active == ^is_active

      _, query ->
        query
    end)
  end

  @doc """
  Sync a sheet
  """
  @spec sync_sheet_data(Sheet.t()) :: {:ok, Sheet.t()} | {:error, Ecto.Changeset.t()}
  def sync_sheet_data(sheet) do
    last_synced_at = DateTime.utc_now()

    ApiClient.get_csv_content(url: sheet.url)
    |> Enum.each(fn {_, row} ->
      %{
        ## we can also think in case we need fist column.
        key: row["Key"],
        row_data: clean_row_values(row),
        sheet_id: sheet.id,
        organization_id: sheet.organization_id,
        last_synced_at: last_synced_at
      }
      |> upsert_sheet_data()
    end)

    remove_stale_sheet_data(sheet, last_synced_at)

    ## we can move this to top of the function also. We can change that later.
    update_sheet(sheet, %{last_synced_at: last_synced_at})
  end

  @spec clean_row_values(map()) :: map()
  defp clean_row_values(row) do
    Enum.reduce(row, %{}, fn {key, value}, acc ->
      key = key |> String.downcase() |> String.replace(" ", "_")
      Map.put(acc, key, value)
    end)
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
  Updates or Creates a SheetData based on the unique indexes in the table. If there is a match it returns the existing SheetData, else it creates a new one
  """
  @spec upsert_sheet_data(map()) :: {:ok, SheetData.t()}
  def upsert_sheet_data(attrs) do
    case Repo.get_by(SheetData, %{key: attrs.key, organization_id: attrs.organization_id}) do
      nil ->
        create_sheet_data(attrs)

      sheet_data ->
        update_sheet_data(sheet_data, attrs)
    end
  end

  @doc """
  Execute a sheet action
  """
  @spec execute(Action.t(), FlowContext.t()) :: nil
  def execute(action, context) do
    result_name = action.result_name

    params = %{
      sheet_id: action.sheet_id,
      row: action.row,
      result_name: result_name,
      organization_id: context.organization_id
    }

    with loaded_sheet <- load_sheet_data(params) do
      {
        FlowContext.update_results(
          context,
          %{result_name => loaded_sheet}
        ),
        Messages.create_temp_message(context.organization_id, "Success")
      }
    else
      _ ->
        {context, Messages.create_temp_message(context.organization_id, "Failure")}
    end
  end

  def load_sheet_data(attrs) do
    {:ok, sheet_data} =
      Repo.fetch_by(SheetData, %{
        sheet_id: attrs.sheet_id,
        key: attrs.row,
        organization_id: attrs.organization_id
      })

    sheet_data.row_data
  end
end
