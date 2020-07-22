defmodule Glific.Flows.ExitTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Exit,
    FlowContext,
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

  test "execute when the destination node is nil" do
    node = %Node{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "destination_uuid" => nil}

    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: 1,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: %{}
      })

    {exit, _uuid_map} = Exit.process(json, %{}, node)
    {:ok, result, messages} = Exit.execute(exit, context, ["will this disappear"])

    assert is_nil(result)
    assert messages == []
    context = Repo.get!(FlowContext, context.id)
    assert !is_nil(context.completed_at)
  end

  # lets set up a node where the execute fails. A lot easier for us to test that
  # exit works as normal and sends it to the right place
  test "execute when the destination node is valid " do
    node_uuid = Ecto.UUID.generate()
    node = %Node{uuid: node_uuid, actions: [], router: nil}
    json = %{"uuid" => "UUID 1", "destination_uuid" => node_uuid}
    uuid_map = %{node_uuid => {:node, node}}

    {exit, uuid_map} = Exit.process(json, uuid_map, node)

    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: 1,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: uuid_map
      })

    result = Exit.execute(exit, context, ["will this disappear"])

    assert elem(result, 0) == :error
    assert elem(result, 1) == "Unsupported node type"
  end
end
