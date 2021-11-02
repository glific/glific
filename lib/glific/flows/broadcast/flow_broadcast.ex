defmodule Glific.Flows.FlowBroadcast do
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
    Flows.Flow,
    Groups.Group,
    Messages.Message,
    Partners.Organization,
    Users.User
  }

  @required_fields [:flow_id, :group_id, :message_id, :started_at, :organization_id]
  @optional_fields [
    :user_id,
    :completed_at
  ]

  # we store one more than the number of messages specified here

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          group_id: non_neg_integer | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          message_id: non_neg_integer | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          started_at: :utc_datetime | nil,
          completed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_broadcasts" do
    field :started_at, :utc_datetime, default: nil
    field :completed_at, :utc_datetime, default: nil

    belongs_to :flow, Flow
    belongs_to :group, Group
    belongs_to :message, Message
    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowBroadcast.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_broadcast, attrs) do
    flow_broadcast
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
  end
end
