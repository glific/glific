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

    # dont send a category UUID and it should raise an error
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end

    # ensure that not sending either of the required fields, raises an error
    json = %{"uuid" => "UUID 1", "type" => "some type"}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end

    json = %{"arguments" => [1, 2, 3], "category_uuid" => "Cat UUID"}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end

    json = %{}
    assert_raise ArgumentError, fn -> Case.process(json, %{}) end
  end

  test "test the execute function for has_any_word" do
    c = %Case{type: "has_any_word", arguments: ["first", "second", "third"]}

    assert Case.execute(c, nil, "first") == true
    assert Case.execute(c, nil, "second") == true
    assert Case.execute(c, nil, "fourth") == false
    assert Case.execute(c, nil, "") == false

    c = %Case{type: "has_any_word", arguments: []}
    assert Case.execute(c, nil, "first") == false
    assert Case.execute(c, nil, "second") == false
    assert Case.execute(c, nil, "fourth") == false
    assert Case.execute(c, nil, "") == false
  end

  test "test the execute function for has_number_eq" do
    c = %Case{type: "has_number_eq", arguments: ["1", "2"]}

    assert Case.execute(c, nil, "1") == true
    assert Case.execute(c, nil, "second") == false
    assert Case.execute(c, nil, "4") == false
    assert Case.execute(c, nil, "") == false

    c = %Case{type: "has_number_eq", arguments: ["23"]}
    assert Case.execute(c, nil, "23") == true
    assert Case.execute(c, nil, "1") == false
  end

  test "test the execute function for has_number_between" do
    c = %Case{type: "has_number_between", arguments: ["1", "10"]}

    assert Case.execute(c, nil, "1") == true
    assert Case.execute(c, nil, "second") == false
    assert Case.execute(c, nil, "4") == true
    assert Case.execute(c, nil, "") == false
    assert Case.execute(c, nil, "10") == true
    assert Case.execute(c, nil, "23") == false
    assert Case.execute(c, nil, "-42") == false
  end

  test "test the execute function for has_only_phrase or has_only_text" do
    c = %Case{type: "has_only_phrase", arguments: ["only phrase"]}
    assert Case.execute(c, nil, "only phrase") == true
    assert Case.execute(c, nil, "only phrase 1") == false
    assert Case.execute(c, nil, "") == false

    c = %Case{type: "has_only_text", arguments: ["only phrase"]}
    assert Case.execute(c, nil, "only phrase") == true
    assert Case.execute(c, nil, "only phrase 1") == false
    assert Case.execute(c, nil, "") == false
  end

  test "test exceptions" do
    c = %Case{type: "no_such_function", arguments: ["only phrase"]}
    assert_raise UndefinedFunctionError, fn -> Case.execute(c, nil, "only phrase 1") end
  end
end
