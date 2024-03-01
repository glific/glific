defmodule Glific.Groups.ContactWAGroup do
  @moduledoc """
  A pipe for managing the contact whatsapp groups
  """

  alias Glific.{
    Contacts.Contact,
    Groups.ContactWAGroup,
    Groups.WAGroup,
    Partners.Organization
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:contact_id, :wa_group_id]
  @optional_fields [:is_admin, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_group: WAGroup.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          is_admin: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts_wa_groups" do
    field :is_admin, :boolean, default: false

    belongs_to :contact, Contact
    belongs_to :wa_group, WAGroup
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ContactWAGroup.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :wa_group_id])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:wa_group_id)
  end
end
