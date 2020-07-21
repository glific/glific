defmodule Glific.Flows.RouterTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Flow,
    FlowContext,
    Node,
    Router
  }

  test "process extracts the right values from json" do
    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
        %{"uuid" => "Default Cat UUID", "exit_uuid" => "UUID Cat 2", "name" => "Default Category"}
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

    node = %Node{uuid: "Node UUID"}
    {router, _uuid_map} = Router.process(json, %{}, node)

    assert router.default_category_uuid == "Default Cat UUID"
    assert router.result_name == "Language"
    assert router.type == "switch"
    assert length(router.categories) == 2
    assert length(router.cases) == 1

    # ensure that not sending either of the required fields, raises an error
    # no categories
    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "result_name" => "Language",
      "cases" => [
        %{
          "uuid" => "UUID 1",
          "type" => "some type",
          "arguments" => [1, 2, 3],
          "category_uuid" => "UUID Cat 1"
        }
      ]
    }

    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    # no type
    json = %{
      "operand" => "@input.text",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => "UUID Cat 2", "name" => "Category Uno"},
        %{"uuid" => "Default Cat UUID", "exit_uuid" => "UUID Cat 2", "name" => "Default Category"}
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

    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end
  end

  test "router execution when no messages are sent" do
    result = Router.execute(nil, nil, [])

    assert elem(result, 0) == :ok
    assert elem(result, 1) == nil
    assert elem(result, 2) == []
  end

  test "router execution with type not equal to switch" do
    router = %Router{type: "No type"}

    assert_raise UndefinedFunctionError, fn -> Router.execute(router, nil, ["Random Input"]) end
  end

  test "router with switch and one case, category" do
    flow = %Flow{uuid: "Flow UUID 1"}
    uuid_map = %{}

    json = %{
      "uuid" => "Node UUID",
      "actions" => [],
      "exits" => [
        %{"uuid" => "Exit UUID", "destination_uuid" => nil}
      ]
    }

    {node, uuid_map} = Node.process(json, uuid_map, flow)

    json = %{
      "operand" => "@input.text",
      "type" => "switch",
      "default_category_uuid" => "Default Cat UUID",
      "result_name" => "Language",
      "categories" => [
        %{"uuid" => "UUID Cat 1", "exit_uuid" => "Exit UUID", "name" => "Category Uno"},
        %{
          "uuid" => "Default Cat UUID",
          "exit_uuid" => "Exit UUID",
          "name" => "Default Category"
        }
      ],
      "cases" => [
        %{
          "uuid" => "UUID 1",
          "type" => "has_number_eq",
          "arguments" => ["23"],
          "category_uuid" => "UUID Cat 1"
        }
      ]
    }

    {router, uuid_map} = Router.process(json, uuid_map, node)

    # create a simple flow context
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: 1,
        flow_id: 1,
        uuid_map: uuid_map
      })

    result = Router.execute(router, context, ["23"])

    # we send it to a null node. lets ensure we get the right values
    assert elem(result, 0) == :ok
    assert elem(result, 1) == nil
    assert elem(result, 2) == []

    # need to recreate the context, since we blew it away when the previous
    # flow finished
    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: 1,
        flow_id: 1,
        uuid_map: uuid_map
      })

    # lets ensure the default category route also works
    result = Router.execute(router, context, ["123"])
    assert elem(result, 0) == :ok
    assert elem(result, 1) == nil
    assert elem(result, 2) == []
  end
end
