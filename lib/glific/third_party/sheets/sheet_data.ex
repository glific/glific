defmodule Glific.Sheets.SheetData do
  @moduledoc """
  The minimal wrapper for the base Sheet structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Sheets.ApiClient,
    Sheets.Sheet,
    Repo
  }

  @required_fields [
    :key,
    :data,
    :sheet_id,
    :organization_id
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          key: String.t() | nil,
          data: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          sheet_id: non_neg_integer | nil,
          sheet: Sheet.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "sheets_data" do
    field :key, :string
    field :data, :map, default: %{}

    belongs_to :sheet, Sheet
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(SheetData.t(), map()) :: Ecto.Changeset.t()
  def changeset(sheet_data, attrs) do
    sheet_data
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:key, :sheet_id, :organization_id])
  end

  @doc """
  Parses a sheet
  """
  @spec parse_sheet_data(map(), non_neg_integer()) :: :ok
  def parse_sheet_data(attrs, sheet_id) do
    ApiClient.get_csv_content(url: attrs.url)
    |> Enum.each(fn {_, row} ->
      %{
        key: row["Key"],
        data: clean_row_values(row),
        sheet_id: sheet_id,
        organization_id: attrs.organization_id
      }
      |> upsert_sheet_data()
    end)
  end

  @spec clean_row_values(map()) :: map()
  defp clean_row_values(row) do
    Enum.reduce(row, %{}, fn {key, value}, acc ->
      key = key |> String.downcase() |> String.replace(" ", "_")
      Map.put(acc, key, value)
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
    |> changeset(attrs)
    |> Repo.insert()
  end

  def upsert_sheet_data(attrs) do
    Repo.insert!(
      change_sheet_data(%SheetData{}, attrs),
      returning: true,
      on_conflict: [set: Enum.map(attrs, fn {key, value} -> {key, value} end)],
      conflict_target: [:key, :sheet_id, :organization_id]
    )
  end

  def change_sheet_data(%SheetData{} = sheet_data, attrs \\ %{}), do: changeset(sheet_data, attrs)
end
