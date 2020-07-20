defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Enums.FlowActionType,
    Flows
  }

  alias Glific.Flows.{
    ContactAction,
    ContactField,
    ContactSetting,
    Flow,
    FlowContext,
    Node,
    Templating
  }

  @required_fields_enter_flow [:uuid, :type, :flow]
  @required_fields_language [:uuid, :type, :language]
  @required_fields_set_contact [:uuid, :type, :value, :field]
  @required_fields [:uuid, :type, :text]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          value: String.t() | nil,
          type: FlowActionType,
          field: map() | nil,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow: Flow.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          templating: Templating.t() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string
    field :text, :string
    field :value, :string
    field :field, :map
    field :language, :string
    field :type, FlowActionType
    field :quick_replies, {:array, :string}, default: []

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    embeds_one :templating, Templating

    field :enter_flow_uuid, Ecto.UUID
    embeds_one :enter_flow, Flow
  end

  @spec process(map(), map(), Node.t(), map()) :: {Action.t(), map()}
  defp process(json, uuid_map, node, attrs) do
    action =
      Map.merge(
        %Action{
          uuid: json["uuid"],
          node_uuid: node.uuid,
          type: json["type"]
        },
        attrs
      )

    {action, Map.put(uuid_map, action.uuid, {:action, action})}
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Action.t(), map()}
  def process(%{"type" => type} = json, uuid_map, node) when type == "enter_flow" do
    Flows.check_required_fields(json, @required_fields_enter_flow)
    process(json, uuid_map, node, %{enter_flow_uuid: json["flow"]["uuid"]})
  end

  def process(%{"type" => type} = json, uuid_map, node) when type == "set_contact_language" do
    Flows.check_required_fields(json, @required_fields_language)
    process(json, uuid_map, node, %{text: json["language"]})
  end

  def process(%{"type" => type} = json, uuid_map, node) when type == "set_contact_field" do
    Flows.check_required_fields(json, @required_fields_set_contact)

    process(json, uuid_map, node, %{
      value: json["value"],
      field: %{
        name: json["field"]["name"],
        key: json["field"]["key"]
      }
    })
  end

  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    attrs = %{
      name: json["name"],
      text: json["text"],
      quick_replies: json["quick_replies"]
    }

    {templating, uuid_map} = Templating.process(json["templating"], uuid_map)
    attrs = Map.put(attrs, :templating, templating)

    process(json, uuid_map, node, attrs)
  end

  @doc """
  Execute a action, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Action.t(), FlowContext.t(), [String.t()]) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def execute(%{type: type} = action, context, message_stream) when type == "send_msg" do
    IO.puts("Sending session message: #{action.text}")
    ContactAction.send_message(context, action)
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "set_contact_language" do
    IO.puts("Setting contact language: #{action.value}")
    context = ContactSetting.set_contact_language(context, action.text)
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "set_contact_name" do
    IO.puts("Setting contact name: #{action.value}")
    context = ContactSetting.set_contact_name(context, action.value)
    {:ok, context, message_stream}
  end

  def execute(%{type: type} = action, context, message_stream)
      when type == "set_contact_field" do
    name = action.field.key
    value = FlowContext.get_result_value(context, action.value)

    context =
      if name == "settings",
        do: ContactSetting.set_contact_preference(context, value),
        else: ContactField.add_contact_field(context, name, value, "string")

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
    IO.puts("entering a new sub flow: #{action.enter_flow_uuid}")
    Flow.start_sub_flow(context, action.enter_flow_uuid)

    {:ok, context, message_stream}
  end

  def execute(action, _context, _message_stream),
    # IO.inspect(action, label: "ACTION");
    do: {:error, "Unsupported action type #{action.type}"}
end
