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
    Tags.Tag,
    Users.User
  }

  @required_fields [
    :phone,
    :language_id,
    :organization_id
  ]
  @optional_fields [
    :name,
    :bsp_status,
    :status,
    :is_org_read,
    :is_org_replied,
    :is_contact_replied,
    :optin_time,
    :optin_status,
    :optin_method,
    :optin_message_id,
    :optout_time,
    :last_message_number,
    :last_message_at,
    :last_communication_at,
    :settings,
    :fields
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          masked_phone: String.t() | nil,
          status: ContactStatus | nil,
          bsp_status: ContactProviderStatus | nil,
          is_org_read: boolean,
          is_org_replied: boolean,
          is_contact_replied: boolean,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          optin_time: :utc_datetime | nil,
          optin_method: String.t() | nil,
          optin_status: boolean() | nil,
          optin_message_id: String.t() | nil,
          optout_time: :utc_datetime | nil,
          last_message_number: integer,
          last_message_at: :utc_datetime | nil,
          last_communication_at: :utc_datetime | nil,
          settings: map() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts" do
    field :name, :string
    field :phone, :string
    field :masked_phone, :string, virtual: true

    field :status, ContactStatus
    field :bsp_status, ContactProviderStatus

    belongs_to :language, Language
    belongs_to :organization, Organization
    has_one :user, User

    field :is_org_read, :boolean, default: true
    field :is_org_replied, :boolean, default: true
    field :is_contact_replied, :boolean, default: true

    field :optin_time, :utc_datetime
    field :optin_status, :boolean, default: false
    field :optin_method, :string
    field :optin_message_id, :string

    field :last_message_number, :integer, default: 0

    field :optout_time, :utc_datetime
    field :last_message_at, :utc_datetime
    field :last_communication_at, :utc_datetime

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

  @doc """
  Populate virtual field of masked phone number
  """
  @spec populate_masked_phone(%Contact{}) :: %Contact{}
  def populate_masked_phone(%Contact{phone: phone} = contact) do
    masked_phone =
      "#{elem(String.split_at(phone, 4), 0)}******#{elem(String.split_at(phone, -2), 1)}"

    %{contact | masked_phone: masked_phone}
  end
end
