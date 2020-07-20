defmodule Glific.Flows.Category do
  @moduledoc """
  The Category object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Flows.Case,
    Flows.Exit,
    Flows.FlowContext
  }

  @required_fields [:name, :uuid, :exit_uuid]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          cases: [Case.t()] | [],
          exit_uuid: Ecto.UUID.t() | nil,
          exit: Exit.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string

    embeds_many :cases, Case

    field :exit_uuid, Ecto.UUID
    embeds_one :exit, Exit
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), any) :: {Category.t(), map()}
  def process(json, uuid_map, _object \\ nil) do
    Flows.check_required_fields(json, @required_fields)

    category = %Category{
      uuid: json["uuid"],
      exit_uuid: json["exit_uuid"],
      name: json["name"]
    }

    {category, Map.put(uuid_map, category.uuid, {:category, category})}
  end

  @doc """
  Execute a category, given a message stream.
  """
  @spec execute(Category.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(category, context, message_stream) do
    # transfer control to the exit node
    {:ok, {:exit, exit}} = Map.fetch(context.uuid_map, category.exit_uuid)
    Exit.execute(exit, context, message_stream)
  end
end
