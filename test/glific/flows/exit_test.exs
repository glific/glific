defmodule Glific.Flows.ExitTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Exit,
    Node
  }

  test "process extracts the right values from json" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "destination_uuid" => "UUID 2"}

    {exit, uuid_map} = Exit.process(json, %{}, node)

    assert exit.uuid == "UUID 1"
    assert exit.destination_node_uuid == "UUID 2"
    assert exit.node_uuid == node.uuid
    assert uuid_map[exit.uuid] == {:exit, exit}

    # ensure that destination_uuid of nil also works
    json = %{"uuid" => "UUID 1", "destination_uuid" => nil}

    {exit, uuid_map} = Exit.process(json, %{}, node)

    assert exit.uuid == "UUID 1"
    assert exit.destination_node_uuid == nil
    assert uuid_map[exit.uuid] == {:exit, exit}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1"}
    assert_raise ArgumentError, fn -> Exit.process(json, %{}, node) end

    json = %{"destination_uuid" => "UUID 1"}
    assert_raise ArgumentError, fn -> Exit.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Exit.process(json, %{}, node) end
  end

end
