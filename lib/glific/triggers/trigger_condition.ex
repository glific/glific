defmodule Glific.Triggers.TriggerCondition do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          start_at: :utc_datetime | nil,
          fire_at: :utc_datetime | nil,
          ends_at: :utc_datetime | nil,
          is_active: boolean(),
          is_repeating: boolean(),
          frequency: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :name,
    :start_at,
    :ends_at
  ]
  @optional_fields [
    :fire_at,
    :is_active,
    :is_repeating,
    :frequency
  ]

  schema "trigger_conditions" do
    field :name, :string

    field :start_at, :utc_datetime
    field :fire_at, :utc_datetime
    field :ends_at, :utc_datetime

    field :frequency, :string, default: "today"

    field :is_active, :boolean, default: true
    field :is_repeating, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TriggerCondition.t(), map()) :: Ecto.Changeset.t()
  def changeset(trigger_condition, attrs) do
    trigger_condition
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:organization_id)
  end
end
