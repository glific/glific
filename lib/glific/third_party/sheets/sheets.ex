defmodule Glific.Sheets do
  @moduledoc """
  The Sheets context
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Repo,
    Sheets.ApiClient,
    Sheets.Sheet
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
    attrs =
      ApiClient.get_csv_content(url: attrs.url)
      |> Enum.reduce(%{}, fn {_, row}, acc ->
        Map.merge(acc, clean_row_values(row))
      end)
      |> then(&Map.merge(attrs, %{data: &1, synced_at: DateTime.utc_now()}))

    %Sheet{}
    |> Sheet.changeset(attrs)
    |> Repo.insert()
  end

  @spec clean_row_values(map()) :: map()
  defp clean_row_values(row) do
    cleaned_row =
      Enum.reduce(row, %{}, fn {key, value}, acc ->
        key = key |> String.downcase() |> String.replace(" ", "_")
        Map.put(acc, key, value)
      end)

    Map.put(%{}, row["Key"], cleaned_row)
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
end
