defmodule Glific.Flows.Case do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Enums.FlowCase,
    Flows,
    Messages.Message
  }

  alias Glific.Flows.{
    Category,
    FlowContext
  }

  alias Pow.Ecto.Schema.Changeset

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
    field :parsed_arguments, :map

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
      # type: (if json["type"] == "has_any_word", do: "has_multiple", else: json["type"]),
      type: json["type"],
      arguments: json["arguments"]
    }

    c =
      if c.type == "has_multiple" do
        pargs =
          json["arguments"]
          |> hd()
          |> Glific.make_set()

        Map.put(c, :parsed_arguments, pargs)
      else
        c
      end

    {c, Map.put(uuid_map, c.uuid, {:case, c})}
  end

  @doc """
  Validate a case
  """
  @spec validate(Case.t(), Keyword.t(), map()) :: Keyword.t()
  def validate(_case, errors, _flow) do
    errors
  end

  defp strip(msgs) when is_list(msgs),
    do: msgs |> hd() |> strip()

  defp strip(%{body: body} = _msg),
    do: strip(body)

  defp strip(msg) when is_binary(msg),
    do: msg |> String.trim() |> String.downcase()

  defp strip(_msg), do: ""

  @doc """
  Execute a case, given a message.
  This is the only execute function which has a different signature, since
  it just consumes one message at a time and executes it against a predefined function
  It also returns a boolean, rather than a tuple
  """
  @spec execute(Case.t(), FlowContext.t(), Message.t()) :: boolean
  def execute(%{type: "has_number_eq"} = c, _context, msg),
    do: strip(c.arguments) == strip(msg)

  def execute(%{type: type} = c, _context, msg) when type == "has_number_between" do
    [low, high] = c.arguments

    # convert all 3 parameters to number
    [low, high, body] = Enum.map([low, high, msg.clean_body], &Glific.parse_maybe_integer/1)

    # ensure no errors
    if Enum.all?([low, high, body], &(&1 != :error)) do
      [low, high, body] = Enum.map([low, high, body], &elem(&1, 1))
      body >= low && body <= high
    else
      false
    end
  end

  def execute(%{type: "has_number"}, _context, msg),
    do: String.contains?(msg.clean_body, Enum.to_list(0..9) |> Enum.map(&Integer.to_string/1))

  def execute(%{type: type} = c, _context, msg) when type in ["has_phrase", "has_any_word"],
    do: String.contains?(strip(c.arguments), strip(msg))

  def execute(%{type: type} = c, _context, msg) when type in ["has_only_phrase", "has_only_text"],
    do: strip(c.arguments) == strip(msg)

  def execute(%{type: "has_all_words"} = c, _context, msg) do
    str = strip(msg)
    Enum.all?(c.arguments, fn l -> String.contains?(str, l) end)
  end

  def execute(%{type: "has_multiple"} = c, _context, msg),
    do:
      msg.body
      |> Glific.make_set()
      |> MapSet.subset?(c.parsed_arguments)

  def execute(%{type: "has_location"}, _context, msg),
    do: msg.type == :location

  def execute(%{type: "has_media"}, _context, msg),
    do: msg.type in [:audio, :video, :image]

  def execute(%{type: "has_audio"}, _context, msg),
    do: msg.type == :audio

  def execute(%{type: "has_video"}, _context, msg),
    do: msg.type == :video

  def execute(%{type: "has_image"}, _context, msg),
    do: msg.type == :image

  def execute(%{type: "has_file"}, _context, msg),
    do: msg.type == :document

  def execute(%{type: "has_phone"} = _c, _context, msg) do
    phone = strip(msg)

    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, phone_number} -> ExPhoneNumber.is_valid_number?(phone_number)
      _ -> false
    end
  end

  def execute(%{type: "has_email"} = _c, _context, msg) do
    email = strip(msg)

    case Changeset.validate_email(email) do
      :ok -> true
      _ -> false
    end
  end

  def execute(c, _context, _msg),
    do:
      raise(UndefinedFunctionError,
        message: "Function not implemented for cases of type #{c.type}"
      )
end
