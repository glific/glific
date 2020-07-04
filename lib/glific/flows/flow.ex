defmodule Glific.Flows.Flow do
  @moduledoc """
  The flow object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.{
    Flows.Node,
    Settings.Language
  }

  @required_fields [:name, :language_id]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "flows" do
    field :name, :string

    belongs_to :language, Language

    has_many :nodes, Node
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Flow.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:language_id)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map()) :: {Flow.t(), map()}
  def process(json, uuid_map) do
    flow = %Flow{
      uuid: json["uuid"],
      language: json["language"],
      name: json["name"]
    }

    uuid_map = Map.put(uuid_map, flow.uuid, :flow)

    {nodes, uuid_map} =
      Enum.reduce(
        json["nodes"],
        {[], uuid_map},
        fn node_json, acc ->
          {node, uuid_map} = Node.process(node_json, elem(acc, 1), flow)
          {[node | elem(acc, 0)], uuid_map}
        end
      )

    flow = Map.put(flow, :nodes, nodes)
    {flow, uuid_map}
  end
end
