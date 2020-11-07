defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Groups,
    Messages,
    Messages.Message,
    Repo
  }

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

  @min_delay 2

  @required_field_common [:uuid, :type]
  @required_fields_enter_flow [:flow | @required_field_common]
  @required_fields_language [:language | @required_field_common]
  @required_fields_set_contact_field [:value, :field | @required_field_common]
  @required_fields_set_contact_name [:name | @required_field_common]
  @required_fields_webook [:url, :headers, :method, :result_name | @required_field_common]
  @required_fields [:text | @required_field_common]
  @required_fields_label [:labels | @required_field_common]
  @required_fields_group [:groups | @required_field_common]

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
          attachments: list() | nil,
          labels: list() | nil,
          groups: list() | nil,
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

    field :attachments, :map

    field :labels, :map
    field :groups, :map

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

  def process(%{"type" => "set_contact_name"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact_name)
    process(json, uuid_map, node, %{value: json["name"]})
  end

  def process(%{"type" => "set_contact_field"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact_field)

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

  def process(%{"type" => "add_input_labels"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_label)
    process(json, uuid_map, node, %{labels: json["labels"]})
  end

  def process(%{"type" => "add_contact_groups"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_group)
    process(json, uuid_map, node, %{groups: json["groups"]})
  end

  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    attrs = %{
      name: json["name"],
      text: json["text"],
      quick_replies: json["quick_replies"],
      attachments: process_attachments(json["attachments"])
    }

    {templating, uuid_map} = Templating.process(json["templating"], uuid_map)
    attrs = Map.put(attrs, :templating, templating)

    process(json, uuid_map, node, attrs)
  end

  @doc """
  Execute a action, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Action.t(), FlowContext.t(), [Message.t()]) ::
          {:ok, FlowContext.t(), [Message.t()]} | {:error, String.t()}
  def execute(%{type: "send_msg"} = action, context, messages) do
    ContactAction.send_message(context, action, messages)
  end

  def execute(%{type: "set_contact_language"} = action, context, messages) do
    context = ContactSetting.set_contact_language(context, action.text)
    {:ok, context, messages}
  end

  def execute(%{type: "set_contact_name"} = action, context, messages) do
    value = FlowContext.get_result_value(context, action.value)
    context = ContactSetting.set_contact_name(context, value)
    {:ok, context, messages}
  end

  def execute(%{type: "set_contact_field"} = action, context, messages) do
    key = String.downcase(action.field.key)
    value = FlowContext.get_result_value(context, action.value)

    context =
      cond do
        key == "settings" and value == "optout" ->
          ContactAction.optout(context)

        key == "settings" ->
          ContactSetting.set_contact_preference(context, value)

        true ->
          ContactField.add_contact_field(context, key, action.field[:name], value, "string")
      end

    {:ok, context, messages}
  end

  def execute(%{type: "enter_flow"} = action, context, _messages) do
    # we start off a new context here and dont really modify the current context
    # hence ignoring the return value of start_sub_flow
    # for now, we'll just delay by at least min_delay second
    context = %{context | delay: min(context.delay + @min_delay, @min_delay)}
    Flow.start_sub_flow(context, action.enter_flow_uuid)

    # We null the messages here, since we are going into a different flow
    # this clears any potential errors
    {:ok, context, []}
  end

  def execute(%{type: "call_webhook"} = action, context, messages) do
    # first call the webhook
    json = Webhook.execute(action, context)

    if is_nil(json) or is_nil(action.result_name) do
      {:ok, context,
       [
         Messages.create_temp_message(context.contact.organization_id, "Failure")
         | messages
       ]}
    else
      {
        :ok,
        FlowContext.update_results(context, action.result_name, json),
        [
          Messages.create_temp_message(context.contact.organization_id, "Success")
          | messages
        ]
      }
    end
  end

  def execute(%{type: "add_input_labels"} = action, context, messages) do
    ## We will soon figure out how we will manage the UUID with tags
    flow_label =
      action.labels
      |> Enum.map(fn label -> label["name"] end)
      |> Enum.join(", ")

    Repo.get(Message, context.last_message.id)
    |> Message.changeset(%{flow_label: flow_label})
    |> Repo.update()

    {:ok, context, messages}
  end

  def execute(%{type: "add_contact_groups"} = action, context, messages) do
    ## We will soon figure out how we will manage the UUID with tags
    _list =
      Enum.reduce(
        action.groups,
        [],
        fn group, _acc ->
          {:ok, group_id} = Glific.parse_maybe_integer(group["uuid"])
          Groups.create_contact_group(%{contact_id: context.contact_id, group_id: group_id})
          {:ok, group_id}
        end
      )

    {:ok, context, messages}
  end

  def execute(action, _context, _messages),
    do: raise(UndefinedFunctionError, message: "Unsupported action type #{action.type}")

  # let's format attachment and add as a map
  @spec process_attachments(list()) :: map()
  defp process_attachments(nil), do: %{}

  defp process_attachments(attachment_list) do
    attachment_list
    |> Enum.map(fn attchement ->
      case String.split(attchement, ":", parts: 2) do
        [type, url] -> {type, url}
        _ -> {nil, nil}
      end
    end)
    |> Map.new()
  end
end
