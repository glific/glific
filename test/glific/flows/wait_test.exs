defmodule Glific.Flows.WaitTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.{Flow, Wait}

  describe "validate/3 timeout expression guard" do
    test "flags a dynamic timeout expression carrying disallowed code" do
      wait = %Wait{type: "msg", seconds: nil, expression: "<%= System.cmd(\"id\", []) %>"}

      errors = Wait.validate(wait, [], %Flow{})

      assert Enum.any?(errors, fn
               {EEx, message, "Critical"} -> message =~ "unsupported expression"
               _ -> false
             end)
    end

    test "allows a safe dynamic timeout expression" do
      wait = %Wait{type: "msg", seconds: nil, expression: "<%= 5 * 60 %>"}

      assert Wait.validate(wait, [], %Flow{}) == []
    end

    test "is a no-op when there is no expression" do
      wait = %Wait{type: "msg", seconds: 60, expression: nil}

      assert Wait.validate(wait, [], %Flow{}) == []
    end
  end
end
