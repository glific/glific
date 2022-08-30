defmodule Glific.Contacts.ContactHistory do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactHistory,
    Partners.Organization,
    Profiles.Profile
  }

  @required_fields [
    :contact_id,
    :event_type,
    :event_label,
    :event_datetime,
    :organization_id
  ]
  @optional_fields [:event_meta, :profile_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          profile_id: non_neg_integer | nil,
          profile: Profile.t() | Ecto.Association.NotLoaded.t() | nil,
          event_type: String.t() | nil,
          event_label: String.t() | nil,
          event_datetime: :utc_datetime | nil,
          event_meta: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil,
          profile: Profile.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "contact_histories" do
    field(:event_type, :string)
    field(:event_label, :string)
    field(:event_datetime, :utc_datetime)
    field(:event_meta, :map, default: %{})
    belongs_to(:contact, Contact)
    belongs_to(:profile, Profile)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ContactHistory.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact_history, attrs) do
    contact_history
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:profile_id)
  end
end
