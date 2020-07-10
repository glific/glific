defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Enums.FlowType

  alias Glific.Flows.{
    ContactSetting,
    Context,
    Flow,
    Node
  }

  @required_fields [:type, :node_uuid]
  @optional_fields [:text, :value, :name, :quick_replies, :flow_uuid]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          value: String.t() | nil,
          type: FlowType,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "actions" do
    field :uuid, Ecto.UUID
    field :name, :string
    field :text, :string
    field :value, :string
    field :language, :string
    field :type, FlowType
    field :quick_replies, {:array, :string}, default: []

    belongs_to :node, Node, foreign_key: :node_uuid, references: :uuid, primary_key: false

    belongs_to :enter_flow, Flow,
      foreign_key: :enter_flow_uuid,
      references: :uuid,
      primary_key: false
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
  @spec execute(Action.t(), Context.t(), [String.t()]) ::
          {:ok, Context.t(), [String.t()]} | {:error, String.t()}
  def execute(%{type: type} = action, context, message_stream) when type == "send_msg" do
    IO.puts("Sending message: #{action.text}, #{action.uuid}")
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "set_contact_language" do
    IO.puts("Setting Contact Language: #{action.text}")
    context = ContactSetting.set_contact_language(context, action.text)
    {:ok, context, message_stream}
  end

  def execute(%{type: type, name: name} = action, context, message_stream)
      when type == "set_run_result" and name == "settings.preference" do
    IO.puts("Setting Contact Setting Preferences: #{action.value}")
    context = ContactSetting.set_contact_preference(context, action.value)
    {:ok, context, message_stream}
  end

  def execute(action, _context, _message_stream),
    do: {:error, "Unsupported action type #{action.type}"}
end
