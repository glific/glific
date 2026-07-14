defmodule Glific.Partners.OrganizationStatusHistory do
  @moduledoc """
  Append-only history of organization (bot) status transitions.

  A new row is recorded for every status change funnelled through
  `Glific.Partners.update_organization/2`, capturing the previous status, the new
  status, and optional reason/metadata. Powers status-timeline and fleet reporting
  (including the BigQuery sync). Identical (no-op) transitions are not recorded.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Enums.OrganizationStatus,
    Partners.Organization
  }

  @required_fields [
    :new_status,
    :changed_at,
    :organization_id
  ]
  @optional_fields [
    :previous_status,
    :reason,
    :metadata
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          previous_status: atom() | nil,
          new_status: atom() | nil,
          reason: String.t() | nil,
          metadata: map() | nil,
          changed_at: DateTime.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "organization_status_histories" do
    field(:previous_status, OrganizationStatus)
    field(:new_status, OrganizationStatus)
    field(:reason, :string)
    field(:metadata, :map, default: %{})
    field(:changed_at, :utc_datetime)

    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(OrganizationStatusHistory.t(), map()) :: Ecto.Changeset.t()
  def changeset(status_history, attrs) do
    status_history
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
