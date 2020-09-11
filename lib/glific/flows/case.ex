defmodule Glific.Flows.Case do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Enums.FlowCase,
    Flows
  }

  alias Glific.Flows.{
    Category,
    FlowContext
  }

  @required_fields [:uuid, :type, :arguments, :category_uuid]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          type: FlowCase | nil,
          arguments: [String.t()],
          category_uuid: Ecto.UUID.t() | nil,
          category: Category.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string

    field :type, FlowCase
    field :arguments, {:array, :string}, default: []

    field :category_uuid, Ecto.UUID
    embeds_one :category, Category
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), any) :: {Case.t(), map()}
  def process(json, uuid_map, _object \\ nil) do
    Flows.check_required_fields(json, @required_fields)

    # Check that the category_uuid exists, if not raise an error
    if !Map.has_key?(uuid_map, json["category_uuid"]),
      do: raise(ArgumentError, message: "Category ID does not exist for Case: #{json["uuid"]}")

    c = %Case{
      uuid: json["uuid"],
      category_uuid: json["category_uuid"],
      type: json["type"],
      arguments: json["arguments"]
    }

    {c, Map.put(uuid_map, c.uuid, {:case, c})}
  end

  defp strip(msgs) when is_list(msgs),
    do: msgs |> hd() |> strip()

  defp strip(msg) when is_binary(msg),
    do: msg |> String.trim() |> String.downcase()

  @doc """
  Execute a case, given a message.
  This is the only execute function which has a different signature, since
  it just consumes one message at a time and executes it against a predefined function
  It also returns a boolean, rather than a tuple
  """
  @spec execute(Case.t(), FlowContext.t(), String.t()) :: boolean
  def execute(%{type: type} = c, _context, msg) when type == "has_any_word",
    do: Enum.member?(c.arguments, strip(msg))

  def execute(%{type: type} = c, _context, msg) when type == "has_number_eq",
    do: strip(c.arguments) == strip(msg)

  def execute(%{type: type} = c, _context, msg) when type == "has_number_between" do
    [low, high] = c.arguments

    # convert all 3 parameters to number
    [low, high, msg] = Enum.map([low, high, msg], &Glific.parse_maybe_integer/1)

    # ensure no errors
    if Enum.all?([low, high, msg], &(&1 != :error)) do
      [low, high, msg] = Enum.map([low, high, msg], &elem(&1, 1))
      msg >= low && msg <= high
    else
      false
    end
  end

  def execute(%{type: type}, _context, msg) when type == "has_number",
    do: String.contains?(msg, Enum.to_list(0..9) |> Enum.map(&Integer.to_string/1))

  def execute(%{type: type} = c, _context, msg) when type == "has_phrase",
    do: String.contains?(strip(msg), strip(c.arguments))

  def execute(%{type: type} = c, _context, msg)
      when type == "has_only_phrase" or type == "has_only_text",
      do: strip(c.arguments) == strip(msg)

  def execute(c, _context, _msg),
    do:
      raise(UndefinedFunctionError,
        message: "Function not implemented for cases of type #{c.type}"
      )
end
