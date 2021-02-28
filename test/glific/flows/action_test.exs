defmodule Glific.Flows.ActionTest do
  use Glific.DataCase

  alias Glific.{
    Contacts,
    Partners,
    Seeds.SeedsDev,
    Settings
  }

  alias Glific.Flows.{
    Action,
    FlowContext,
    Node
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
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
    json = %{"uuid" => "UUID 1", "type" => "call_webhook",
             "url" => "URL",
             "method" => "METHOD",
             "result_name" => "RESULT_NAME",
             "headers" => %{
               "Accept": "application/json",
               "Content-Type": "application/json"
             },
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
      "result_name" => "RESULT_NAME",
    }
    assert_raise ArgumentError, fn -> Action.process(json, %{}, node) end
  end

  test "process extracts the right values from json for send_broadcast" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "send_broadcast", "text" => "Test Text",
             "contacts" => ["23", "45"]}

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

  test "process extracts the right values from json for add_contact_groups" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "type" => "add_contact_groups",
             "groups" => ["23", "45"]}

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
    json = %{"uuid" => "UUID 1", "type" => "remove_contact_groups",
             "groups" => ["23", "45"]}

    {action, uuid_map} = Action.process(json, %{}, node)

    assert action.uuid == "UUID 1"
    assert action.type == "remove_contact_groups"
    assert action.node_uuid == node.uuid
    assert action.groups == ["23", "45"]
    assert uuid_map[action.uuid] == {:action, action}

    json = %{"uuid" => "UUID 1", "type" => "remove_contact_groups",
             "all_groups" => true, "groups" => ["23", "45"]}

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
    json = %{"uuid" => "UUID 1", "type" => "send_broadcast", "text" => "Test Text"}
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

    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

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

    action = %Action{type: "send_msg", text: "This is a test message"}

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result

    message =
      Glific.Messages.Message
      |> where([m], m.contact_id == ^contact.id)
      |> Ecto.Query.last()
      |> Repo.one()

    assert message.body == "This is a test message"
  end

  test "execute an action when type is set_contact_language", attrs do
    language_label = "English (United States)"
    [language | _] = Settings.list_languages(%{filter: %{label: language_label}})

    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    action = %Action{type: "set_contact_language", text: "English (United States)"}

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result
    assert updated_context.contact.language_id == language.id
  end

  test "execute an action when type is set_contact_name", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context = %FlowContext{contact_id: contact.id} |> Repo.preload(:contact)

    action = %Action{type: "set_contact_name", value: "Updated Name"}

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result
    assert updated_context.contact.name == action.value
  end

  test "execute an action when type is set_contact_field to set contact preferences", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    context =
      %FlowContext{contact_id: contact.id, results: %{"test_result" => "preference1"}}
      |> Repo.preload(:contact)

    action = %Action{
      type: "set_contact_field",
      value: "@results.test_result",
      field: %{key: "settings", name: "Settings"}
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result
    assert updated_context.contact.settings["preferences"]["preference1"] == true
  end

  test "execute an action when type is set_contact_field to add contact field", attrs do
    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    context =
      %FlowContext{contact_id: contact.id, results: %{"test_result" => "field1"}}
      |> Repo.preload(:contact)

    action = %Action{
      type: "set_contact_field",
      value: "@results.test_result",
      field: %{key: "not_settings", name: "Not Settings"}
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result

    assert updated_context.contact.fields[action.field.key].value == "field1"
    assert updated_context.contact.fields[action.field.key].type == "string"
    assert updated_context.contact.fields[action.field.key].label == "Not Settings"
  end

  test "execute an action when type is enter_flow", attrs do
    Partners.organization(attrs.organization_id)

    [contact | _] =
      Contacts.list_contacts(%{filter: Map.merge(attrs, %{name: "Default receiver"})})

    # preload contact
    context =
      %FlowContext{contact_id: contact.id, flow_id: 1, organization_id: attrs.organization_id}
      |> Repo.preload([:contact, :flow])

    # using uuid of language flow
    action = %Action{
      type: "enter_flow",
      uuid: "UUID 1",
      enter_flow_uuid: "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
      node_uuid: "Test UUID"
    }

    message_stream = []

    result = Action.execute(action, context, message_stream)

    assert {:ok, updated_context, updated_message_stream} = result

    assert Map.delete(updated_context, :delay) == Map.delete(context, :delay)
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
