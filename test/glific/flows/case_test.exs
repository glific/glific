defmodule Glific.Flows.CaseTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Fixtures,
    Flows.Case,
    Messages
  }

  test "process extracts the right values from json" do
    json = %{
      "uuid" => "UUID 1",
      "type" => "has_multiple",
      "arguments" => ["1, 2, 3"],
      "category_uuid" => "Cat UUID"
    }

    {case, uuid_map} = Case.process(json, %{"Cat UUID" => {:category, nil}})

    assert case.uuid == "UUID 1"
    assert case.category_uuid == "Cat UUID"
    assert case.arguments == ["1, 2, 3"]
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
    args = ["first second third"]
    parsed_args = args |> hd() |> Glific.make_set()

    c = %Case{type: "has_any_word", arguments: args, parsed_arguments: parsed_args}

    assert wrap_execute(c, nil, "First") == true
    assert wrap_execute(c, nil, "second ") == true
    assert wrap_execute(c, nil, "fourth") == false

    args = ["none of these"]
    parsed_args = args |> hd() |> Glific.make_set()

    c = %Case{type: "has_any_word", arguments: args, parsed_arguments: parsed_args}
    assert wrap_execute(c, nil, "first") == false
    assert wrap_execute(c, nil, "second") == false
    assert wrap_execute(c, nil, "fourth") == false
  end

  test "test the execute function for has_phrase" do
    args = ["This is a green apple"]

    c = %Case{type: "has_phrase", arguments: args}

    assert wrap_execute(c, nil, "This is a green") == true
    assert wrap_execute(c, nil, "This is a red apple ") == false
    assert wrap_execute(c, nil, "apple") == true
  end

  test "test the execute function for has_multiple" do
    args = ["first second third"]
    parsed_args = args |> hd() |> Glific.make_set()

    c = %Case{type: "has_multiple", arguments: args, parsed_arguments: parsed_args}

    assert wrap_execute(c, nil, "first") == true
    assert wrap_execute(c, nil, "second ") == true
    assert wrap_execute(c, nil, "second third first") == true
    assert wrap_execute(c, nil, "second third") == true
    assert wrap_execute(c, nil, "fourth") == false
    assert wrap_execute(c, nil, "first third fourth") == false

    c = %Case{type: "has_any_word", arguments: args, parsed_arguments: parsed_args}
    assert wrap_execute(c, nil, "first") == true
    assert wrap_execute(c, nil, "first second") == true
    assert wrap_execute(c, nil, "first second third") == true
    assert wrap_execute(c, nil, "first second third forth") == true
    assert wrap_execute(c, nil, "fifth") == false
    assert wrap_execute(c, nil, "fifth first") == true
  end

  test "test the execute function for has_number_eq" do
    c = %Case{type: "has_number_eq", arguments: ["1", "2"]}

    assert wrap_execute(c, nil, "1") == true
    assert wrap_execute(c, nil, "second") == false
    assert wrap_execute(c, nil, "4") == false
    assert wrap_execute(c, nil, "") == false

    c = %Case{type: "has_number_eq", arguments: ["23"]}
    assert wrap_execute(c, nil, "23") == true
    assert wrap_execute(c, nil, "1") == false
  end

  test "test the execute function for has_number" do
    c = %Case{type: "has_number"}

    assert wrap_execute(c, nil, "1221") == true
    assert wrap_execute(c, nil, "second") == false
    assert wrap_execute(c, nil, "4") == true
    assert wrap_execute(c, nil, "") == false
  end

  test "test the execute function for has_all_words" do
    args = ["one, two"]
    parsed_args = args |> hd() |> Glific.make_set()
    c = %Case{type: "has_all_words", arguments: ["one, two"], parsed_arguments: parsed_args}

    assert wrap_execute(c, nil, "one1") == false
    assert wrap_execute(c, nil, "one, two") == true
    assert wrap_execute(c, nil, "two one") == true
    assert wrap_execute(c, nil, "one two three") == true
    assert wrap_execute(c, nil, "one") == false
  end

  test "test the execute function for has_location" do
    c = %Case{type: "has_location"}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == true
  end

  test "test the execute function for has_phone" do
    c = %Case{type: "has_phone"}
    assert wrap_execute(c, nil, nil, [{:body, "919417443994"}]) == true
    assert wrap_execute(c, nil, nil, [{:body, "917443994"}]) == false
    assert wrap_execute(c, nil, nil, [{:body, "invalid_phone"}]) == false
  end

  test "test the execute function for has_email" do
    c = %Case{type: "has_email"}
    assert wrap_execute(c, nil, nil, [{:body, "abc@glific.com"}]) == true
    assert wrap_execute(c, nil, nil, [{:body, "acs.@ge.123"}]) == false
    assert wrap_execute(c, nil, nil, [{:body, "invalid_email"}]) == false
  end

  defp wrap_execute(c, context, body) do
    message = Messages.create_temp_message(Fixtures.get_org_id(), body)
    Case.execute(c, context, message)
  end

  defp wrap_execute(c, context, body, opts) do
    message = Messages.create_temp_message(Fixtures.get_org_id(), body, opts)
    Case.execute(c, context, message)
  end

  test "test the execute function for has_number_between" do
    c = %Case{type: "has_number_between", arguments: ["1", "10"]}

    assert wrap_execute(c, nil, "1") == true
    assert wrap_execute(c, nil, "2@") == false
    assert wrap_execute(c, nil, "2.5") == false
    assert wrap_execute(c, nil, "second") == false
    assert wrap_execute(c, nil, "4") == true
    assert wrap_execute(c, nil, "") == false
    assert wrap_execute(c, nil, "10") == true
    assert wrap_execute(c, nil, "23") == false
    assert wrap_execute(c, nil, "-42") == false
  end

  test "test the execute function for has_media" do
    c = %Case{type: "has_media", arguments: []}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :text}]) == false
    assert wrap_execute(c, nil, nil, [{:type, nil}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :image}]) == true
    assert wrap_execute(c, nil, nil, [{:type, :audio}]) == true
    assert wrap_execute(c, nil, nil, [{:type, :video}]) == true
  end

  test "test the execute function for has_image" do
    c = %Case{type: "has_image", arguments: []}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :text}]) == false
    assert wrap_execute(c, nil, nil, [{:type, nil}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :image}]) == true
    assert wrap_execute(c, nil, nil, [{:type, :audio}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :video}]) == false
  end

  test "test the execute function for has_audio" do
    c = %Case{type: "has_audio", arguments: []}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :text}]) == false
    assert wrap_execute(c, nil, nil, [{:type, nil}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :image}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :audio}]) == true
    assert wrap_execute(c, nil, nil, [{:type, :video}]) == false
  end

  test "test the execute function for has_file" do
    c = %Case{type: "has_file", arguments: []}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :text}]) == false
    assert wrap_execute(c, nil, nil, [{:type, nil}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :image}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :document}]) == true
    assert wrap_execute(c, nil, nil, [{:type, :audio}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :video}]) == false
  end

  test "test the execute function for has_video" do
    c = %Case{type: "has_video", arguments: []}
    assert wrap_execute(c, nil, nil, [{:type, :location}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :text}]) == false
    assert wrap_execute(c, nil, nil, [{:type, nil}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :image}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :audio}]) == false
    assert wrap_execute(c, nil, nil, [{:type, :video}]) == true
  end

  test "test the execute function for has_only_phrase or has_only_text" do
    c = %Case{type: "has_only_phrase", arguments: ["only phrase"]}
    assert wrap_execute(c, nil, "only phrase") == true
    assert wrap_execute(c, nil, "only phrase 1") == false
    assert wrap_execute(c, nil, "") == false

    c = %Case{type: "has_only_text", arguments: ["only phrase"]}
    assert wrap_execute(c, nil, "only phrase") == true
    assert wrap_execute(c, nil, "only phrase 1") == false
    assert wrap_execute(c, nil, "") == false
  end

  test "test the execute function for has_groups" do
    c = %Case{type: "has_group", arguments: ["3", "Default groups"]}
    assert wrap_execute(c, nil, "", extra: %{contact_groups: ["Default groups"]}) == true

    assert wrap_execute(c, nil, "", extra: %{contact_groups: []}) == false
  end

  test "test exceptions" do
    c = %Case{type: "no_such_function", arguments: ["only phrase"]}
    assert_raise UndefinedFunctionError, fn -> wrap_execute(c, nil, "only phrase 1") end
  end
end
