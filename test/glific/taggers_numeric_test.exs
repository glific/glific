defmodule Glific.TaggersNumericTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Messages.Message,
    Taggers,
    Taggers.Numeric
  }

  # and some random ordinals, hindi numbers, and emojis
  @checker %{
    0 => "shunya",
    1 => "one",
    2 => "\u0968",
    3 => "तीन",
    4 => to_string(['\u0034', 65_039, 8419]),
    5 => "five",
    6 => "\u096C",
    7 => "saat",
    8 => "आठ",
    9 => to_string(['\u0039', 65_039, 8419]),
  }

  @checker_punct %{
    0 => "&= shunya  ",
    1 => ":.# o n e  ",
    2 => " \u0968  ",
    3 => "तीन",
    4 => to_string(['\u0034', 65_039, 8419]),
    5 => "!@#five!@#",
    6 => "%^&\u096C:;:",
    7 => "  saat%$^",
    8 => "<>,.आठ  ",
    9 => to_string(['\u0039', 65_039, 8419]),
    "23" => "23",
  }

  @invalid %{
    "आठ and more" => nil,
    "hundred" => nil,
    "some gibberirsh" => nil
  }

  test "tag maps has got at least all the number from zero to twenty" do
    numeric_map = Numeric.get_numeric_map()
    Enum.map(0..19, fn x -> assert x == Map.get(numeric_map, to_string(x)) end)

    Enum.map(
      @checker,
      fn {k, v} -> assert Map.get(numeric_map, v) == k end
    )
  end

  test "taggers string clean does a good jonb of cleaning string, but leaves unicode and hindi intact" do
    Enum.map(
      @checker,
      fn {_, v} -> assert Taggers.string_clean(v) == String.downcase(v) end
    )
  end

  test "check numeric tag body matches things in numeric map, and skips non matches" do
    numeric_map = Numeric.get_numeric_map()

    Enum.map(
      @checker,
      fn {k, v} -> assert Numeric.tag_body(v, numeric_map) == {:ok, to_string(k)} end
    )

    Enum.map(
      @invalid,
      fn {k, _} -> assert Numeric.tag_body(k, numeric_map) == :error end
    )
  end

  test "check numeric tag message matches things in numeric map, and skips non matches" do
    numeric_map = Numeric.get_numeric_map()

    Enum.map(
      @checker,
      fn {k, v} ->
        assert Numeric.tag_message(%Message{body: v}, numeric_map) == {:ok, to_string(k)}
      end
    )

    Enum.map(
      @checker_punct,
      fn {k, v} ->
        assert Numeric.tag_message(%Message{body: v}, numeric_map) == {:ok, to_string(k)}
      end
    )

    Enum.map(
      @invalid,
      fn {k, _} -> assert Numeric.tag_message(%Message{body: k}, numeric_map) == :error end
    )
  end
end
