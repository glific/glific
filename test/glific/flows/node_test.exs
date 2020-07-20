defmodule Glific.Flows.NodeTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Flow,
    Node
  }

  test "process extracts the right values from json" do
    flow = %Flow{uuid: "Flow UUID 1"}

    json = %{
      "uuid" => "UUID 1",
      "actions" => [
        %{"uuid" => "UUID Act 1", "type" => "enter_flow", "flow" => %{"uuid" => "UUID 2"}},
        %{"uuid" => "UUID Act 2", "type" => "set_contact_language", "language" => "Hindi"}
      ],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => "UUID Exit 2"},
        %{"uuid" => "UUID Exit 3", "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    assert node.uuid == "UUID 1"
    assert uuid_map[node.uuid] == {:node, node}
    assert length(node.actions) == 2
    assert length(node.exits) == 2

    # add a node with no actions but a router
    json = %{
      "uuid" => "UUID 123",
      "actions" => [],
      "exits" => [
        %{"uuid" => "UUID Exit 1", "destination_uuid" => "UUID Exit 2"},
        %{"uuid" => "UUID Exit 3", "destination_uuid" => nil}
      ],
      "router" => %{
        "operand" => "@input.text",
        "type" => "switch",
        "default_category_uuid" => "Default Cat UUID",
        "result_name" => "Language",
        "categories" => [
          %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
          %{
            "uuid" => "Default Cat UUID",
            "exit_uuid" => "UUID Cat 2",
            "name" => "Default Category"
          }
        ],
        "cases" => [
          %{
            "uuid" => "UUID 1",
            "type" => "some type",
            "arguments" => [1, 2, 3],
            "category_uuid" => "UUID Cat 1"
          }
        ]
      }
    }

    {node, uuid_map} = Node.process(json, %{}, flow)

    assert node.uuid == "UUID 123"
    assert uuid_map[node.uuid] == {:node, node}
    assert Enum.empty?(node.actions)
    assert length(node.exits) == 2
    assert !is_nil(node.router)

    json = %{}
    assert_raise ArgumentError, fn -> Node.process(json, %{}, flow) end
  end
end
