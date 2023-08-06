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
    :type,
    :fields
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "profiles" do
    field(:name, :string)
    field(:type, :string)
    field(:fields, :map, default: %{})

    belongs_to(:language, Language, foreign_key: :language_id)
    belongs_to(:contact, Contact, foreign_key: :contact_id)
    belongs_to(:organization, Organization, foreign_key: :organization_id)

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
    |> unique_constraint([:name, :type, :contact_id, :organization_id],
      message: "Sorry, a profile with same name and type already exists"
    )
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end
end
