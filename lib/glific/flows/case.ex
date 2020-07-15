defmodule Glific.Flows.Case do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowCase

  alias Glific.Flows.{
    Category,
    FlowContext,
    Router
  }

  @required_fields [:type, :arguments, :category_uuid, :router_uuid]
  @optional_fields []

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          type: FlowCase | nil,
          arguments: [String.t()],
          category_uuid: Ecto.UUID.t() | nil,
          category: Category.t() | nil,
          router_uuid: Ecto.UUID.t() | nil,
          router: Router.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string

    field :type, FlowCase
    field :arguments, {:array, :string}, default: []

    field :router_uuid, Ecto.UUID
    embeds_one :router, Router

    field :category_uuid, Ecto.UUID
    embeds_one :category, Category
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Case.t(), map()) :: Ecto.Changeset.t()
  def changeset(case, attrs) do
    case
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:router_uuid)
    |> foreign_key_constraint(:category_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Router.t()) :: {Case.t(), map()}
  def process(json, uuid_map, router) do
    c = %Case{
      uuid: json["uuid"],
      router_uuid: router.uuid,
      category_uuid: json["category_uuid"],
      type: json["type"],
      arguments: json["arguments"]
    }

    {c, Map.put(uuid_map, c.uuid, {:case, c})}
  end

  @doc """
  Execute a case, given a message.
  This is the only execute function which has a different signature, since
  it just consumes one message at a time and executes it against a predefined function
  It also returns a boolean, rather than a tuple
  """
  @spec execute(Case.t(), FlowContext.t(), String.t()) :: boolean
  def execute(%{type: type} = c, _context, msg) when type == "has_any_word",
    do: Enum.member?(c.arguments, msg)

  def execute(%{type: type} = c, _context, msg) when type == "has_number_eq",
    do: hd(c.arguments) == msg

  def execute(%{type: type} = c, _context, msg)
      when type == "has_only_phrase" or type == "has_only_text",
      do: hd(c.arguments) == msg

  def execute(c, _context, _msg) do
    IO.puts("Not processing cases of type #{c.type}")
    false
  end
end
