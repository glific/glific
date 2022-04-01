defmodule Glific.Flows.ActionTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Contact,
    Groups,
    Groups.ContactGroup,
    Partners,
    Seeds.SeedsDev,
    Settings,
    Templates.InteractiveTemplate
  }

  alias Glific.Flows.{
    Action,
    Flow,
    FlowContext,
    Node,
    WebhookLog
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    organization = SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_interactives(organization)
    :ok
  end

  test "process extracts the right values from json for enter_flow action" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "enter_flow", "flow" => %{"uuid" => "UUID 2"}}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "enter_flow"
    assert action.enter_flow_uuid == "UUID 2"
    assert action.node_uuid == node.uuid
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "enter_flow"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{"uuid" => "UUID 1", "flow" => %{"uuid" => "UUID 2"}}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for set_contact_language action" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "set_contact_language", "language" => "Hindi"}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "set_contact_language"
    assert action.node_uuid == node.uuid
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "set_contact_language"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{"uuid" => "UUID 1", "language" => "Hindi"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for set_contact_name action" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "set_contact_name", "name" => "Contact Name"}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "set_contact_name"
    assert action.node_uuid == node.uuid
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "set_contact_name"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{"uuid" => "UUID 1", "name" => "Contact Name"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for set_contact_field action" do
    node = %Node{uuid: "Test UUID"}

    json = %{
      "uuid" => "UUID 1",
      "type" => "set_contact_field",
      "value" => "Test Value",
      "field" => %{"name" => "Test Name", "key" => "Test Key"}
    }

    {action, _uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "set_contact_field"
    assert action.node_uuid == node.uuid
    assert action.value == "Test Value"
    assert action.field.name == "Test Name"
    assert action.field.key == "Test Key"

    # ensure we can send key instead of name
    json = %{
      "uuid" => "UUID 1",
      "type" => "set_contact_field",
      "value" => "Test Value",
      "field" => %{"key" => "Test Key"}
    }

    {action, _uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "set_contact_field"
    assert action.node_uuid == node.uuid
    assert action.field.name == "Test Key"
    assert action.field.key == "Test Key"

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "set_contact_field", "value" => "Test Value"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{
      "uuid" => "UUID 1",
      "type" => "set_contact_field",
      "field" => %{"name" => "Test Name", "key" => "Test Key"}
    }

    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{
      "uuid" => "UUID 1",
      "value" => "Test Value",
      "field" => %{"name" => "Test Name", "key" => "Test Key"}
    }

    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for webhook" do
    node = %Node{uuid: "Test UUID"}

    json = %{
      "uuid" => "UUID 1",
      "type" => "call_webhook",
      "url" => "URL",
      "method" => "METHOD",
      "result_name" => "RESULT_NAME",
      "headers" => %{
        Accept: "application/json",
        "Content-Type": "application/json"
      }
    }

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "call_webhook"
    assert action.node_uuid == node.uuid
    assert action.url == "URL"
    assert is_map(action.headers)
    assert uuid_map[action.uuid] == {:action, action}

    json = %{
      "uuid" => "UUID 1",
      "type" => "call_webhook",
      "url" => "URL",
      "method" => "METHOD",
      "result_name" => "RESULT_NAME"
    }

    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for send_broadcast" do
    node = %Node{uuid: "Test UUID"}

    json = %{
      "uuid" => "UUID 1",
      "type" => "send_broadcast",
      "text" => "Test Text",
      "contacts" => ["23", "45"]
    }

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "send_broadcast"
    assert action.node_uuid == node.uuid
    assert action.text == "Test Text"
    assert action.contacts == ["23", "45"]
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "send_broadcast", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for send_interactive_msg" do
    node = %Node{uuid: "Test UUID"}

    json = %{
      "id" => 1,
      "name" => "Quick Reply Text",
      "text" =>
        "{\"content\":{\"caption\":\"Glific is a two way communication platform\",\"text\":\"How excited are you for Glific?\",\"type\":\"text\"},\"options\":[{\"title\":\"Excited\",\"type\":\"text\"},{\"title\":\"Very Excited\",\"type\":\"text\"}],\"type\":\"quick_reply\"}",
      "type" => "send_interactive_msg",
      "uuid" => "UUID 1"
    }

    {action, uuid_map} = Action.process(json, %{}, node)
    assert action.uuid == "UUID 1"
    assert action.type == "send_interactive_msg"
    assert action.node_uuid == node.uuid
    assert action.interactive_template_id == 1
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "send_interactive_msg"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for add_contact_groups" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "add_contact_groups", "groups" => ["23", "45"]}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "add_contact_groups"
    assert action.node_uuid == node.uuid
    assert action.groups == ["23", "45"]
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "send_broadcast", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for remove_contact_groups" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "remove_contact_groups", "groups" => ["23", "45"]}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "remove_contact_groups"
    assert action.node_uuid == node.uuid
    assert action.groups == ["23", "45"]
    assert uuid_map[action.uuid] == {:action, action}

    json = %{
      "uuid" => "UUID 1",
      "type" => "remove_contact_groups",
      "all_groups" => true,
      "groups" => ["23", "45"]
    }

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "remove_contact_groups"
    assert action.node_uuid == node.uuid
    assert action.groups == ["all_groups"]
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "send_broadcast", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for wait_for_time" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "wait_for_time", "delay" => "23"}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "wait_for_time"
    assert action.node_uuid == node.uuid
    assert action.wait_time == 23
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "wait_for_time", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for wait_for_result" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "wait_for_result", "delay" => "23"}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "wait_for_result"
    assert action.node_uuid == node.uuid
    assert action.wait_time == 23
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "wait_for_result", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for other actions" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "test_type", "text" => "Test Text"}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "test_type"
    assert action.node_uuid == node.uuid
    assert action.text == "Test Text"
    assert uuid_map[action.uuid] == {:action, action}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "test_type"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{"uuid" => "UUID 1", "text" => "Test Text"}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "execute an action when type is send_msg", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    # preload contact
    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:flow, :contact])

    action = %Action{
      type: "send_msg",
      text: "This is a test send_msg",
      labels: [
        %{
          "name" => "Age Group 11 to 14",
          "uuid" => "aed0e1a1-29ad-413e-9aaa-3ece3ec4011e"
        }
      ]
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, _updated_context, _updated_message_stream} = result

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is a test send_msg"
    assert message.flow_label == "Age Group 11 to 14"
  end

  test "execute an action when type is send_interactive_msg", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})
    # preload contact
    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    # preload contact
    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:flow, :contact])
    interactive = Repo.get_by(InteractiveTemplate, %{label: "Quick Reply Text"})

    action = %Action{
      type: "send_interactive_msg",
      text: "This is a test send_msg",
      interactive_template_id: interactive.id,
      labels: [
        %{
          "name" => "Age Group 11 to 14",
          "uuid" => "aed0e1a1-29ad-413e-9aaa-3ece3ec4011e"
        }
      ]
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, _updated_context, _updated_message_stream} = result

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "Glific is a two way communication platform"
    assert message.flow_label == "Age Group 11 to 14"
  end

  test "execute an action when type is send_broadcast", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})
    staff = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    # preload contact
    attrs = %{
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    # preload contact
    {:ok, context} = FlowContext.create_flow_context(attrs)
    context = Repo.preload(context, [:flow, :contact])

    action = %Action{
      type: "send_broadcast",
      text: "This is a send_broadcast message",
      contacts: [%{"uuid" => staff.id, "name" => staff.name}]
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, _updated_context, _updated_message_stream} = result

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^staff.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is a send_broadcast message"
  end

  test "execute an action when type is set_contact_language", _attrs do
    language_label = "English"
    [language | _] = Settings.list_languages(%{filter: %{label: language_label}})

    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    context = %FlowContext{contact_id: contact.id, flow_id: 1} |> Repo.preload([:contact, :flow])

    action = %Action{type: "set_contact_language", text: "English"}

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, _updated_message_stream} = result
    assert updated_context.contact.language_id == language.id
  end

  test "execute an action when type is set_contact_name", _attrs do
    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    context =
      %FlowContext{contact_id: contact.id, flow_id: 1}
      |> Repo.preload([:contact, :flow])

    action = %Action{type: "set_contact_name", value: "Updated Name"}

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, _updated_message_stream} = result
    assert updated_context.contact.name == action.value
  end

  test "execute an action when type is set_contact_field to set contact preferences", _attrs do
    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, results: %{"test_result" => "preference1"}}
      |> Repo.preload([:contact, :flow])

    action = %Action{
      type: "set_contact_field",
      value: "@results.test_result",
      field: %{key: "settings", name: "Settings"}
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, _updated_message_stream} = result
    assert updated_context.contact.settings["preferences"]["preference1"] == true

    # now set an action without the name field
    action = %Action{
      type: "set_contact_field",
      value: "@results.test_result",
      field: %{key: "settings"}
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)
    assert {:ok, updated_context, __updated_message_stream} = result
    assert updated_context == context
  end

  test "execute an action when type is set_contact_field to add contact field", _attrs do
    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, results: %{"test_result" => "field1"}}
      |> Repo.preload([:contact, :flow])

    action = %Action{
      type: "set_contact_field",
      value: "@results.test_result",
      field: %{key: "not_settings", name: "Not Settings"}
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, _updated_message_stream} = result

    assert updated_context.contact.fields[action.field.key].value == "field1"
    assert updated_context.contact.fields[action.field.key].type == "string"
    assert updated_context.contact.fields[action.field.key].label == "Not Settings"
  end

  test "execute an action when type is enter_flow", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, organization_id: attrs.organization_id}
      |> Repo.preload([:contact, :flow])
      |> Map.put(:uuid_map, %{"Test UUID" => {:node, %{is_terminal: false}}})

    # using uuid of language flow
    action = %Action{
      type: "enter_flow",
      uuid: "UUID 1",
      enter_flow_uuid: "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
      node_uuid: "Test UUID"
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, _updated_message_stream} = result

    assert Glific.delete_multiple(updated_context, [:delay, :uuids_seen]) ==
             Glific.delete_multiple(context, [:delay, :uuids_seen])
  end

  test "execute an action when type is wait_for_time", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    context_args = %{
      contact_id: contact.id,
      flow_id: 1,
      flow_uuid: Ecto.UUID.generate(),
      organization_id: attrs.organization_id
    }

    {:ok, context} = FlowContext.create_flow_context(context_args)
    context = Repo.preload(context, [:contact, :flow])

    # using uuid of language flow
    action = %Action{
      type: "wait_for_time",
      uuid: "UUID 1",
      wait_time: 0,
      node_uuid: "Test UUID"
    }

    # bad message
    assert elem(Action.execute(action, context, [%{body: "FooBar"}]), 0) == :error

    # good message, proceed ahead
    result = Action.execute(action, context, [%{body: "No Response"}])
    assert match?(%FlowContext{}, elem(result, 1))

    # delay is 0
    result = Action.execute(action, context, [])
    assert match?(%FlowContext{}, elem(result, 1))

    node = %{uuid: Ecto.UUID.generate()}
    # here we need a real context
    flow =
      Repo.get(Flow, 1)
      |> Map.put(:nodes, [node])
      |> Map.put(:start_node, node)
      |> Map.put(:uuid_map, %{})
      |> Map.put(:is_background, false)

    {:ok, context} = FlowContext.seed_context(flow, contact, "published")

    # delay > 0
    result = Action.execute(Map.put(action, :wait_time, 30), context |> Repo.preload(:flow), [])
    assert elem(result, 0) == :wait

    context = Repo.get(FlowContext, context.id)
    assert !is_nil(context.wakeup_at)
    assert context.is_background_flow == false
  end

  test "execute an action when type is call_webhook", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})

    # preload contact
    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, organization_id: attrs.organization_id}
      |> Repo.preload([:contact, :flow])

    url = "https://postman-echo.com/post"

    # using uuid of language flow
    action = %Action{
      type: "call_webhook",
      uuid: "UUID 1",
      url: url,
      body: "qbc",
      method: "POST",
      headers: %{
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      result_name: "test_webhook",
      node_uuid: "Test UUID"
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:wait, updated_context, _updated_message_stream} = result

    assert updated_context == context

    # ensure we have an entry in the webhook log
    # webhooks are tested in a complete manner in webhook_test, so skipping here
    log = Repo.get_by(WebhookLog, %{url: url})

    assert String.contains?(log.error, "Error in decoding webhook body")
  end

  defp add_contact_group(contact, organization_id) do
    {:ok, group} =
      Groups.create_group(%{
        label: Faker.String.base64(10),
        organization_id: organization_id
      })

    {:ok, _contact_group} =
      Groups.create_contact_group(%{
        contact_id: contact.id,
        group_id: group.id,
        organization_id: organization_id
      })

    group
  end

  defp count_groups(contact) do
    ContactGroup
    |> where([cg], cg.contact_id == ^contact.id)
    |> Repo.aggregate(:count)
  end

  test "execute the action when type is remove_contact_groups", attrs do
    Partners.organization(attrs.organization_id)

    contact = Repo.get_by(Contact, %{name: "Default receiver"})
    assert count_groups(contact) == 0

    g1 = add_contact_group(contact, attrs.organization_id)
    _g2 = add_contact_group(contact, attrs.organization_id)
    _g3 = add_contact_group(contact, attrs.organization_id)
    assert count_groups(contact) == 3

    # preload contact
    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, organization_id: attrs.organization_id}
      |> Repo.preload([:contact, :flow])

    # using uuid of language flow
    action = %Action{
      type: "remove_contact_groups",
      groups: [%{"uuid" => "#{g1.id}"}],
      node_uuid: "Test UUID",
      uuid: "UUID 1"
    }

    message_stream = []

    _result = Action.execute(action, context, message_stream)
    assert count_groups(contact) == 2

    action = %Action{
      type: "remove_contact_groups",
      groups: ["all_groups"],
      node_uuid: "Test UUID",
      uuid: "UUID 1"
    }

    _result = Action.execute(action, context, message_stream)
    assert count_groups(contact) == 0
  end

  test "execute an action when type is not supported" do
    action = %Action{type: "others"}
    context = %FlowContext{}
    message_stream = []

    assert_raise UndefinedFunctionError, fn ->
      Action.execute(action, context, message_stream)
    end
  end
end
