defmodule Glific.Triggers.TriggerCondition do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

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
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :name,
    :start_at,
    :ends_at,
    :organiztion_id
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

    belongs_to :organization, Organization

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

  @doc false
  @spec create_trigger_condition(map()) :: {:ok, TriggerCondition.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger_condition(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.merge(%{
        fire_at: attrs.start_at
      })

    %TriggerCondition{}
    |> TriggerCondition.changeset(attrs)
    |> Repo.insert()
  end

  @doc false
  @spec update_trigger_condition(TriggerCondition.t(), map()) ::
          {:ok, TriggerCondition.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger_condition(trigger_condition, attrs) do
    trigger_condition
    |> TriggerCondition.changeset(attrs)
    |> Repo.update()
  end
end
