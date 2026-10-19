defmodule Glific.Contacts.ContactIdentity do
  @moduledoc """
  A contact's identity on a channel. A contact is the person; it can have several identities (a
  WhatsApp phone, a username issued by its NGO, later a Telegram chat id).

  A web identifier (an NGO username) may contain letters, digits, `_`, `@` and `.`, and is
  case-insensitive: it is stored lowercase, so `Ravi_Web` and `ravi_web` are the same identity. A
  WhatsApp identifier is the contact's phone, kept as stored. Identifiers are unique within an
  organization and channel.

  The identity also holds the contact's consent and session state on its channel: opt-in and
  opt-out, and for WhatsApp the BSP status and the time of the last inbound message.

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
  @optional_fields []
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
