defmodule Glific.Contacts.ContactsFields do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Partners.Organization
  alias Glific.Enums.{ContactFieldValueType, ContactFieldScope}

  @required_fields [
    :name,
    :shortcode,
    :organization_id
  ]
  @optional_fields [
    :value_type,
    :scope
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          shortcode: String.t() | nil,
          value_type: String.t() | nil,
          scope: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts_fields" do
    field :name, :string
    field :shortcode, :string
    field :value_type, ContactFieldValueType, default: :text
    field :scope, ContactFieldScope, default: :contact

    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Contact.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
    |> unique_constraint([:shortcode, :organization_id])
  end
end
