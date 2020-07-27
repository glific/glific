defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema

  alias Glific.Flows

  alias Glific.Flows.{
    ContactAction,
    ContactField,
    ContactSetting,
    Flow,
    FlowContext,
    Node,
    Templating,
    Webhook
  }

  @required_field_common [:uuid, :type]
  @required_fields_enter_flow [:flow | @required_field_common]
  @required_fields_language [:language | @required_field_common]
  @required_fields_set_contact [:value, :field | @required_field_common]
  @required_fields_webook [:url, :headers, :method, :result_name | @required_field_common]
  @required_fields [:text | @required_field_common]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          value: String.t() | nil,
          url: String.t() | nil,
          headers: map() | nil,
          method: String.t() | nil,
          result_name: String.t() | nil,
          body: String.t() | nil,
          type: String.t() | nil,
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

    # various fields for webhooks
    field :url, :string
    field :headers, :map
    field :method, :string
    field :result_name, :string
    field :body, :string

    # fields for certain actions: set_contact_field, set_contact_language
    field :field, :map
    field :language, :string

    field :type, :string

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
  def process(%{"type" => "enter_flow"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_enter_flow)
    process(json, uuid_map, node, %{enter_flow_uuid: json["flow"]["uuid"]})
  end

  def process(%{"type" => "set_contact_language"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_language)
    process(json, uuid_map, node, %{text: json["language"]})
  end

  def process(%{"type" => "set_contact_field"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact)

    process(json, uuid_map, node, %{
      value: json["value"],
      field: %{
        name: json["field"]["name"],
        key: json["field"]["key"]
      }
    })
  end

  def process(%{"type" => "call_webhook"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_webook)

    process(json, uuid_map, node, %{
      url: json["url"],
      method: json["method"],
      result_name: json["result_name"],
      body: json["body"],
      headers: json["headers"]
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
  def execute(%{type: "send_msg"} = action, context, message_stream) do
    ContactAction.send_message(context, action)
    {:ok, context, message_stream}
  end

  def execute(%{type: "set_contact_language"} = action, context, message_stream) do
    context = ContactSetting.set_contact_language(context, action.text)
    {:ok, context, message_stream}
  end

  def execute(%{type: "set_contact_name"} = action, context, message_stream) do
    context = ContactSetting.set_contact_name(context, action.value)
    {:ok, context, message_stream}
  end

  def execute(%{type: "set_contact_field"} = action, context, message_stream) do
    name = action.field.key
    value = FlowContext.get_result_value(context, action.value)

    context =
      if name == "settings",
        do: ContactSetting.set_contact_preference(context, value),
        else: ContactField.add_contact_field(context, name, value, "string")

    {:ok, context, message_stream}
  end

  def execute(%{type: "enter_flow"} = action, context, message_stream) do
    Flow.start_sub_flow(context, action.enter_flow_uuid)
    {:ok, context, message_stream}
  end

  def execute(%{type: "call_webhook"} = action, context, message_stream) do
    # first call the webhook
    json = Webhook.get(
      action.url,
      Keyword.new(action.headers, fn {k, v} -> {String.to_existing_atom(k), v} end),
      action.body)

    context =
      if is_nil(json) or is_nil(action.result_name) do
        {:ok, context, ["Failure"]}
      else
        {
          :ok,
          FlowContext.update_results(context, action.result_name, json),
          ["Success"]
        }
      end
  end

  def execute(action, _context, _message_stream),
    do: raise(UndefinedFunctionError, message: "Unsupported action type #{action.type}")
end
