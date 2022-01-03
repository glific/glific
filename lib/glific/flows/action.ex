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
    Groups,
    Groups.Group,
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

  require Logger

  @min_delay 2

  @required_field_common [:uuid, :type]
  @required_fields_enter_flow [:flow | @required_field_common]
  @required_fields_language [:language | @required_field_common]
  @required_fields_set_contact_field [:value, :field | @required_field_common]
  @required_fields_set_contact_name [:name | @required_field_common]
  @required_fields_webhook [:url, :headers, :method, :result_name | @required_field_common]
  @required_fields_classifier [:input, :result_name | @required_field_common]
  @required_fields [:text | @required_field_common]
  @required_fields_label [:labels | @required_field_common]
  @required_fields_group [:groups | @required_field_common]
  @required_fields_contact [:contacts, :text | @required_field_common]
  @required_fields_waittime [:delay]
  @required_fields_interactive_template [:name, :id | @required_field_common]

  @wait_for ["wait_for_time", "wait_for_result"]

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
          wait_time: integer() | nil,
          interactive_template_id: integer() | nil
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
    field :contacts, :map

    field :wait_time, :integer
    field :interactive_template_id, :integer

    field :node_uuid, Ecto.UUID
    embeds_one :node, Node

    embeds_one :templating, Templating

    field :enter_flow_uuid, Ecto.UUID
    field :enter_flow_name, :string
    field :enter_flow_expression, :string

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
    process(json, uuid_map, node, %{labels: json["labels"]})
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

    {templating, uuid_map} = Templating.process(json["templating"], uuid_map)
    attrs = Map.put(attrs, :templating, templating)
    process(json, uuid_map, node, attrs)
  end

  def process(%{"type" => "send_interactive_msg"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_interactive_template)
    process(json, uuid_map, node, %{interactive_template_id: json["id"], labels: json["labels"]})
  end

  def process(%{"type" => "remove_contact_groups"} = json, uuid_map, node) do
    Flows.check_required_fields(json, @required_fields_group)

    if json["all_groups"] do
      process(json, uuid_map, node, %{groups: ["all_groups"]})
    else
      process(json, uuid_map, node, %{groups: json["groups"]})
    end
  end

  @default_wait_time 5 * 60
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
      labels: json["labels"],
      quick_replies: json["quick_replies"],
      attachments: process_attachments(json["attachments"])
    }

    {templating, uuid_map} = Templating.process(json["templating"], uuid_map)

    attrs = Map.put(attrs, :templating, templating)

    process(json, uuid_map, node, attrs)
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
      {:ok, _} -> errors
      _ -> [{object, "Could not find #{get_name(object)}: #{entity["name"]}"}] ++ errors
    end
  end

  @spec object(String.t()) :: atom()
  defp object("send_broadcast"), do: Contact
  defp object("add_contact_groups"), do: Group
  defp object("remove_contact_groups"), do: Group

  @doc """
  Validate a action and all its children
  """
  @spec validate(Action.t(), Keyword.t(), map()) :: Keyword.t()
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
            [{object, "Could not parse #{get_name(object)}"}] ++ errors
        end
      end
    )
  end

  def validate(%{type: "enter_flow"} = action, errors, _flow) do
    # ensure that the flow exists
    case Repo.fetch_by(Flow, %{uuid: action.enter_flow_uuid}) do
      {:ok, _} -> errors
      _ -> [{Flow, "Could not find Sub Flow: #{action.enter_flow_name}"}] ++ errors
    end
  end

  def validate(%{type: type} = action, errors, flow)
      when type in @wait_for do
    # ensure that any downstream messages from this action are of type HSM
    # if wait time > 24 hours!
    if action.wait_time >= 24 * 60 * 60 &&
         type_of_next_message(flow, action) == :session,
       do:
         [{Message, "The next message after a long wait for time should be an HSM template"}] ++
           errors,
       else: errors
  end

  def validate(%{type: "set_contact_language"} = action, errors, _flow) do
    if is_nil(action.text) || action.text == "",
      do: [{Message, "Language is a required field"}] ++ errors,
      else: errors
  end

  # default validate, do nothing
  def validate(_action, errors, _flow), do: errors

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

  @doc """
  Execute a action, given a message stream.
  Consume the message stream as processing occurs
  """
  @spec execute(Action.t(), FlowContext.t(), [Message.t()]) ::
          {:ok | :wait, FlowContext.t(), [Message.t()]} | {:error, String.t()}
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
    # if we dont recognize it, we just ignore it, and avoid an error being thrown
    # Issue #858
    if Map.get(action.field, :name) in ["", nil] do
      {:ok, context, messages}
    else
      execute(Map.put(action, :type, "set_contact_field_valid"), context, messages)
    end
  end

  def execute(%{type: "enter_flow"} = action, context, _messages) do
    flow_uuid = get_flow_uuid(action, context)

    # check if we've seen this flow in this execution
    if Map.has_key?(context.uuids_seen, flow_uuid) do
      FlowContext.log_error("Repeated loop, hence finished the flow")
    else
      # check if we are looping with the same flow, if so reset
      # and start from scratch, since we really dont want to have too deep a stack
      maybe_reset_flows(context, flow_uuid)

      # if the action is part of a terminal node, then lets mark this context as
      # complete, and use the parent context
      {:node, node} = context.uuid_map[action.node_uuid]

      {context, parent_id} =
        if node.is_terminal == true,
          do: {FlowContext.reset_one_context(context), context.parent_id},
          else: {context, context.id}

      # we start off a new context here and dont really modify the current context
      # hence ignoring the return value of start_sub_flow
      # for now, we'll just delay by at least min_delay second
      context =
        context
        |> Map.put(:delay, max(context.delay + @min_delay, @min_delay))
        |> Map.update!(:uuids_seen, &Map.put(&1, flow_uuid, 1))

      Flow.start_sub_flow(context, flow_uuid, parent_id)

      # We null the messages here, since we are going into a different flow
      # this clears any potential errors
      {:ok, context, []}
    end
  end

  def execute(%{type: "call_webhook"} = action, context, messages) do
    # just call the webhook, and ask the caller to wait
    # we are processing the webhook using Oban and this happens asynchrnously
    Webhook.execute(action, context)
    # webhooks dont consume a message, so we send it forward
    {:wait, context, messages}
  end

  def execute(%{type: "call_classifier"} = action, context, messages) do
    # just call the classifier, and ask the caller to wait
    # we are processing the webhook using Oban and this happens asynchronously
    Dialogflow.execute(action, context, context.last_message)
    # webhooks dont consume a message, so we send it forward
    {:wait, context, messages}
  end

  def execute(%{type: "add_input_labels"} = action, context, messages) do
    ## We will soon figure out how we will manage the UUID with tags
    flow_label =
      action.labels
      |> Enum.map_join(", ", fn label -> label["name"] end)

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
    if msg.body != "No Response",
      do: FlowContext.log_error("Unexpected message #{msg.body} received"),
      else: {:ok, context, []}
  end

  def execute(%{type: type} = action, context, [])
      when type in @wait_for do
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

  def execute(action, _context, _messages),
    do: raise(UndefinedFunctionError, message: "Unsupported action type #{action.type}")

  @spec add_flow_label(FlowContext.t(), String.t()) :: nil
  defp add_flow_label(%{last_message: nil}, _flow_label), do: nil

  defp add_flow_label(%{last_message: last_message}, flow_label) do
    # there is a chance that:
    # when we send a fake temp message (like No Response)
    # or when a flow is resumed, there is no last_message
    # hence we check for the existence of one in these functions
    {:ok, _} =
      Repo.get(Message, last_message.id)
      |> Message.changeset(%{flow_label: flow_label})
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

  ## we will remvoe this once we have a fix it form the flow editor
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
