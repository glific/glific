defmodule Glific.Sheets.SheetData do
  @moduledoc """
  The minimal wrapper for the base Sheet structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
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
  Prepare the attributes for insert_all
  """
  @spec prepare_insert_all_attrs(map()) :: Ecto.Changeset.t()
  def prepare_insert_all_attrs(attrs) do
    changeset =
      %SheetData{
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      |> cast(attrs, @required_fields)
      |> validate_required(@required_fields)

    if changeset.valid? do
      changeset
      |> apply_changes()
      |> Map.from_struct()
      |> Map.take(@required_fields ++ [:inserted_at, :updated_at])
    else
      {:error, changeset}
    end
  end
end
