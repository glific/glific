defmodule Glific.Contacts.ContactIdentity do
  @moduledoc """
  How a contact logs in on a channel. A contact is the person; it can have one identity per login
  (a phone on web, a username issued by its NGO, later a Telegram chat id).

  The `identifier` is opaque and matched exactly, so it is neither trimmed nor case-folded. It is
  unique within an organization and channel.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactIdentity,
    Enums.MessageChannel,
    Partners.Organization,
    Repo
  }

  @required_fields [:contact_id, :organization_id, :channel, :identifier]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          channel: MessageChannel.t() | nil,
          identifier: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contact_identities" do
    field :channel, MessageChannel
    field :identifier, :string

    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
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
    |> validate_contact_organization()
    |> unique_constraint([:organization_id, :channel, :identifier])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end

  @spec validate_contact_organization(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_contact_organization(%{valid?: true} = changeset) do
    contact_id = get_field(changeset, :contact_id)
    organization_id = get_field(changeset, :organization_id)

    contact_organization_id =
      Contact
      |> where([c], c.id == ^contact_id)
      |> select([c], c.organization_id)
      |> Repo.one(skip_organization_id: true)

    if contact_organization_id in [nil, organization_id],
      do: changeset,
      else: add_error(changeset, :contact_id, "belongs to another organization")
  end

  defp validate_contact_organization(changeset), do: changeset
end
