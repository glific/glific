defmodule Glific.GlificTest do
  use Glific.DataCase, async: true

  @checker %{
    "123" => {:ok, 123},
    123 => {:ok, 123},
    "1234.4" => :error,
    "This is not a number" => :error,
    "123456" => {:ok, 123_456},
    123_456 => {:ok, 123_456}
  }

  test "parse maybe integer" do
    Enum.map(
      @checker,
      fn {k, v} -> assert Glific.parse_maybe_integer(k) == v end
    )
  end
end
