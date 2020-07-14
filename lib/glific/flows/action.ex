defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowType

  alias Glific.Flows.{
    ContactAction,
    ContactSetting,
    Flow,
    FlowContext,
    Node
  }

  @required_fields [:type, :node_uuid]
  @optional_fields [:text, :value, :name, :quick_replies, :flow_uuid]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          value: String.t() | nil,
          type: FlowType,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow: Flow.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string
    field :text, :string
    field :value, :string
    field :language, :string
    field :type, FlowType
    field :quick_replies, {:array, :string}, default: []

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    field :enter_flow_uuid, Ecto.UUID
    embeds_one :enter_flow, Flow
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
      name: json["name"],
      text: json["text"],
      value: json["value"],
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
  @spec execute(Action.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(%{type: type} = action, context, message_stream) when type == "send_msg" do
    ContactAction.send_message(context, action.text)
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "set_contact_language" do
    IO.puts("Setting contact preference: #{action.value}")
    context = ContactSetting.set_contact_language(context, action.text)
    {:ok, context, message_stream}
  end

  def execute(%{type: type, name: name} = _action, context, message_stream)
      when type == "set_run_result" and name == "settings_optout" do
    context = ContactAction.optout(context)
    {:ok, context, message_stream}
  end

  def execute(%{type: type, name: name} = action, context, message_stream)
      when type == "set_run_result" and name == "settings_preference" do
    IO.puts("Setting contact preference: #{action.value}")
    context = ContactSetting.set_contact_preference(context, action.value)
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "enter_flow" do
    # we create a new context and set the parent id to the exisiting context
    # and start that flow
    Flow.start_sub_flow(context, action.enter_flow_uuid)

    {:ok, context, message_stream}
  end

  def execute(action, _context, _message_stream),
    do: {:error, "Unsupported action type #{action.type}"}
end
