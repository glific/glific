defmodule Glific.Contacts.ContactChannel do
  @moduledoc """
  The state of a contact on one channel, one row per `(contact, channel)`. Today that is consent
  to be messaged on the channel; `contacts.optin_*` remains the WhatsApp consent record.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactChannel,
    Enums.MessageChannel,
    Partners.Organization
  }

  @required_fields [:contact_id, :organization_id, :channel]
  @optional_fields [:optin_time, :optin_method, :optout_time, :optout_method]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          channel: MessageChannel.t() | nil,
          optin_time: DateTime.t() | nil,
          optin_method: String.t() | nil,
          optout_time: DateTime.t() | nil,
          optout_method: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contact_channels" do
    field :channel, MessageChannel
    field :optin_time, :utc_datetime
    field :optin_method, :string
    field :optout_time, :utc_datetime
    field :optout_method, :string

    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types.
  """
  @spec changeset(ContactChannel.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact_channel, attrs) do
    contact_channel
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :channel])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end
end
