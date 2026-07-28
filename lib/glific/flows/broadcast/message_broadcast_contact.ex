defmodule Glific.Flows.MessageBroadcastContact do
  @moduledoc """
  When we are running a flow, we are running it in the context of a
  contact and/or a conversation (or other Glific data types). Let encapsulate
  this in a module and isolate the flow from the other aspects of Glific
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Contacts.Contact,
    Flows.MessageBroadcast,
    Partners.Organization
  }

  @required_fields [:message_broadcast_id, :contact_id, :organization_id]
  @optional_fields [:status, :processed_at, :group_ids]

  # we store one more than the number of messages specified here

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          message_broadcast_id: non_neg_integer | nil,
          message_broadcast: MessageBroadcast.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          status: :string | nil,
          processed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          group_ids: list() | nil
        }

  schema "message_broadcast_contacts" do
    field(:processed_at, :utc_datetime, default: nil)
    field(:status, :string, default: nil)
    field :group_ids, {:array, :integer}, default: []

    belongs_to(:message_broadcast, MessageBroadcast)
    belongs_to(:contact, Contact)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(MessageBroadcastContact.t(), map()) :: Ecto.Changeset.t()
  def changeset(message_broadcast_contact, attrs) do
    message_broadcast_contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :message_broadcast_id])
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
  end
end
