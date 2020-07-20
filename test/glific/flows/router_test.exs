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
end
