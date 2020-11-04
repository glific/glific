defmodule Glific.Flows.CategoryTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Category,
    Exit,
    FlowContext,
    Node
  }

  test "process extracts the right values from json" do
    uuid_1 = Ecto.UUID.generate()
    uuid_2 = Ecto.UUID.generate()
    json = %{"uuid" => uuid_1, "exit_uuid" => uuid_2, "name" => "Default Category"}

    {category, uuid_map} = Category.process(json, %{})

    assert category.uuid == uuid_1
    assert category.exit_uuid == uuid_2
    assert category.name == "Default Category"
    assert uuid_map[category.uuid] == {:category, category}

    # ensure that not sending the required fields, raises an error
    json = %{"uuid" => uuid_1, "exit_uuid" => uuid_2}
    assert_raise ArgumentError, fn -> Category.process(json, %{}) end

    json = %{"exit_uuid" => uuid_2, "name" => "Default Category"}
    assert_raise ArgumentError, fn -> Category.process(json, %{}) end

    json = %{}
    assert_raise ArgumentError, fn -> Category.process(json, %{}) end
  end

  test "test category execute with exit node with null destination", attrs do
    node = %Node{uuid: Ecto.UUID.generate()}
    exit_uuid = Ecto.UUID.generate()
    json = %{"uuid" => exit_uuid, "destination_uuid" => nil}
    {_exit, uuid_map} = Exit.process(json, %{}, node)

    json = %{
      "uuid" => Ecto.UUID.generate(),
      "exit_uuid" => exit_uuid,
      "name" => "Default Category"
    }

    {category, uuid_map} = Category.process(json, uuid_map)

    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: 1,
        flow_id: 1,
        flow_uuid: Ecto.UUID.generate(),
        uuid_map: uuid_map,
        organization_id: attrs.organization_id
      })

    result = Category.execute(category, context, [])
    assert result == {:ok, nil, []}
  end
end
