defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Glific.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowType

  alias Glific.Flows.{
    Flow,
    Node
  }

  @required_fields [:type, :node_uuid]
  @optional_fields [:text, :quick_replies, :flow_uuid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          text: String.t() | nil,
          type: FlowType,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "actions" do
    field :text, :string
    field :language, :string
    field :type, FlowType
    field :quick_replies, {:array, :string}, default: []

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: true

    belongs_to :enter_flow, Flow,
      foreign_key: :enter_flow_uuid,
      references: :uuid,
      primary_key: true
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Action.t(), map()) :: Ecto.Changeset.t()
  def changeset(action, attrs) do
    action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:node_uuid)
    |> foreign_key_constraint(:flow_uuid)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Action.t(), map()}
  def process(%{"type" => type} = json, uuid_map, node) when type == "enter_flow" do
    action = %Action{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      type: json["type"],
      enter_flow_uuid: json["flow"]["uuid"]
    }

    {action, Map.put(uuid_map, action.uuid, {:action, action})}
  end

  def process(json, uuid_map, node) do
    action = %Action{
      uuid: json["uuid"],
      node_uuid: node.uuid,
      text: json["text"],
      type: json["type"],
      quick_replies: json["quick_replies"]
    }

    action =
    if action.type == "set_contact_language",
      do: Map.put(action, :text, json["language"]),
    else: action

    {action, Map.put(uuid_map, action.uuid, {:action, action})}
  end

  @doc """
  Execute a action, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Action.t(), map(), [String.t()]) :: any
  def execute(%{type: type} = action, _uuid_map, _message_stream) when type == "send_msg",
    do: IO.puts("Sending message: #{action.text}, #{action.uuid}")

  def execute(%{type: type} = action, _uuid_map, _message_stream) when type == "set_contact_language",
    do: IO.puts("Setting Contact Language: #{action.text}")

  def execute(action, _uuid_map, _message_stream),
    do: IO.inspect(action)
end
