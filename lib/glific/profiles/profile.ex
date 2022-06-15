defmodule Glific.Profiles.Profile do
  @moduledoc """
    The schema for profile
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Partners.Organization,
    Profiles.Profile,
    Settings.Language
  }

  @required_fields [
    :contact_id,
    :language_id,
    :organization_id
  ]

  @optional_fields [
    :name,
    :profile_type,
    :fields
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          profile_type: String.t() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "profiles" do
    field :name, :string
    field :profile_type, :string
    field :fields, :map, default: %{}

    belongs_to :language, Language
    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for the profile. It takes profile struct and attrs to cast and put validation on it.
  """
  @spec changeset(Profile.t(), map()) :: Ecto.Changeset.t()
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end
end
