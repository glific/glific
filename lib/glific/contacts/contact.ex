defmodule Glific.Contacts.Contact do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Enums.ContactProviderStatus,
    Enums.ContactStatus,
    Groups.Group,
    Partners.Organization,
    Settings.Language,
    Tags.Tag
  }

  @required_fields [
    :phone,
    :language_id,
    :organization_id
  ]
  @optional_fields [
    :name,
    :provider_status,
    :status,
    :optin_time,
    :optout_time,
    :last_message_at,
    :settings,
    :fields
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          status: ContactStatus | nil,
          provider_status: ContactProviderStatus | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          optin_time: :utc_datetime | nil,
          optout_time: :utc_datetime | nil,
          last_message_at: :utc_datetime | nil,
          settings: map() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts" do
    field :name, :string
    field :phone, :string

    field :status, ContactStatus
    field :provider_status, ContactProviderStatus

    belongs_to :language, Language
    belongs_to :organization, Organization

    field :optin_time, :utc_datetime
    field :optout_time, :utc_datetime
    field :last_message_at, :utc_datetime

    field :settings, :map, default: %{}
    field :fields, :map, default: %{}

    many_to_many :tags, Tag, join_through: "contacts_tags", on_replace: :delete

    many_to_many :groups, Group, join_through: "contacts_groups", on_replace: :delete

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
    |> unique_constraint([:phone, :organization_id])
    |> foreign_key_constraint(:language_id)
  end
end
