defmodule Glific.Contacts.ContactChannelOptin do
  @moduledoc """
  A contact's consent to be messaged on one specific channel.

  `contacts.optin_*` keeps its existing meaning — WhatsApp — and is deliberately not migrated
  here: every reader of it (searches, collection counts, reports, stats, the BigQuery contact
  export) means WhatsApp and keeps working untouched. This table holds the web channel and
  whatever comes after it, one row per contact per channel.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactChannelOptin,
    Enums.MessageChannel,
    Partners.Organization
  }

  @required_fields [:contact_id, :channel, :organization_id]
  @optional_fields [:optin_time, :optin_method, :optout_time, :optout_method]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          channel: atom() | nil,
          optin_time: DateTime.t() | nil,
          optin_method: String.t() | nil,
          optout_time: DateTime.t() | nil,
          optout_method: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contact_channel_optins" do
    field(:channel, MessageChannel)
    field(:optin_time, :utc_datetime)
    field(:optin_method, :string)
    field(:optout_time, :utc_datetime)
    field(:optout_method, :string)

    belongs_to(:contact, Contact)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ContactChannelOptin.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact_channel_optin, attrs) do
    contact_channel_optin
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:contact_id, :channel])
  end
end
