defmodule Glific.Contacts.ContactIdentity do
  @moduledoc """
  How a contact logs in on a channel. A contact is the person; it can have one identity per login
  (a phone, a username issued by its NGO, later a Telegram chat id). Login credentials only:
  per-channel state lives elsewhere.

  The `identifier` is opaque and matched exactly, so it is neither trimmed nor case-folded. `kind`
  says what it is, and it is unique within an organization, channel and kind, so an NGO username
  that happens to be a phone number never matches someone's phone login.

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

  @required_fields [:contact_id, :organization_id, :channel, :kind, :identifier]
  @optional_fields []
  @kinds ["phone", "ngo_username"]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          channel: MessageChannel.t() | nil,
          kind: String.t() | nil,
          identifier: String.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "contact_identities" do
    field :channel, MessageChannel
    field :kind, :string
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
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:identifier, min: 1, max: 255)
    |> unique_constraint([:organization_id, :channel, :kind, :identifier],
      name: :contact_identities_org_channel_kind_identifier_index
    )
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end
end
