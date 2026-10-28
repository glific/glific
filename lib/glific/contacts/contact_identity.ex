defmodule Glific.Contacts.ContactIdentity do
  @moduledoc """
  A contact's identity on a channel. A contact is the person; it can have several identities (a
  WhatsApp phone, a username issued by its NGO, later a Telegram chat id). Identities only:
  per-channel state lives elsewhere.

  A web identifier (an NGO username) may contain letters, digits, `_`, `@` and `.`, and is
  case-insensitive: it is stored lowercase, so `Ravi_Web` and `ravi_web` are the same identity. A
  WhatsApp identifier is the contact's phone, kept as stored. Identifiers are unique within an
  organization and channel.

  A WhatsApp identity also holds a copy of the contact's consent and session state (opt-in, opt-out,
  BSP status, last inbound message). `contacts` is still the source of truth: `Glific.Contacts`
  keeps the copy in step on every write, and nothing reads it yet.

  The identity's organization must be its contact's; nothing checks this, so identities are only
  written by code that takes the organization from the contact.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.ContactProviderStatus,
    Enums.MessageChannel,
    Partners.Organization
  }

  @required_fields [:contact_id, :organization_id, :channel, :identifier]
  @consent_and_session_fields [
    :optin_time,
    :optin_status,
    :optin_method,
    :optout_time,
    :optout_method,
    :bsp_status,
    :last_message_at
  ]
  @optional_fields @consent_and_session_fields
  @identifier_format ~r/^[a-z0-9_@.]+$/

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          channel: MessageChannel.t() | nil,
          identifier: String.t() | nil,
          optin_time: DateTime.t() | nil,
          optin_status: boolean(),
          optin_method: String.t() | nil,
          optout_time: DateTime.t() | nil,
          optout_method: String.t() | nil,
          bsp_status: ContactProviderStatus.t(),
          last_message_at: DateTime.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "contact_identities" do
    field :channel, MessageChannel
    field :identifier, :string

    field :optin_time, :utc_datetime
    field :optin_status, :boolean, default: false
    field :optin_method, :string
    field :optout_time, :utc_datetime
    field :optout_method, :string
    field :bsp_status, ContactProviderStatus, default: :none
    field :last_message_at, :utc_datetime

    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The consent and session columns an identity shares with a contact.
  """
  @spec consent_and_session_fields() :: [atom()]
  def consent_and_session_fields, do: @consent_and_session_fields

  @doc """
  Standard changeset pattern we use for all data types.
  """
  @spec changeset(ContactIdentity.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact_identity, attrs) do
    contact_identity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:identifier, min: 1, max: 255)
    |> validate_username()
    |> unique_constraint(:identifier,
      name: :contact_identities_organization_id_channel_identifier_index
    )
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end

  @spec validate_username(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_username(changeset) do
    if get_field(changeset, :channel) == :web do
      changeset
      |> update_change(:identifier, &String.downcase/1)
      |> validate_format(:identifier, @identifier_format,
        message: "can only contain letters, numbers, underscores, @ and dots"
      )
    else
      changeset
    end
  end
end
