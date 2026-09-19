defmodule Glific.Flows.MessageVarParserNestedTest do
  @moduledoc "Reading keys out of a JSON flow result, gated on :nested_flow_results."

  # async: false — enabling the flag caches it in ETS, which would otherwise leak into the async
  # tests asserting the legacy substitution for the same org.
  use Glific.DataCase, async: false

  import Ecto.Query

  alias FunWithFlags.Flag
  alias FunWithFlags.Store.Cache
  alias Glific.Fixtures
  alias Glific.Flows
  alias Glific.Flows.Action
  alias Glific.Flows.FlowContext
  alias Glific.Flows.MessageVarParser
  alias Glific.Messages.Message
  alias Glific.Repo

  @json ~s({"year":"2026-27","grade":12,"program":"Tejasvi"})
  @nested ~s({"student":{"address":{"city":"Pune"},"grade":12},"subjects":["Math","Science"]})

  setup do
    organization_id = Repo.get_organization_id()
    FunWithFlags.enable(:nested_flow_results, for_actor: %{organization_id: organization_id})

    # on_exit runs after the sandbox connection is gone, so disabling would fail on its DB write —
    # cache a gate-less flag, which reads as disabled.
    on_exit(fn -> Cache.put(Flag.new(:nested_flow_results, [])) end)

    %{organization_id: organization_id}
  end

  # `value` matters: without it `parse/2`'s `@x.y` pass is never reached, and these tests pass
  # while a real flow fails.
  defp result(input), do: %{"input" => input, "value" => input, "category" => ""}

  defp json_fields, do: %{"results" => %{"json" => result(@json)}}

  test "reads a key out of a saved json object", _attrs do
    assert MessageVarParser.parse("Grade @results.json.grade", json_fields()) == "Grade 12"
  end

  test "resolves several keys in one body", _attrs do
    assert MessageVarParser.parse(
             "@results.json.program for @results.json.year",
             json_fields()
           ) == "Tejasvi for 2026-27"
  end

  test "still renders the whole value for a bare reference", _attrs do
    assert MessageVarParser.parse("Whole @results.json", json_fields()) == "Whole #{@json}"
  end

  test "an unknown nested key falls back to the stored value" do
    assert MessageVarParser.parse("@results.json.gradez", json_fields()) ==
             "#{@json}.gradez"
  end

  defp nested_fields, do: %{"results" => %{"j" => result(@nested)}}

  test "reads two keys deep" do
    assert MessageVarParser.parse("@results.j.student.grade", nested_fields()) == "12"
  end

  test "reads three keys deep" do
    assert MessageVarParser.parse("@results.j.student.address.city", nested_fields()) == "Pune"
  end

  test "renders an object reached part-way down" do
    assert MessageVarParser.parse("@results.j.student", nested_fields()) ==
             ~s({"address":{"city":"Pune"},"grade":12})
  end

  test "renders a list reached by key" do
    assert MessageVarParser.parse("@results.j.subjects", nested_fields()) == "Math, Science"
  end

  # `parse/2` matches at most five dot-separated segments, so a fourth key is never part of the
  # reference.
  test "stops at three keys, leaving a fourth unresolved" do
    assert MessageVarParser.parse("@results.j.student.address.zip", nested_fields()) ==
             ~s({"city":"Pune"}.zip)
  end

  # A webhook result is stored as a map rather than as text, so there is nothing to decode.
  test "reads a key out of a result already stored as a map" do
    fields = %{
      "results" => %{"j" => %{"input" => %{"grade" => 12}, "value" => %{"grade" => 12}}}
    }

    assert MessageVarParser.parse("@results.j.grade", fields) == "12"
  end

  test "a non-json result keeps its long-standing rendering", _attrs do
    fields = %{"results" => %{"name" => result("Amisha")}}

    assert MessageVarParser.parse("@results.name.foo", fields) == "Amisha.foo"
  end

  test "mixes nested and plain references", _attrs do
    fields = %{"results" => %{"json" => result(@json), "name" => result("Amisha")}}

    assert MessageVarParser.parse("@results.name got @results.json.grade", fields) ==
             "Amisha got 12"
  end

  test "renders a nested value that is itself structured", _attrs do
    fields = %{"results" => %{"json" => result(~s({"subjects":["Math","Science"]}))}}

    assert MessageVarParser.parse("@results.json.subjects", fields) == "Math, Science"
  end

  test "a json array falls back to the plain rendering", _attrs do
    fields = %{"results" => %{"list" => result(~s(["a","b"]))}}

    assert MessageVarParser.parse("@results.list.0", fields) == ~s(["a","b"].0)
  end

  # End to end, because testing the parser alone missed a real bug on this path.
  test "a saved json result is readable key-by-key in a later message", attrs do
    [flow | _tail] = Flows.list_flows(%{filter: attrs})
    contact = Fixtures.contact_fixture()

    {:ok, context} =
      FlowContext.create_flow_context(%{
        flow_id: flow.id,
        flow_uuid: Ecto.UUID.generate(),
        contact_id: contact.id,
        organization_id: attrs.organization_id
      })

    context = Repo.preload(context, [:flow, :contact])

    save_json = %Action{
      uuid: Ecto.UUID.generate(),
      node_uuid: "Test UUID",
      type: "set_run_result",
      name: "json",
      value: ~S(<%= "{\"year\":\"2026-27\",\"grade\":12,\"program\":\"Tejasvi\"}" %>),
      category: ""
    }

    {:ok, context, _stream} = Action.execute(save_json, context, [])

    assert context.results["json"]["input"] ==
             ~s({"year":"2026-27","grade":12,"program":"Tejasvi"})

    for {reference, expected} <- [
          {"@results.json.year", "2026-27"},
          {"@results.json.grade", "12"},
          {"@results.json.program", "Tejasvi"}
        ] do
      {:ok, _ctx, _stream} =
        Action.execute(%Action{type: "send_msg", text: reference}, context, [])

      body =
        Message
        |> where([m], m.contact_id == ^contact.id)
        |> Ecto.Query.last()
        |> Repo.one()
        |> Map.get(:body)

      assert body == expected, "#{reference} rendered #{inspect(body)}"
    end
  end
end
