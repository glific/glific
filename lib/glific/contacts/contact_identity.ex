defmodule Glific.Contacts.ContactIdentity do
  @moduledoc """
  How a contact logs in on a channel. A contact is the person; it can have one identity per login
  (a WhatsApp phone, a username issued by its NGO, later a Telegram chat id). Login credentials
  only: per-channel state lives elsewhere.

  A web identifier (an NGO username) may contain letters, digits, `_`, `@` and `.`, and is
  case-insensitive: it is stored lowercase, so `Ravi_Web` and `ravi_web` are the same identity. A
  WhatsApp identifier is the contact's phone, kept as stored. Identifiers are unique within an
  organization and channel.

  The identity's organization must be its contact's; nothing checks this, so identities are only
  written by code that takes the organization from the contact.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
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
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "contact_identities" do
    field :channel, MessageChannel
    field :identifier, :string

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
