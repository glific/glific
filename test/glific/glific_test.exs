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

  test "make list" do
    valid = MapSet.new(["a", "b", "c"])
    assert Glific.make_set("a b c") == valid
    assert Glific.make_set("a,b;c") == valid
    assert Glific.make_set("a,b;c") == valid
    assert Glific.make_set("a,\tb\n;c") == valid
    assert Glific.make_set("a,     b;     c") == valid
  end

  test "mask phone number" do
    # when number is string
    phone = "919876543210_2"
    assert Glific.mask_phone_number(phone) == "919876543***_*"

    # when number is integer
    phone = 9_198_765_432_102
    assert Glific.mask_phone_number(phone) == "91987654*****"
  end

  test "get_tesla_retry_middleware/1" do
    assert [{_h, opts}] = Glific.get_tesla_retry_middleware()
    assert opts[:delay] == 500

    assert opts[:max_retries] == 2

    # when adding custom config
    assert [{_h, opts}] = Glific.get_tesla_retry_middleware(%{max_retries: 5})
    assert opts[:delay] == 500

    assert opts[:max_retries] == 5
  end
end
