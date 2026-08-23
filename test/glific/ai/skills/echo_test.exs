defmodule Glific.AI.Skills.EchoTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Skills.Echo

  describe "identity" do
    test "name/0, description/0 and model/0" do
      assert Echo.name() == "echo"
      assert is_binary(Echo.description())
      assert Echo.model() == "anthropic:claude-sonnet-5"
    end
  end

  describe "validate_input/1" do
    test "accepts a non-empty message" do
      assert {:ok, %{"message" => "hi"}} == Echo.validate_input(%{"message" => "hi"})
    end

    test "rejects a missing message" do
      assert {:error, _reason} = Echo.validate_input(%{})
    end

    test "rejects an empty message" do
      assert {:error, _reason} = Echo.validate_input(%{"message" => ""})
    end

    test "rejects a non-string message" do
      assert {:error, _reason} = Echo.validate_input(%{"message" => 123})
    end
  end

  describe "system_prompt/1" do
    test "includes the message verbatim" do
      assert Echo.system_prompt(%{"message" => "hello there"}) =~ "hello there"
    end

    test "is deterministic for the same input" do
      input = %{"message" => "hello there"}
      assert Echo.system_prompt(input) == Echo.system_prompt(input)
    end
  end

  describe "no tools, no structured output, no gating" do
    test "tools/0 is empty" do
      assert Echo.tools() == []
    end

    test "output_schema/0 is nil" do
      assert Echo.output_schema() == nil
    end

    test "gate_policy/0 is :none" do
      assert Echo.gate_policy() == :none
    end
  end
end
