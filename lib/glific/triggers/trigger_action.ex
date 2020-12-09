defmodule Glific.Triggers.TriggerAction do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Groups.Group,
    Partners.Organization,
    Repo
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          action_type: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          group_id: non_neg_integer | nil,
          group: Group.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :name,
    :organization_id
  ]
  @optional_fields [
    :action_type,
    :flow_id,
    :group_id
  ]

  schema "trigger_actions" do
    field :name, :string
    field :action_type, :string, default: "start_flow"

    belongs_to :flow, Flow
    belongs_to :group, Group

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TriggerAction.t(), map()) :: Ecto.Changeset.t()
  def changeset(trigger_action, attrs) do
    trigger_action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc false
  @spec create_trigger_action(map()) :: {:ok, TriggerAction.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger_action(attrs \\ %{}) do
    %TriggerAction{}
    |> TriggerAction.changeset(attrs)
    |> Repo.insert()
  end
end
