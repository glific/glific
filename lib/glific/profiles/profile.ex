defmodule Glific.Profiles.Profile do
  @moduledoc """
    The schema for profile
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Glific.{
    Contacts.Contact,
    Settings.Language,
  }

  @required_fields [
    :contact_id,
    :language_id
  ]

  @optional_fields [
    :name,
    :type,
    :profile_registration_fields,
    :contact_profile_fields
  ]

  @type t() :: %__MODULE__{
    __meta__: Ecto.Schema.Metadata.t(),
    id: non_neg_integer | nil,
    name: String.t() | nil,
    type: String.t() | nil,
    profile_registration_fields: map() | nil,
    contact_profile_fields: map() | nil,
    inserted_at: :utc_datetime_usec | nil,
    updated_at: :utc_datetime_usec | nil
  }

  schema "profiles" do
    field :name, :string
    field :type, :string
    field :profile_registration_fields, :map, default: %{}
    field :contact_profile_fields, :map, default: %{}

    belongs_to :language, Language
    belongs_to :contact, Contact

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(Contact.t(), map()) :: Ecto.Changeset.t()
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
