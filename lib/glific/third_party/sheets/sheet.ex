defmodule Glific.Sheets.Sheet do
  @moduledoc """
  The minimal wrapper for the base Sheet structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Enums.SheetSyncStatus,
    Partners.Organization
  }

  @required_fields [
    :label,
    :url,
    :organization_id
  ]

  @optional_fields [
    :last_synced_at,
    :is_active,
    :sheet_data_count,
    :type,
    :auto_sync,
    :sync_status,
    :failure_reason
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          url: String.t() | nil,
          type: String.t() | nil,
          is_active: boolean() | nil,
          last_synced_at: :utc_datetime | nil,
          auto_sync: boolean() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          sheet_data_count: non_neg_integer | nil,
          sync_status: String.t() | nil | atom(),
          failure_reason: String.t() | nil,
          updated_at: :utc_datetime | nil
        }

  schema "sheets" do
    field(:label, :string)
    field(:url, :string)
    field(:type, :string, default: "READ")
    field(:is_active, :boolean, default: true)
    field(:last_synced_at, :utc_datetime)
    field(:auto_sync, :boolean, default: false)
    field(:sheet_data_count, :integer)
    field(:sync_status, SheetSyncStatus, default: :success)
    field(:failure_reason, :string)

    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Sheet.t(), map()) :: Ecto.Changeset.t()
  def changeset(sheet, attrs) do
    sheet
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url()
    |> unique_constraint([:url, :organization_id])
  end

  @spec validate_url(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_url(%{changes: changes} = changeset) when not is_nil(changes.url) do
    url = changeset.changes[:url]

    if Glific.URI.cast(url) == :ok &&
         String.contains?(url, "https://docs.google.com/spreadsheets/") do
      changeset
    else
      add_error(
        changeset,
        :url,
        "Sheet URL is invalid"
      )
    end
  end

  defp validate_url(changeset), do: changeset
end
