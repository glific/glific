defmodule Glific.Flows.CategoryTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.{
    Category,
    Router
  }

  test "process extracts the right values from json" do
    router = %Router{uuid: "Test UUID"}
    json = %{"uuid" => "UUID 1", "exit_uuid" => "UUID 2", "name" => "Default Category"}

    {category, uuid_map} = Category.process(json, %{}, router)

    assert category.uuid == "UUID 1"
    assert category.exit_uuid == "UUID 2"
    assert category.router_uuid == router.uuid
    assert category.name == "Default Category"
    assert uuid_map[category.uuid] == {:category, category}

    # ensure that not sending the required fields, raises an error
    json = %{"uuid" => "UUID 1", "exit_uuid" => "UUID 2"}
    assert_raise ArgumentError, fn -> Category.process(json, %{}, router) end

    json = %{"exit_uuid" => "UUID 2", "name" => "Default Category"}
    assert_raise ArgumentError, fn -> Category.process(json, %{}, router) end

    json = %{}
    assert_raise ArgumentError, fn -> Category.process(json, %{}, router) end
  end
end
