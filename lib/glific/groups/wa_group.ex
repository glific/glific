defmodule Glific.Groups.WAGroup do
  @moduledoc """
  The minimal wrapper for the base Group structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Groups.WAGroup,
    Partners.Organization,
    WAGroup.WAManagedPhone,
    Contacts.Contact
  }

  @required_fields [:label, :wa_managed_phone_id, :organization_id, :bsp_id]
  @optional_fields [:last_communication_at]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          bsp_id: String.t() | nil,
          wa_managed_phone_id: non_neg_integer | nil,
          wa_managed_phone: WAManagedPhone.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          last_communication_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "wa_groups" do
    field :label, :string
    field :bsp_id, :string

    belongs_to :wa_managed_phone, WAManagedPhone
    belongs_to :organization, Organization

    many_to_many :contacts, Contact, join_through: "contacts_wa_groups", on_replace: :delete

    field :last_communication_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WAGroup.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_group, attrs) do
    wa_group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :wa_managed_phone_id, :organization_id])
  end
end
