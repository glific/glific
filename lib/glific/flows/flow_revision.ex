defmodule Glific.Flows.FlowRevision do
  @moduledoc """
  The flow revision object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Repo
  }

  @required_fields [:definition, :flow_id]
  @optional_fields [:revision_number]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          definition: map() | nil,
          revision_number: integer() | nil,
          status: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flow_revisions" do
    field :definition, :map
    field :revision_number, :integer
    field :status, :string
    belongs_to :flow, Flow
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(FlowRevision.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow_revision, attrs) do
    flow_revision
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Default definition when we create a new flow
  """
  @spec default_definition(Flow.t()) :: map()
  def default_definition(flow) do
    %{
      "name" => flow.name,
      "uuid" => flow.uuid,
      "spec_version" => "13.1.0",
      "language" => "base",
      "type" => "messaging",
      "nodes" => [],
      "_ui" => %{},
      "revision" => 1,
      "expire_after_minutes" => 10_080
    }
  end

  @doc false
  @spec create_flow_revision(map()) :: {:ok, FlowRevision.t()} | {:error, Ecto.Changeset.t()}
  def create_flow_revision(attrs \\ %{}) do
    %FlowRevision{}
    |> FlowRevision.changeset(attrs)
    |> Repo.insert()
  end
end
