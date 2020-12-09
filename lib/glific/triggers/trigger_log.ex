defmodule Glific.Triggers.TriggerLog do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo,
    Triggers.Trigger
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          status: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          trigger_id: non_neg_integer | nil,
          trigger: Trigger.t() | Ecto.Association.NotLoaded.t() | nil,
          fire_at: :utc_datetime | nil,
          started_at: :utc_datetime | nil,
          completed_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :status,
    :organization_id,
    :trigger_id,
    :fire_at
  ]
  @optional_fields [
    :started_at,
    :completed_at
  ]

  schema "trigger_logs" do
    field :name, :string
    field :event_type, :string, default: "scheduled"

    belongs_to :trigger, Trigger

    field :fire_at, :utc_datetime
    field :started_at, :utc_datetime, default: nil
    field :completed_at, :utc_datetime, default: nil

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TriggerLog.t(), map()) :: Ecto.Changeset.t()
  def changeset(trigger_log, attrs) do
    trigger_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:trigger_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc false
  @spec create_trigger_log(map()) :: {:ok, TriggerLog.t()} | {:error, Ecto.Changeset.t()}
  def create_trigger_log(attrs \\ %{}) do
    %TriggerLog{}
    |> TriggerLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc false
  @spec update_trigger_log(TriggerLog.t(), map()) ::
          {:ok, TriggerLog.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger_log(trigger_log, attrs) do
    trigger_log
    |> TriggerLog.changeset(attrs)
    |> Repo.update()
  end
end
