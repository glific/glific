defmodule Glific.Triggers.Trigger do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo,
    Triggers.TriggerAction,
    Triggers.TriggerCondition
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          event_type: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          trigger_action_id: non_neg_integer | nil,
          trigger_action: TriggerAction.t() | Ecto.Association.NotLoaded.t() | nil,
          trigger_condition_id: non_neg_integer | nil,
          trigger_condition: TriggerCondition.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :name,
    :organization_id,
    :trigger_action_id,
    :trigger_condition_id
  ]
  @optional_fields [
    :event_type
  ]

  schema "triggers" do
    field :name, :string
    field :event_type, :string, default: "scheduled"

    belongs_to :trigger_action, TriggerAction
    belongs_to :trigger_condition, TriggerCondition

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Trigger.t(), map()) :: Ecto.Changeset.t()
  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:trigger_action_id)
    |> foreign_key_constraint(:trigger_condition_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:name, :organization_id])
  end

  @doc false
  @spec create_trigger(map()) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger(attrs) do
    # here first we need to create trigger action and trigger condition

    {:ok, trigger_action} = TriggerAction.create_trigger_action(attrs)
    {:ok, trigger_condition} = TriggerCondition.create_trigger_condition(attrs)

    attrs =
      attrs
      |> Map.merge(%{
        trigger_action_id: trigger_action.id,
        trigger_condition_id: trigger_condition.id
      })

    %Trigger{}
    |> Trigger.changeset(attrs)
    |> Repo.insert()
  end
end
