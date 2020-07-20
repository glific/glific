defmodule Glific.Flows.RouterTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
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

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "some type"}
    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    json = %{"arguments" => [1, 2, 3], "category_uuid" => "Cat UUID"}
    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end

    json = %{}
    assert_raise ArgumentError, fn -> Router.process(json, %{}, node) end
  end
end
