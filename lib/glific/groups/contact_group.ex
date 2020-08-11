defmodule Glific.Groups.ContactGroup do
  @moduledoc """
  A pipe for managing the contact groups
  """

  alias Glific.{
    Contacts.Contact,
    Groups.ContactGroup,
    Groups.Group
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:contact_id, :group_id]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "contacts_groups" do
    belongs_to :contact, Contact
    belongs_to :group, Group
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ContactGroup.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :group_id])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:group_id)
  end
end
