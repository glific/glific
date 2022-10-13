defmodule Glific.Sheets.SheetData do
  @moduledoc """
  The minimal wrapper for the base Sheet structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo,
    Sheets.Sheet
  }

  @required_fields [
    :key,
    :row_data,
    :sheet_id,
    :organization_id,
    :last_synced_at
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          key: String.t() | nil,
          row_data: map() | nil,
          last_synced_at: :utc_datetime | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          sheet_id: non_neg_integer | nil,
          sheet: Sheet.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "sheets_data" do
    field(:key, :string)
    field(:row_data, :map, default: %{})
    field(:last_synced_at, :utc_datetime)

    belongs_to(:sheet, Sheet)
    belongs_to(:organization, Organization)

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
    |> changeset(attrs)
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
  Returns an `%Ecto.Changeset{}` for tracking sheet_data changes.
  """
  @spec change_sheet_data(SheetData.t(), map()) :: Ecto.Changeset.t()
  def change_sheet_data(%SheetData{} = sheet_data, attrs \\ %{}), do: changeset(sheet_data, attrs)
end
