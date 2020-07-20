defmodule Glific.Flows.ActionTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Action,
    Node,
    Templating,
  }

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
end
