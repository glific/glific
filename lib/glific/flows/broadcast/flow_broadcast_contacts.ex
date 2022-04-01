defmodule Glific.Flows.FlowBroadcastContact do
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
    Flows.FlowBroadcast,
    Partners.Organization
  }

  @required_fields [:flow_broadcast_id, :contact_id, :organization_id]
  @optional_fields [:status, :processed_at]

  # we store one more than the number of messages specified here

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          flow_broadcast_id: non_neg_integer | nil,
          flow_broadcast: FlowBroadcast.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          status: :string | nil,
          processed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_broadcast_contacts" do
    field :processed_at, :utc_datetime, default: nil
    field :status, :string, default: nil

    belongs_to :flow_broadcast, FlowBroadcast
    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowBroadcastContact.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_broadcast_contact, attrs) do
    flow_broadcast_contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:contact_id, :flow_broadcast_id])
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
  end
end
