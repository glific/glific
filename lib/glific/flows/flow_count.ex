defmodule Glific.Flows.FlowCount do
  @moduledoc """
  The flow count object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Repo
  }

  @required_fields [:uuid, :flow_uuid, :type]
  @optional_fields [:destination_uuid, :recent_messages]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          type: String.t() | nil,
          count: integer() | nil,
          destination_uuid: Ecto.UUID.t() | nil,
          recent_messages: [map()] | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_counts" do
    field :uuid, Ecto.UUID
    belongs_to :flow, Flow, foreign_key: :flow_uuid
    field :type, :string
    field :count, :integer
    field :destination_uuid, Ecto.UUID
    field :recent_messages, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowCount.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_revision, attrs) do
    flow_revision
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Upsert flow count
  """
  @spec upsert_flow_count(map()) :: :error | FlowCount.t()
  def upsert_flow_count(%{flow_uuid: nil} = _attrs), do: :error

  def upsert_flow_count(%{flow_uuid: _flow_uuid} = attrs) do
    Repo.insert!(
      FlowCount.changeset(%FlowCount{}, attrs),
      on_conflict: [inc: [count: 1]],
      conflict_target: [:flow_uuid, :uuid, :type]
    )
    |> update_recent_messages(attrs)
  end

  @spec update_recent_messages(FlowCount.t(), map()) :: :error | FlowCount.t()
  defp update_recent_messages(flow_count, %{recent_message: recent_message}) do
    recent_messages = [recent_message | flow_count.recent_messages]

    flow_count
    |> FlowCount.changeset(%{recent_messages: recent_messages})
    |> Repo.update()
  end

  defp update_recent_messages(flow_count, _), do: flow_count
end
