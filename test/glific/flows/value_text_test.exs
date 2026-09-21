defmodule Glific.Flows.ValueTextTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.ValueText

  describe "to_text/1 — scalars" do
    test "passes a binary through untouched" do
      assert ValueText.to_text("Pune") == "Pune"
    end

    test "renders numbers, booleans and nil" do
      assert ValueText.to_text(42) == "42"
      assert ValueText.to_text(3.5) == "3.5"
      assert ValueText.to_text(true) == "true"
      assert ValueText.to_text(nil) == ""
    end
  end

  describe "to_text/1 — structs keep their String.Chars rendering" do
    test "a Date renders as an ISO date" do
      assert ValueText.to_text(~D[2026-09-17]) == "2026-09-17"
    end

    test "a DateTime renders as a datetime string" do
      assert ValueText.to_text(~U[2026-09-17 06:20:45Z]) == "2026-09-17 06:20:45Z"
    end

    test "a Decimal renders as a number" do
      assert ValueText.to_text(Decimal.new("9.5")) == "9.5"
    end
  end

  describe "to_text/1 — maps render as JSON" do
    test "a flat map" do
      assert ValueText.to_text(%{"city" => "Pune"}) == ~s({"city":"Pune"})
    end

    test "a nested map" do
      assert ValueText.to_text(%{"a" => %{"b" => 1}}) == ~s({"a":{"b":1}})
    end

    test "an empty map" do
      assert ValueText.to_text(%{}) == "{}"
    end

    # Contained by isolated/1 in Expression, so the author sees "Invalid Code"
    # rather than inspect output leaking into a message.
    test "a map JSON cannot represent raises instead of rendering internals" do
      assert_raise Protocol.UndefinedError, fn -> ValueText.to_text(%{"port" => {1, 2}}) end
    end
  end

  describe "to_text/1 — lists join their rendered elements" do
    # to_string/1 treats an integer list as a charlist, so `[1, 2, 3]` used to
    # render as the raw bytes <<1, 2, 3>>.
    test "a list of integers is not treated as a charlist" do
      assert ValueText.to_text([1, 2, 3]) == "1, 2, 3"
    end

    # to_string/1 concatenates a list of binaries with no separator, so
    # ["Math", "Science"] used to render as "MathScience".
    test "a list of strings is comma separated" do
      assert ValueText.to_text(["Math", "Science", "Art"]) == "Math, Science, Art"
    end

    test "a list of maps renders each element as JSON" do
      assert ValueText.to_text([%{"a" => 1}, %{"b" => 2}]) == ~s({"a":1}, {"b":2})
    end

    test "an empty list renders as an empty string" do
      assert ValueText.to_text([]) == ""
    end
  end
end
