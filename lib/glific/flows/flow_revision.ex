defmodule Glific.Flows.FlowRevision do
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.Flow

  @required_fields [:definition, :revision_number, :flow_id]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          definition: map() | nil,
          revision_number: integer() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
    }

  schema "flow_revisions" do
    field :definition, :map
    field :revision_number, :integer
    belongs_to :flow, Flow
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def default_definition(flow) do
     %{
       "name" => "Flow9",
       "uuid" => flow.uuid,
       "spec_version" => "13.1.0",
       "language" => "base",
       "type" => "messaging",
       "nodes" => [],
       "_ui" => %{},
       "revision" => 1,
       "expire_after_minutes" => 10080
      }
  end
end
