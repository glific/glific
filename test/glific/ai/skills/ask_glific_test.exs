defmodule Glific.AI.Skills.AskGlificTest do
  use ExUnit.Case, async: true

  alias Glific.AI.KnowledgeBase
  alias Glific.AI.Skills.AskGlific
  alias Glific.AI.Tools.DescribeTable
  alias Glific.AI.Tools.QueryOrgData

  describe "identity" do
    test "name/0, description/0 and model/0" do
      assert AskGlific.name() == "ask_glific"
      assert is_binary(AskGlific.description())
      assert AskGlific.model() == "anthropic:claude-sonnet-5"
    end
  end

  describe "validate_input/1" do
    test "accepts a non-empty message" do
      assert {:ok, %{"message" => "hi"}} == AskGlific.validate_input(%{"message" => "hi"})
    end

    test "rejects a missing message" do
      assert {:error, _reason} = AskGlific.validate_input(%{})
    end

    test "rejects an empty message" do
      assert {:error, _reason} = AskGlific.validate_input(%{"message" => ""})
    end

    test "rejects a non-string message" do
      assert {:error, _reason} = AskGlific.validate_input(%{"message" => 123})
    end
  end

  describe "system_prompt/1" do
    test "is deterministic for the same input" do
      input = %{"message" => "why is this contact stuck?"}
      assert AskGlific.system_prompt(input) == AskGlific.system_prompt(input)
    end

    test "is deterministic regardless of input, since it is a fixed module attribute" do
      assert AskGlific.system_prompt(%{"message" => "one question"}) ==
               AskGlific.system_prompt(%{"message" => "a completely different question"})
    end

    test "inlines the full knowledge base content" do
      assert AskGlific.system_prompt(%{}) =~ KnowledgeBase.content()
    end

    test "instructs the model never to claim it changed anything" do
      prompt = AskGlific.system_prompt(%{})
      assert prompt =~ "read-only"
    end

    test "distinguishes a tool error from a genuinely empty result" do
      prompt = AskGlific.system_prompt(%{})
      assert prompt =~ "Unknown table"
      assert prompt =~ "zero rows"
    end
  end

  describe "tools/0" do
    test "returns exactly describe_table and query_org_data" do
      assert AskGlific.tools() == [DescribeTable, QueryOrgData]
    end
  end

  describe "budget, authorization and gating" do
    test "max_steps/0 is 8" do
      assert AskGlific.max_steps() == 8
    end

    test "gate_policy/0 is :none" do
      assert AskGlific.gate_policy() == :none
    end

    test "required_role/0 is :manager, narrower than the legacy :staff-gated askGlific mutation" do
      assert AskGlific.required_role() == :manager
    end

    test "feature_flag/0 is :is_ask_glific_enabled" do
      assert AskGlific.feature_flag() == :is_ask_glific_enabled
    end

    test "output_schema/0 is nil" do
      assert AskGlific.output_schema() == nil
    end

    test "cache_ttl/0 is \"1h\"" do
      assert AskGlific.cache_ttl() == "1h"
    end

    test "stream_thinking?/0 is false" do
      assert AskGlific.stream_thinking?() == false
    end
  end
end
