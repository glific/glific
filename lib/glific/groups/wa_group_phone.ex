defmodule Glific.Groups.WAGroupPhone do
  @moduledoc """
  Membership row linking a `WAManagedPhone` to a `WAGroup`. Replaces the
  one-to-one `wa_groups.wa_managed_phone_id` column. Exactly one
  membership per group is marked `is_primary` (enforced by a partial
  unique index on the database). `is_active` flips to false when sync
  detects the phone has been removed from the WhatsApp group itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Groups.WAGroup,
    Groups.WAGroupPhone,
    Partners.Organization,
    WAGroup.WAManagedPhone
  }

  @required_fields [:wa_group_id, :wa_managed_phone_id, :organization_id]
  @optional_fields [:is_primary, :is_active]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          wa_group_id: non_neg_integer | nil,
          wa_group: WAGroup.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_managed_phone_id: non_neg_integer | nil,
          wa_managed_phone: WAManagedPhone.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          is_primary: boolean(),
          is_active: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "wa_groups_phones" do
    field :is_primary, :boolean, default: false
    field :is_active, :boolean, default: true

    belongs_to :wa_group, WAGroup
    belongs_to :wa_managed_phone, WAManagedPhone
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types.
  """
  @spec changeset(WAGroupPhone.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_group_phone, attrs) do
    wa_group_phone
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:wa_group_id, :wa_managed_phone_id])
    |> unique_constraint(:is_primary, name: :wa_groups_phones_one_primary)
    |> foreign_key_constraint(:wa_group_id)
    |> foreign_key_constraint(:wa_managed_phone_id)
    |> foreign_key_constraint(:organization_id)
  end
end
