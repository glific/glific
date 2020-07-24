defmodule Glific.Flows.Router do
  @moduledoc """
  The Router object which encapsulates the router in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.Flows

  alias Glific.Flows.{
    Case,
    Category,
    FlowContext,
    Node,
    Wait
  }

  @required_fields [:type, :operand, :default_category_uuid, :cases, :categories]

  @type t() :: %__MODULE__{
          type: String.t() | nil,
          result_name: String.t() | nil,
          default_category_uuid: Ecto.UUID.t() | nil,
          default_category: Category.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          wait: Wait.t() | nil,
          node: Node.t() | nil,
          cases: [Case.t()] | nil,
          categories: [Category.t()] | nil
        }

  schema "routers" do
    field :type, :string
    field :operand, :string
    field :result_name, :string
    field :wait_type, :string

    field :default_category_uuid, Ecto.UUID
    embeds_one :default_category, Category

    embeds_one :wait, Wait

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    embeds_many :cases, Case
    embeds_many :categories, Category
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Router.t(), map()}
  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    router = %Router{
      node_uuid: node.uuid,
      type: json["type"],
      operand: json["operand"],
      result_name: json["result_name"]
    }

    {categories, uuid_map} =
      Flows.build_flow_objects(
        json["categories"],
        uuid_map,
        &Category.process/3
      )

    # Check that the default_category_uuid exists, if not raise an error
    if !Map.has_key?(uuid_map, json["default_category_uuid"]),
      do: raise(ArgumentError, message: "Default Category ID does not exist for Router")

    {cases, uuid_map} =
      Flows.build_flow_objects(
        json["cases"],
        uuid_map,
        &Case.process/3
      )

    {wait, uuid_map} =
      if Map.has_key?(json, "wait"),
        do: Wait.process(json["wait"], uuid_map, router),
        else: {nil, uuid_map}

    {
      router
      |> Map.put(:categories, categories)
      |> Map.put(:default_category_uuid, json["default_category_uuid"])
      |> Map.put(:cases, cases)
      |> Map.put(:wait, wait),
      uuid_map
    }
  end

  @doc """
  Execute a router, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Router.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(nil, context, message_stream),
    do: {:ok, context, message_stream}

  def execute(router, context, []),
    do: Wait.execute(router.wait, context, [])

  def execute(
        %{type: type} = router,
        context,
        message_stream
      )
      when type == "switch" do
    [msg | rest] = message_stream

    category_uuid = find_category(router, context, msg)

    # find the category object and send it over
    {:ok, {:category, category}} = Map.fetch(context.uuid_map, category_uuid)

    context =
      if is_nil(router.result_name),
        # if there is a result name, store it in the context table along with the category name first
        do: context,
        else: FlowContext.update_results(context, router.result_name, msg, category.name)

    Category.execute(category, context, rest)
  end

  def execute(_router, _context, _message_stream),
    do: raise(UndefinedFunctionError, message: "Unimplemented router type and/or wait type")

  @spec find_category(Router.t(), FlowContext.t(), String.t()) :: Ecto.UUID.t()
  defp find_category(router, _context, "No Response" = msg) do
    # Find the category with name == "No Response"
    category = Enum.find(router.categories, fn c -> c.name == msg end)

    if is_nil(category),
      do: raise(MatchError, message: "Did not find a no response category"),
      else: category.uuid
  end

  defp find_category(router, context, msg) do
    # go thru the cases and find the first one that succeeds
    c =
      Enum.find(
        router.cases,
        nil,
        fn c -> Case.execute(c, context, msg) end
      )

    if is_nil(c),
      do: router.default_category_uuid,
      else: c.category_uuid
  end
end
