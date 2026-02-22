defmodule Glific.Flows.Action do
  @moduledoc """
  The Action object which encapsulates one action in a given node.
  """

  alias __MODULE__

  use Ecto.Schema
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Dialogflow,
    Flows,
    Flows.Flow,
    Flows.WAGroupAction,
    Groups,
    Groups.Group,
    Messages,
    Messages.Message,
    Profiles,
    Repo,
    Sheets,
    Templates.InteractiveTemplate,
    ThirdParty.Kaapi,
    Tickets
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

  require Logger

  @contact_profile %{
    "Switch Profile" => :switch_profile,
    "Create Profile" => :create_profile,
    "Deactivate Profile" => :deactivate_profile
  }

  @required_field_common [:uuid, :type]
  @required_fields_enter_flow [:flow | @required_field_common]
  @required_fields_language [:language | @required_field_common]
  @required_fields_set_contact_field [:value, :field | @required_field_common]
  @required_fields_set_contact_profile [:value, :profile_type | @required_field_common]
  @required_fields_set_contact_name [:name | @required_field_common]
  @required_fields_webhook [:url, :headers, :method, :result_name | @required_field_common]
  @required_fields_classifier [:input, :result_name | @required_field_common]
  @required_fields [:text | @required_field_common]
  @required_fields_label [:labels | @required_field_common]
  @required_fields_sheet [:sheet_id, :result_name | @required_field_common]
  @required_fields_open_ticket [:body | @required_field_common]
  @required_fields_start_session [
    :contacts,
    :create_contact,
    :flow,
    :groups,
    :exclusions | @required_field_common
  ]
  @required_fields_group [:groups | @required_field_common]
  @required_fields_contact [:contacts, :text | @required_field_common]
  @required_fields_waittime [:delay]
  @required_fields_interactive_template [:name | @required_field_common]
  @required_fields_set_results [:name, :category, :value | @required_field_common]
  @required_fields_set_wa_group_field [:value, :field | @required_field_common]

  # They fall under actions, thus not using "wait for response" with them, as that is a router.
  @wait_for ["wait_for_time", "wait_for_result"]
  @template_type ["send_msg", "send_broadcast"]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          text: String.t() | nil,
          value: String.t() | nil,
          input: String.t() | nil,
          url: String.t() | nil,
          headers: map() | nil,
          method: String.t() | nil,
          result_name: String.t() | nil,
          body: String.t() | nil,
          type: String.t() | nil,
          profile_type: String.t() | nil,
          create_contact: boolean,
          exclusions: boolean,
          is_template: boolean,
          flow: map() | nil,
          field: map() | nil,
          quick_replies: [String.t()],
          enter_flow_uuid: Ecto.UUID.t() | nil,
          enter_flow_name: String.t() | nil,
          enter_flow_expression: String.t() | nil,
          attachments: list() | nil,
          labels: list() | nil,
          groups: list() | nil,
          contacts: list() | nil,
          enter_flow: Flow.t() | nil,
          node_uuid: Ecto.UUID.t() | nil,
          node: Node.t() | nil,
          templating: Templating.t() | nil,
          ## this is a custom delay in minutes for wait for time nodes.
          ## Currently we use this only for the wait for time node.
          wait_time: integer() | nil,

          # Google sheet node specific fields
          row: map() | nil,
          row_data: list() | nil,
          action_type: String.t() | nil,
          range: String.t() | nil,
          sheet_id: integer() | nil,
          assignee: integer() | nil,
          topic: String.t() | nil,

          ## this is a custom delay in seconds before processing for the node.
          ## Currently only used for send messages
          delay: integer() | 0,
          # Interactive messages
          interactive_template_id: integer() | nil,
          interactive_template_expression: String.t() | nil,
          params_count: String.t() | nil,
          params: list() | nil,
          attachment_type: String.t() | nil,
          attachment_url: String.t() | nil,
          category: String.t() | nil
        }

  embedded_schema do
    field(:uuid, Ecto.UUID)
    field(:name, :string)
    field(:text, :string)
    field(:value, :string)
    field(:category, :string)
    field(:input, :string)

    # various fields for webhooks
    field(:url, :string)
    field(:headers, :map)
    field(:method, :string)
    field(:result_name, :string)
    field(:body, :string)

    # fields for certain actions: set_contact_field, set_contact_language
    field(:field, :map)
    field(:language, :string)

    field(:type, :string)
    field(:profile_type, :string)

    field(:create_contact, :boolean, default: false)
    field(:exclusions, :boolean, default: false)
    field(:is_template, :boolean, default: false)
    field(:flow, :map)

    field(:quick_replies, {:array, :string}, default: [])

    field(:attachments, :map)

    field(:labels, :map)
    field(:groups, :map)
    field(:contacts, :map)

    # fields for google sheet action
    field(:row, :map)
    field(:row_data, :map)
    field(:action_type, :string)
    field(:range, :string)
    field(:sheet_id, :integer)
    field(:assignee, :integer)
    field(:topic, :string)

    field(:wait_time, :integer)

    field(:interactive_template_id, :integer)

    field(:node_uuid, Ecto.UUID)
    embeds_one(:node, Node)

    embeds_one(:templating, Templating)

    field(:enter_flow_uuid, Ecto.UUID)
    field(:enter_flow_name, :string)
    field(:enter_flow_expression, :string)

    field(:params, {:array, :string}, default: [])
    field(:params_count, :string)
    field(:interactive_template_expression, :string)
    field(:attachment_type, :string)
    field(:attachment_url, :string)
    field(:delay, :integer, default: 0)

    embeds_one(:enter_flow, Flow)
  end

  @spec do_templating(map(), map(), Node.t(), map()) :: {Action.t(), map()}
  defp do_templating(json, uuid_map, node, attrs) do
    {templating, uuid_map} = Templating.process(json["templating"], uuid_map)
    is_template = json["templating"] != nil && map_size(json["templating"]) > 0

    attrs
    |> Map.put(:templating, templating)
    |> Map.put(:is_template, is_template)
    |> then(&process(json, uuid_map, node, &1))
  end

  @spec process(map(), map(), Node.t(), map()) :: {Action.t(), map()}
  defp process(json, uuid_map, node, attrs) do
    action =
      Map.merge(
        %Action{
          uuid: json["uuid"],
          node_uuid: node.uuid,
          type: json["type"],
          delay: Glific.parse_maybe_integer!(json["delay"] || 0)
        },
        attrs
      )

    {action, Map.put(uuid_map, action.uuid, {:action, action})}
  end

  @doc """
  Process a json structure from flow editor to the Glific data types
  """
  @spec process(map(), map(), Node.t()) :: {Action.t(), map()}
  def process(%{"type" => "link_google_sheet"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_sheet)

    process(json, uuid_map, node, %{
      sheet_id: json["sheet_id"],
      row: json["row"],
      row_data: json["row_data"] || [],
      url: json["url"] || [],
      action_type: json["action_type"] || "READ",
      range: json["range"] || "",
      result_name: json["result_name"]
    })
  end

  def process(%{"type" => "open_ticket"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_open_ticket)

    process(json, uuid_map, node, %{
      topic: json["topic"]["name"],
      body: json["body"],
      assignee: json["assignee"]["uuid"]
    })
  end

  def process(%{"type" => "start_session"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_start_session)

    process(json, uuid_map, node, %{
      contacts: json["contacts"],
      create_contact: json["create_contact"],
      flow: json["flow"],
      groups: json["groups"],
      exclusions: json["exclusions"]["in_a_flow"]
    })
  end

  def process(%{"type" => "enter_flow"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_enter_flow)

    process(json, uuid_map, node, %{
      enter_flow_uuid: json["flow"]["uuid"],
      enter_flow_name: json["flow"]["name"],
      enter_flow_expression: json["flow"]["expression"]
    })
  end

  def process(%{"type" => "set_contact_language"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_language)
    process(json, uuid_map, node, %{text: json["language"]})
  end

  def process(%{"type" => "set_contact_name"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact_name)
    process(json, uuid_map, node, %{value: json["name"]})
  end

  def process(%{"type" => "set_contact_profile"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact_profile)
    process(json, uuid_map, node, %{profile_type: json["profile_type"], value: json["value"]})
  end

  def process(%{"type" => "set_contact_field"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_contact_field)

    name =
      if is_nil(json["field"]["name"]),
        do: json["field"]["key"],
        else: json["field"]["name"]

    process(json, uuid_map, node, %{
      value: json["value"],
      field: %{
        name: name,
        key: json["field"]["key"]
      }
    })
  end

  def process(%{"type" => "set_wa_group_field"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_wa_group_field)

    name =
      if is_nil(json["field"]["name"]),
        do: json["field"]["key"],
        else: json["field"]["name"]

    process(json, uuid_map, node, %{
      value: json["value"],
      field: %{
        name: name,
        key: json["field"]["key"]
      }
    })
  end

  def process(%{"type" => "call_webhook"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_webhook)

    process(json, uuid_map, node, %{
      url: json["url"],
      method: json["method"],
      result_name: json["result_name"],
      body: json["body"],
      headers: json["headers"]
    })
  end

  def process(%{"type" => "call_classifier"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_classifier)

    process(json, uuid_map, node, %{
      input: json["input"],
      result_name: json["result_name"]
    })
  end

  def process(%{"type" => "add_input_labels"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_label)
    process(json, uuid_map, node, %{labels: process_labels(json["labels"])})
  end

  def process(%{"type" => "add_contact_groups"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_group)
    process(json, uuid_map, node, %{groups: json["groups"]})
  end

  def process(%{"type" => "send_broadcast"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_contact)

    attrs = %{
      text: json["text"],
      attachments: process_attachments(json["attachments"]),
      contacts: json["contacts"]
    }

    do_templating(json, uuid_map, node, attrs)
  end

  def process(%{"type" => "send_interactive_msg"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_interactive_template)

    process(json, uuid_map, node, %{
      interactive_template_id: json["id"],
      labels: process_labels(json["labels"]),
      params: json["params"] || [],
      params_count: json["paramsCount"] || "0",
      attachment_url: json["attachment_url"],
      attachment_type: json["attachment_type"],
      interactive_template_expression: json["expression"] || nil
    })
  end

  def process(%{"type" => "remove_contact_groups"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_group)

    if json["all_groups"] do
      process(json, uuid_map, node, %{groups: ["all_groups"]})
    else
      process(json, uuid_map, node, %{groups: json["groups"]})
    end
  end

  def process(%{"type" => "set_run_result"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_set_results)

    process(json, uuid_map, node, %{
      value: json["value"],
      category: json["category"],
      name: json["name"]
    })
  end

  @default_wait_time -1
  def process(%{"type" => type} = json, uuid_map, node)
      when type in @wait_for do
    Flows.check_required_fields(json, @required_fields_waittime)

    # use a default wait time< of 5 minutes
    wait_time =
      if is_nil(json["delay"]) || String.trim(json["delay"]) == "" do
        @default_wait_time
      else
        time = String.to_integer(json["delay"])

        if time <= 0,
          do: @default_wait_time,
          else: time
      end

    process(
      json,
      uuid_map,
      node,
      %{
        wait_time: wait_time,
        # this is potentially set in wait_for_result
        result_name: json["result_name"]
      }
    )
  end

  def process(json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields)

    attrs = %{
      name: json["name"],
      text: json["text"],
      labels: process_labels(json["labels"]),
      quick_replies: json["quick_replies"],
      attachments: process_attachments(json["attachments"])
    }

    do_templating(json, uuid_map, node, attrs)
  end

  @spec get_name(atom()) :: String.t()
  defp get_name(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  @spec check_entity_exists(map(), Keyword.t(), atom()) :: Keyword.t()
  defp check_entity_exists(entity, errors, object) do
    case Repo.fetch_by(object, %{id: entity["uuid"]}) do
      {:ok, _} ->
        errors

      _ ->
        [{object, "Could not find #{get_name(object)}: #{entity["name"]}", "Critical"} | errors]
    end
  end

  @spec object(String.t()) :: atom()
  defp object("send_broadcast"), do: Contact
  defp object("add_contact_groups"), do: Group
  defp object("remove_contact_groups"), do: Group

  @doc """
  Validate a action and all its children
  """
  @spec validate(Action.t(), list(), map()) :: list()
  def validate(%{type: type, groups: groups} = action, errors, _flow)
      when type in ["add_contact_groups", "remove_contact_groups", "send_broadcast"] do
    # ensure that the contacts and/or groups exist that are involved in the above
    # action
    object = object(type)

    Enum.reduce(
      check_object(object, action, groups),
      errors,
      fn entity, errors ->
        case Glific.parse_maybe_integer(entity["uuid"]) do
          {:ok, _entity_id} ->
            # ensure entity_id exists
            check_entity_exists(entity, errors, object)

          _ ->
            [{object, "Could not parse #{get_name(object)}", "Critical"} | errors]
        end
      end
    )
  end

  def validate(%{type: "enter_flow"} = action, errors, _flow) do
    # ensure that the flow exists
    case Repo.fetch_by(Flow, %{uuid: action.enter_flow_uuid}) do
      {:ok, _} -> errors
      _ -> [{Flow, "Could not find Sub Flow: #{action.enter_flow_name}", "Critical"} | errors]
    end
  end

  def validate(%{type: type} = action, errors, flow)
      when type in @wait_for do
    # ensure that any downstream messages from this action are of type HSM
    # if wait time > 24 hours!
    if action.wait_time >= 24 * 60 * 60 &&
         type_of_next_message(flow, action) == :session,
       do: [
         {Message, "The next message after a long wait for time should be a template", "Warning"}
         | errors
       ],
       else: errors
  end

  def validate(%{type: "set_contact_language"} = action, errors, _flow) do
    if is_nil(action.text) || action.text == "",
      do: [{Message, "Language is a required field", "Warning"} | errors],
      else: errors
  end

  def validate(%{type: type, is_template: true} = action, errors, _flow)
      when type in @template_type do
    if action.templating == nil,
      do: [
        {Message, "A template could not be found in the flow", "Critical"}
        | errors
      ],
      else: errors
  end

  def validate(%{type: "send_interactive_msg"} = action, errors, flow) do
    {:node, node} = flow.uuid_map[action.node_uuid]

    if is_nil(action.interactive_template_expression) do
      errors
      |> check_missing_interactive_template(action, flow)
      |> check_the_next_node(node, flow)
    else
      check_the_next_node(errors, node, flow)
    end
  end

  # default validate, do nothing
  def validate(_action, errors, _flow), do: errors

  @spec check_missing_interactive_template(list(), Action.t(), map()) :: list()
  defp check_missing_interactive_template(errors, action, flow) do
    Repo.fetch_by(
      InteractiveTemplate,
      %{id: action.interactive_template_id, organization_id: flow.organization_id}
    )
    |> case do
      {:ok, _} -> errors
      {:error, _} -> [{Message, "An Interactive template does not exist", "Critical"} | errors]
    end
  end

  @spec check_the_next_node(list(), map(), map()) :: list()
  defp check_the_next_node(errors, node, flow) do
    [exit | _] = node.exits

    case exit.destination_node_uuid do
      nil ->
        warning_message(errors, node.uuid)

      _ ->
        {:node, dest_node} = flow.uuid_map[exit.destination_node_uuid]

        if dest_node.router == nil or
             dest_node.router.wait == nil do
          warning_message(errors, node.uuid)
        else
          errors
        end
    end
  end

  @spec warning_message(list(), String.t()) :: list()
  defp warning_message(errors, node_id) do
    node_label = String.slice(node_id, -4..-1)

    [
      {Message, "The next node after interactive Node #{node_label} should be wait for response",
       "Warning"}
      | errors
    ]
  end

  defp check_object(Contact, action, _groups), do: action.contacts

  defp check_object(_object, _action, ["all_groups"]),
    do: Group |> select([m], %{"uuid" => m.id, "name" => m.label}) |> Repo.all()

  defp check_object(_object, action, _groups), do: action.groups

  @spec type_of_next_message(Flow.t(), Action.t()) :: atom()
  defp type_of_next_message(flow, action) do
    # lets keep this simple for now, we'll just go follow the exit of this
    # action to the next node
    {:node, node} = flow.uuid_map[action.node_uuid]
    [exit | _] = node.exits
    {:node, dest_node} = flow.uuid_map[exit.destination_node_uuid]
    [action | _] = dest_node.actions

    if is_nil(action.templating),
      do: :session,
      else: :hsm
  rescue
    # in case any of the uuids don't exist, we just trap the exception
    _ -> :unknown
  end

  ## Label formatter so that we can apply the dynamic label to the message
  @spec process_labels(list() | nil) :: list() | nil
  defp process_labels(labels) when is_list(labels) do
    Enum.map(
      labels,
      fn label ->
        if is_nil(label["name_match"]),
          do: label,
          else: Map.put_new(label, "name", label["name_match"])
      end
    )
  end

  defp process_labels(labels), do: labels

  @doc """
  Execute a action, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Action.t(), FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}

  def execute(%{type: "link_google_sheet"} = action, context, _messages) do
    {context, message} = Sheets.execute(action, context)
    {:ok, context, [message]}
  end

  def execute(
        %{type: "call_webhook", method: "FUNCTION", url: "filesearch-gpt"} = action,
        context,
        []
      ) do
    # just call the webhook, and ask the caller to wait
    # we are processing the webhook using Oban and this happens asynchronously

    # Webhooks don't consume messages, so if we send a message while a webhook node is running,
    # the node won't be executed again because it only matches when the message list is empty (`[]`)
    # unified_api_enabled takes priority over is_kaapi_enabled.
    # unified routes to /api/v1/llm/call, kaapi routes to /api/v1/responses.
    # If neither flag is on, fall back to the legacy direct OpenAI call.
    cond do
      FunWithFlags.enabled?(:unified_api_enabled,
        for: %{organization_id: context.organization_id}
      ) ->
        execute_kaapi_filesearch(action, context, "unified-llm-call")

      FunWithFlags.enabled?(:is_kaapi_enabled,
        for: %{organization_id: context.organization_id}
      ) ->
        execute_kaapi_filesearch(action, context)

      true ->
        Webhook.execute(action, context)
        {:wait, context, []}
    end
  end

  def execute(%{type: "call_webhook"} = action, context, []) do
    Webhook.execute(action, context)
    {:wait, context, []}
  end

  def execute(%{type: "call_webhook"} = _action, context, messages) do
    {:wait, context, messages}
  end

  def execute(
        %{type: "set_wa_group_field"} = action,
        %{wa_group_id: wa_group_id} = context,
        messages
      ) do
    # we raise error if this action is runnning for a contact flow
    if is_nil(wa_group_id) do
      execute(%{action | type: "invalid action"}, context, messages)
    else
      name = action.field.name
      key = action.field[:key] || String.downcase(name) |> String.replace(" ", "_")
      value = ContactField.parse_contact_field_value(context, action.value)

      context = ContactField.add_wa_group_field(context, key, name, value, "string")

      {:ok, context, messages}
    end
  end

  def execute(%{type: "send_msg"} = action, %{wa_group_id: wa_group_id} = context, messages)
      when wa_group_id != nil do
    action = Map.put(action, :templating, nil)
    WAGroupAction.send_message(context, action, messages)
  end

  def execute(%{type: "set_run_result"} = action, context, messages) do
    value =
      context
      |> FlowContext.parse_context_string(action.value)
      |> Glific.execute_eex()

    category =
      context
      |> FlowContext.parse_context_string(action.category)

    results = %{
      "input" => value,
      "value" => value,
      "category" => category,
      "inserted_at" => DateTime.utc_now()
    }

    updated_context = FlowContext.update_results(context, %{action.name => results})

    {:ok, updated_context, messages}
  end

  def execute(action, %{wa_group_id: wa_group_id} = context, messages)
      when wa_group_id != nil do
    Logger.error(
      "Unsupported action type: for flow_id #{inspect(context.flow_id)} wa_group_id #{inspect(context.wa_group_id)} and the message is #{inspect(messages)}"
    )

    raise(UndefinedFunctionError, message: "Unsupported action type #{action.type} for WA group")
  end

  def execute(%{type: "send_msg"} = action, context, messages) do
    templating = Templating.execute(action.templating, context, messages)
    action = Map.put(action, :templating, templating)
    ContactAction.send_message(context, action, messages)
  end

  def execute(%{type: "send_interactive_msg"} = action, context, messages) do
    ContactAction.send_interactive_message(context, action, messages)
  end

  def execute(%{type: "send_broadcast"} = action, context, messages) do
    ContactAction.send_broadcast(context, action, messages)
  end

  def execute(%{type: "start_session"} = action, context, _messages),
    do: Flow.execute(action, context)

  def execute(%{type: "set_contact_language"} = action, context, messages) do
    # make sure we have a valid language to set
    context =
      if is_nil(action.text) || action.text == "",
        do: context,
        else: ContactSetting.set_contact_language(context, action.text)

    {:ok, context, messages}
  end

  def execute(%{type: "set_contact_name"} = action, context, messages) do
    value = ContactField.parse_contact_field_value(context, action.value)
    context = ContactSetting.set_contact_name(context, value)
    {:ok, context, messages}
  end

  # Fake the valid key so we can have the same function signature and simplify the code base
  def execute(%{type: "set_contact_field_valid"} = action, context, messages) do
    name = action.field.name
    key = action.field[:key] || String.downcase(name) |> String.replace(" ", "_")
    value = ContactField.parse_contact_field_value(context, action.value)

    context =
      if key == "settings",
        do: settings(context, value),
        else: ContactField.add_contact_field(context, key, name, value, "string")

    {:ok, context, messages}
  end

  def execute(%{type: "set_contact_field"} = action, context, messages) do
    # sometimes action.field.name does not exist based on what the user
    # has entered in the flow. We should have a validation for this, but
    # lets prevent the error from happening
    # if we don't recognize it, we just ignore it, and avoid an error being thrown
    # Issue #858
    if Map.get(action.field, :name) in ["", nil] do
      {:ok, context, messages}
    else
      execute(Map.put(action, :type, "set_contact_field_valid"), context, messages)
    end
  end

  def execute(%{type: "set_contact_profile"} = action, context, _messages) do
    {context, message} =
      @contact_profile
      |> Map.get(action.profile_type)
      |> Profiles.handle_flow_action(context, action)

    {:ok, context, [message]}
  end

  def execute(%{type: "enter_flow"} = action, context, _messages) do
    flow_uuid = get_flow_uuid(action, context)

    # check if we've seen this flow in this execution
    if Map.has_key?(context.uuids_seen, flow_uuid) do
      Glific.log_error("Repeated loop, hence finished the flow", false)
    else
      # check if we are looping with the same flow, if so reset
      # and start from scratch, since we really don't want to have too deep a stack
      maybe_reset_flows(context, flow_uuid)

      # if the action is part of a terminal node, then lets mark this context as
      # complete, and use the parent context
      {:node, node} = context.uuid_map[action.node_uuid]

      {context, parent_id} =
        if node.is_terminal == true,
          do:
            {FlowContext.reset_one_context(context,
               source: "enter_flow",
               event_meta: %{
                 "action" => "#{inspect(action)}",
                 "current_flow_uuid" => context.flow_uuid,
                 "new_flow" => flow_uuid
               }
             ), context.parent_id},
          else: {context, context.id}

      # we start off a new context here and don't really modify the current context
      # hence ignoring the return value of start_sub_flow
      # for now, we'll just delay by at least min_delay second

      context = Map.update!(context, :uuids_seen, &Map.put(&1, flow_uuid, 1))

      Flow.start_sub_flow(context, flow_uuid, parent_id)

      # We null the messages here, since we are going into a different flow
      # this clears any potential errors
      {:ok, context, []}
    end
  end

  def execute(%{type: "open_ticket"} = action, context, _messages) do
    {context, message} = Tickets.execute(action, context)

    {:ok, context, [message]}
  end

  def execute(%{type: "call_classifier"} = action, context, messages) do
    # just call the classifier, and ask the caller to wait

    ## Check if we have a different input then last message.
    ## If yes then pass that string as a message.
    ## we might need more refactoring here. But this is fine for now.

    message =
      if action.input in [nil, "@input.text"],
        do: context.last_message,
        else:
          Messages.create_temp_message(
            context.organization_id,
            FlowContext.parse_context_string(context, action.input),
            contact_id: context.contact_id,
            session_uuid: context.id
          )
          |> Repo.preload(contact: [:language])

    Dialogflow.execute(action, context, message)
    {:wait, context, messages}
  end

  def execute(%{type: "add_input_labels"} = action, context, messages) do
    ## We will soon figure out how we will manage the UUID with tags
    flow_label =
      action.labels
      |> Enum.map_join(", ", fn label ->
        FlowContext.parse_context_string(context, label["name"])
      end)

    add_flow_label(context, flow_label)

    {:ok, context, messages}
  end

  def execute(%{type: "add_contact_groups"} = action, context, messages) do
    ## We will soon figure out how we will manage the UUID with tags
    _list =
      Enum.reduce(
        action.groups,
        [],
        fn group, _acc ->
          case Glific.parse_maybe_integer(group["uuid"]) do
            {:ok, group_id} ->
              Groups.create_contact_group(%{
                contact_id: context.contact_id,
                group_id: group_id,
                organization_id: context.organization_id
              })

              {:ok, _} =
                Contacts.capture_history(context.contact_id, :contact_groups_updated, %{
                  event_label: "Added to collection: \"#{group["name"]}\"",
                  event_meta: %{
                    context_id: context.id,
                    group: %{
                      id: group_id,
                      name: group["name"],
                      uuid: group["uuid"]
                    },
                    flow: %{
                      id: context.flow.id,
                      name: context.flow.name,
                      uuid: context.flow.uuid
                    }
                  }
                })

            _ ->
              Logger.error("Could not parse action groups: #{inspect(action)}")
          end

          []
        end
      )

    {:ok, context, messages}
  end

  def execute(%{type: "remove_contact_groups"} = action, context, messages) do
    if action.groups == ["all_groups"] do
      groups_ids = Groups.get_group_ids()
      Groups.delete_contact_groups_by_ids(context.contact_id, groups_ids)

      {:ok, _} =
        Contacts.capture_history(context.contact_id, :contact_groups_updated, %{
          event_label: "Removed from All the collections",
          event_meta: %{
            context_id: context.id,
            group: %{
              ids: groups_ids
            },
            flow: %{
              id: context.flow.id,
              name: context.flow.name,
              uuid: context.flow.uuid
            }
          }
        })
    else
      groups_ids =
        Enum.map(
          action.groups,
          fn group ->
            {:ok, group_id} = Glific.parse_maybe_integer(group["uuid"])

            {:ok, _} =
              Contacts.capture_history(context.contact_id, :contact_groups_updated, %{
                event_label: "Removed from collection: \"#{group["name"]}\"",
                event_meta: %{
                  context_id: context.id,
                  group: %{
                    id: group_id,
                    name: group["name"],
                    uuid: group["uuid"]
                  },
                  flow: %{
                    id: context.flow.id,
                    name: context.flow.name,
                    uuid: context.flow.uuid
                  }
                }
              })

            group_id
          end
        )

      Groups.delete_contact_groups_by_ids(context.contact_id, groups_ids)
    end

    {:ok, context, messages}
  end

  def execute(%{type: type} = _action, context, [msg])
      when type in @wait_for do
    if msg.body != "No Response" do
      Logger.info(
        "Message #{msg.body} with context (#{context.id}) received while waiting for time"
      )

      {:error, "unexpected message received while waiting for time"}
    else
      {:ok, context, []}
    end
  end

  @sleep_timeout 4 * 1000

  def execute(%{type: type} = action, context, [])
      when type in @wait_for do
    if action.wait_time == @default_wait_time do
      ## Ideally we should do it by async call
      ## but this is fine as a sort term fix.
      Process.sleep(@sleep_timeout)
      {:ok, context, []}
    else
      {:ok, context} =
        FlowContext.update_flow_context(
          context,
          %{
            wakeup_at: DateTime.add(DateTime.utc_now(), action.wait_time),
            is_background_flow: context.flow.is_background,
            is_await_result: type == "wait_for_result"
          }
        )

      {:wait, context, []}
    end
  end

  def execute(action, context, messages) do
    Logger.error(
      "Unsupported action type: for flow_id #{inspect(context.flow_id)} contact_id #{inspect(context.contact_id)} and the message is #{inspect(messages)}"
    )

    raise(UndefinedFunctionError, message: "Unsupported action type #{action.type}")
  end

  @spec execute_kaapi_filesearch(Action.t(), FlowContext.t(), String.t()) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]}
  defp execute_kaapi_filesearch(action, context, webhook_name \\ "call_and_wait") do
    with {:ok, kaapi_secrets} <- Kaapi.fetch_kaapi_creds(context.organization_id),
         api_key when is_binary(api_key) <- Map.get(kaapi_secrets, "api_key") do
      updated_headers = Map.put(action.headers, "X-API-KEY", api_key)
      updated_action = %{action | headers: updated_headers}
      Webhook.webhook_and_wait(updated_action, context, true, webhook_name)
    else
      {:error, _error} ->
        Webhook.webhook_and_wait(action, context, false)
    end
  end

  @spec add_flow_label(FlowContext.t(), String.t()) :: nil
  defp add_flow_label(%{last_message: nil}, _flow_label), do: nil

  defp add_flow_label(%{last_message: last_message}, flow_label) do
    # there is a chance that:
    # when we send a fake temp message (like No Response)
    # or when a flow is resumed, there is no last_message
    # hence we check for the existence of one in these functions
    message = Repo.get(Message, last_message.id)

    new_labels =
      if message.flow_label in [nil, ""] do
        flow_label
      else
        message.flow_label <> ", " <> flow_label
      end

    {:ok, _} =
      Repo.get(Message, last_message.id)
      |> Message.changeset(%{flow_label: new_labels})
      |> Repo.update()

    nil
  end

  @spec settings(FlowContext.t(), String.t()) :: FlowContext.t()
  defp settings(context, value) do
    case String.downcase(value) do
      "optout" ->
        ContactAction.optout(context)

      "optin" ->
        message_id =
          if context.last_message == nil,
            do: nil,
            else: context.last_message.bsp_message_id

        ContactAction.optin(
          context,
          method: "WA",
          message_id: message_id,
          bsp_status: :session_and_hsm
        )

      _ ->
        ContactSetting.set_contact_preference(context, value)
    end
  end

  # let's format attachment and add as a map
  @spec process_attachments(list()) :: map()
  defp process_attachments(nil), do: %{}

  ## we will remove this once we have a fix it form the flow editor
  defp process_attachments(attachment_list) do
    attachment_list
    |> Enum.reduce(%{}, fn attachment, acc -> do_process_attachment(attachment, acc) end)
  end

  @spec do_process_attachment(String.t(), map()) :: map()
  defp do_process_attachment(attachment, acc) do
    case String.split(attachment, ":", parts: 2) do
      [type, url] ->
        type = if type == "application", do: "document", else: type
        Map.put(acc, type, url)

      _ ->
        acc
    end
  end

  @spec maybe_reset_flows(FlowContext.t(), Ecto.UUID.t()) :: boolean
  defp maybe_reset_flows(context, flow_uuid) do
    # check and see if there are any matching flows that are not completed
    matching =
      FlowContext
      |> where([fc], fc.contact_id == ^context.contact_id)
      |> where([fc], fc.flow_uuid == ^flow_uuid)
      |> where([fc], is_nil(fc.completed_at))
      |> Repo.aggregate(:count)

    if matching > 0 do
      FlowContext.reset_all_contexts(context, "Repeated loop, hence finished the flow")
      true
    else
      false
    end
  end

  @spec get_flow_uuid(Action.t(), FlowContext.t()) :: String.t()
  defp get_flow_uuid(
         %{enter_flow_name: "Expression", enter_flow_expression: expression} = _action,
         context
       ),
       do:
         FlowContext.parse_context_string(context, expression)
         |> Glific.execute_eex()
         |> String.trim()

  defp get_flow_uuid(action, _),
    do: action.enter_flow_uuid
end
