defmodule Glific.Sheets do
  @moduledoc """
  The Sheets context
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
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
           |> Sheet.changeset(Map.put_new(attrs, :last_synced_at, DateTime.utc_now()))
           |> Repo.insert() do
      parse_sheet_data(attrs, sheet)
      {:ok, sheet}
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
           |> Sheet.changeset(Map.put_new(attrs, :last_synced_at, DateTime.utc_now()))
           |> Repo.update() do
      parse_sheet_data(attrs, sheet)
      {:ok, sheet}
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
  def delete_sheet(%Sheet{} = sheet) do
    Repo.delete(sheet)
  end

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
  Parses a sheet
  """
  @spec parse_sheet_data(map(), Sheet.t()) :: :ok
  def parse_sheet_data(attrs, sheet) do
    ApiClient.get_csv_content(url: attrs.url)
    |> Enum.each(fn {_, row} ->
      %{
        key: row["Key"],
        row_data: clean_row_values(row),
        sheet_id: sheet.id,
        last_synced_at: sheet.last_synced_at,
        organization_id: attrs.organization_id
      }
      |> SheetData.upsert_sheet_data()
    end)

    clean_unsynced_sheet_data(sheet)
    :ok
  end

  @spec clean_row_values(map()) :: map()
  defp clean_row_values(row) do
    Enum.reduce(row, %{}, fn {key, value}, acc ->
      key = key |> String.downcase() |> String.replace(" ", "_")
      Map.put(acc, key, value)
    end)
  end

  @spec clean_unsynced_sheet_data(Sheet.t()) :: {integer(), nil | [term()]}
  defp clean_unsynced_sheet_data(sheet) do
    Repo.delete_all(
      from(sd in SheetData,
        where:
          sd.organization_id == ^sheet.organization_id and sd.sheet_id == ^sheet.id and
            sd.last_synced_at != ^sheet.last_synced_at
      )
    )
  end
end
