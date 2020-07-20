defmodule Glific.Flows.CaseTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Case

  test "process extracts the right values from json" do
    json = %{
      "uuid" => "UUID 1",
      "type" => "some type",
      "arguments" => [1, 2, 3],
      "category_uuid" => "Cat UUID"
    }

    {case, uuid_map} = Case.process(json, %{"Cat UUID" => {:category, nil}})

    assert case.uuid == "UUID 1"
    assert case.category_uuid == "Cat UUID"
    assert case.arguments == [1, 2, 3]
    assert uuid_map[case.uuid] == {:case, case}

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "some type"}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end

    json = %{"arguments" => [1, 2, 3], "category_uuid" => "Cat UUID"}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end

    json = %{}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end
  end
end
