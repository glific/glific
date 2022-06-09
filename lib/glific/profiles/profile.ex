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
    :profile_registration_fields,
    :contact_profile_fields,
    :active_profile_id
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          profile_type: String.t() | nil,
          profile_registration_fields: map() | nil,
          contact_profile_fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          active_profile_id: non_neg_integer | nil,
        }

  schema "profiles" do
    field :name, :string
    field :profile_type, :string
    field :profile_registration_fields, :map, default: %{}
    field :contact_profile_fields, :map, default: %{}

    belongs_to :language, Language
    belongs_to :contact, Contact
    belongs_to :organization, Organization
    belongs_to :active_profile, Profile, foreign_key: :active_profile_id

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
