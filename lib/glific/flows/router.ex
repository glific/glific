defmodule Glific.Flows.Router do
  @moduledoc """
  The Router object which encapsulates the router in a given node.
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Flows.{
    Case,
    Category,
    Context,
    Node
  }

  @required_fields [:type, :operand, :default_category_uuid, :node_uuid]
  @optional_fields [:result_name, :wait_type]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | nil,
          wait_type: String.t() | nil,
          default_category_uuid: Ecto.UUID.t() | nil,
          default_category: Category.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "routers" do
    field :uuid, Ecto.UUID
    field :type, :string
    field :operand, :string
    field :result_name, :string
    field :wait_type, :string

    has_many :cases, Case, foreign_key: :router_uuid
    has_many :categories, Category, foreign_key: :router_uuid

    belongs_to :default_category, Category,
      foreign_key: :default_category_uuid,
      references: :uuid,
      primary_key: false

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: false
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Router.t(), map()) :: Ecto.Changeset.t()
  def changeset(router, attrs) do
    router
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_uuid)
    |> foreign_key_constraint(:default_category_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Router.t(), map()}
  def process(json, uuid_map, node) do
    router = %Router{
      # A router does not have a uuid, since it is attached to a node (optionally)
      # uuid: json["uuid"],
      node_uuid: node.uuid,
      type: json["type"],
      operand: json["operand"],
      result_name: json["result_name"],
      wait_type: json["wait"]["type"]
    }

    {categories, uuid_map} =
      Enum.reduce(
        json["categories"],
        {[], uuid_map},
        fn c, acc ->
          {category, uuid_map} = Category.process(c, elem(acc, 1), router)
          {[category | elem(acc, 0)], uuid_map}
        end
      )

    router =
      router
      |> Map.put(:categories, Enum.reverse(categories))
      # we should check that this category does exist and for FK checks etc, before adding to DB
      # we can only assign this after the category is created
      |> Map.put(:default_category_uuid, json["default_category_uuid"])

    {cases, uuid_map} =
      Enum.reduce(
        json["cases"],
        {[], uuid_map},
        fn c, acc ->
          {case, uuid_map} = Case.process(c, elem(acc, 1), router)
          {[case | elem(acc, 0)], uuid_map}
        end
      )

    router = Map.put(router, :cases, Enum.reverse(cases))
    {router, uuid_map}
  end

  @doc """
  Execute a router, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Router.t(), Context.t(), [String.t()]) ::
          {:ok, Context.t(), [String.t()]} | {:error, String.t()}
  def execute(_router, context, message_stream) when message_stream == [],
    do: {:ok, context, []}

  def execute(
        %{type: type, wait_type: wait_type} = router,
        context,
        message_stream
      )
      when type == "switch" and wait_type == "msg" do
    [msg | rest] = message_stream

    # go thru the cases and find the first one that succeeds
    c =
      Enum.find(
        router.cases,
        nil,
        fn c -> Case.execute(c, context, msg) end
      )

    category_uuid =
      if is_nil(c),
        do: router.default_category_uuid,
        else: c.category_uuid

    # find the category object and send it over
    {:ok, {:category, category}} = Map.fetch(context.uuid_map, category_uuid)
    Category.execute(category, context, rest)
  end

  def execute(_router, _context, _message_stream),
    do: {:error, "Unimplemented router type and/or wait type"}
end
