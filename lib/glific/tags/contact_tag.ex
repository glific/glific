defmodule Glific.Tags.ContactTag do
  @moduledoc """
  A pipe for managing the contact tags
  """

  alias __MODULE__
  alias Glific.{Contacts.Contact, Tags.Tag}
  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:contact_id, :tag_id]
  @optional_fields [:value]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          value: String.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          tag: Tag.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "contacts_tags" do
    field :value, :string, default: nil

    belongs_to :contact, Contact
    belongs_to :tag, Tag
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ContactTag.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :tag_id])
  end
end
