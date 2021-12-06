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
    FlowContext,
    Localization
  }

  alias Pow.Ecto.Schema.Changeset

  @required_fields [:uuid, :type, :arguments, :category_uuid]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | nil,
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

    c = update_parsed_arguments(c, json["arguments"])

    {c, Map.put(uuid_map, c.uuid, {:case, c})}
  end

  # Update the parsed_arguments field of the case
  @spec update_parsed_arguments(Case.t(), [String.t()]) :: Case.t()
  defp update_parsed_arguments(%{type: type} = flow_case, arguments)
       when type in ["has_multiple", "has_any_word", "has_all_words"] do
    parsed_arguments =
      arguments
      |> hd()
      |> Glific.make_set()

    Map.put(flow_case, :parsed_arguments, parsed_arguments)
  end

  defp update_parsed_arguments(flow_case, _arguments), do: flow_case

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

  defp translated_arguments(context, flow_case) do
    Localization.get_translated_case_arguments(context, flow_case)
  end

  @text_types [:text, :quick_reply, :list]

  @text_fns [
    "has_number_eq",
    "has_number_between",
    "has_number",
    "has_any_word",
    "has_phrase",
    "has_only_phrase",
    "has_only_text",
    "has_all_words",
    "has_multiple",
    "has_phone",
    "has_email",
    "has_pattern",
    "has_beginning",
    "has_intent",
    "has_top_intent"
  ]

  @doc """
  Execute a case, given a message.
  This is the only execute function which has a different signature, since
  it just consumes one message at a time and executes it against a predefined function
  It also returns a boolean, rather than a tuple
  """
  @spec execute(Case.t(), FlowContext.t(), Message.t()) :: boolean
  def execute(flow_case, context, msg) do
    translated_arguments = translated_arguments(context, flow_case)

    Map.put(flow_case, :arguments, translated_arguments)
    |> update_parsed_arguments(translated_arguments)
    |> do_execute(context, msg)
  end

  @spec do_execute(Case.t(), FlowContext.t(), Message.t()) :: boolean
  defp do_execute(%{type: "has_number_eq"} = c, _context, %{type: type} = msg)
       when type in @text_types,
       do: strip(c.arguments) == strip(msg)

  defp do_execute(%{type: "has_number_between"} = c, _context, %{type: type} = msg)
       when type in @text_types do
    [low, high] = c.arguments

    # convert all 3 parameters to number
    [low, high, body] = Enum.map([low, high, msg.body], &Glific.parse_maybe_integer/1)

    # ensure no errors
    if Enum.all?([low, high, body], &(&1 != :error)) do
      [low, high, body] = Enum.map([low, high, body], &elem(&1, 1))
      body >= low && body <= high
    else
      false
    end
  end

  defp do_execute(%{type: "has_number"}, _context, %{type: type} = msg)
       when type in @text_types,
       do: String.contains?(msg.clean_body, Enum.to_list(0..9) |> Enum.map(&Integer.to_string/1))

  defp do_execute(%{type: "has_any_word"} = c, _context, %{type: type} = msg)
       when type in @text_types do
    str = msg |> strip() |> Glific.make_set([",", ";", " "])
    !MapSet.disjoint?(str, c.parsed_arguments)
  end

  defp do_execute(%{type: "has_phrase"} = c, _context, %{type: type} = msg)
       when type in @text_types,
       do: String.contains?(strip(c.arguments), strip(msg))

  defp do_execute(%{type: ctype} = c, _context, %{type: type} = msg)
       when ctype in ["has_only_phrase", "has_only_text"] and type in @text_types,
       do: strip(c.arguments) == strip(msg)

  defp do_execute(%{type: "has_all_words"} = c, _context, %{type: type} = msg)
       when type in @text_types do
    str = msg |> strip() |> Glific.make_set([",", ";", " "])

    c.parsed_arguments |> MapSet.subset?(str)
  end

  defp do_execute(%{type: "has_multiple"} = c, _context, %{type: type} = msg)
       when type in @text_types,
       do:
         msg.body
         |> Glific.make_set()
         |> MapSet.subset?(c.parsed_arguments)

  defp do_execute(%{type: "has_phone"} = _c, _context, %{type: type} = msg)
       when type in @text_types do
    phone = strip(msg)

    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, phone_number} -> ExPhoneNumber.is_valid_number?(phone_number)
      _ -> false
    end
  end

  defp do_execute(%{type: "has_email"} = _c, _context, %{type: type} = msg)
       when type in @text_types do
    email = strip(msg)

    case Changeset.validate_email(email) do
      :ok -> true
      _ -> false
    end
  end

  defp do_execute(%{type: "has_pattern"} = c, _context, %{type: type} = msg)
       when type in @text_types,
       do:
         c.arguments
         |> strip()
         |> Regex.compile!()
         |> Regex.match?(strip(msg))

  defp do_execute(%{type: "has_beginning"} = c, _context, %{type: type} = msg)
       when type in @text_types,
       do:
         c.arguments
         |> strip()
         |> String.starts_with?(strip(msg))

  defp do_execute(%{type: ctype} = c, _context, %{type: type} = msg)
       when type in @text_types and
              ctype in ["has_intent", "has_top_intent"] do
    [intent, confidence] = c.arguments
    # always prepend a 0 to the string, in case it is something like ".9",
    # this also works with "0.9"
    confidence = String.to_float("0" <> confidence)

    if intent == "all",
      # any intent is fine, we are only interested in the confidence level
      do: msg.extra.confidence >= confidence,
      else: msg.extra.intent == intent && msg.extra.confidence >= confidence
  end

  # for all the above functions, if we encounter in a non-text context, return false
  defp do_execute(%{type: ctype}, _context, %{type: type})
       when ctype in @text_fns and type not in @text_types,
       do: false

  defp do_execute(%{type: "has_group"} = c, _context, msg) do
    [_group_id, group_label] = c.arguments
    group_label in msg.extra.contact_groups
  end

  defp do_execute(%{type: "has_category"}, _context, _msg), do: true

  defp do_execute(%{type: "has_location"}, _context, msg),
    do: msg.type == :location

  defp do_execute(%{type: "has_media"}, _context, msg),
    do: Flows.is_media_type?(msg.type)

  defp do_execute(%{type: "has_audio"}, _context, msg),
    do: msg.type == :audio

  defp do_execute(%{type: "has_video"}, _context, msg),
    do: msg.type == :video

  defp do_execute(%{type: "has_image"}, _context, msg),
    do: msg.type == :image

  defp do_execute(%{type: "has_file"}, _context, msg),
    do: msg.type == :document

  defp do_execute(c, _context, msg),
    do:
      raise(UndefinedFunctionError,
        message:
          "Function not implemented for cases of case type: #{c.type}, message type: #{msg.type}"
      )
end
