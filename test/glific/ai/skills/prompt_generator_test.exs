defmodule Glific.AI.Skills.PromptGeneratorTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Skills.PromptGenerator

  describe "identity" do
    test "name/0, description/0 and model/0" do
      assert PromptGenerator.name() == "prompt_generator"
      assert is_binary(PromptGenerator.description())
      assert PromptGenerator.model() == "anthropic:claude-sonnet-5"
    end
  end

  describe "validate_input/1" do
    test "accepts a non-empty message" do
      assert {:ok, %{"message" => "- persona: NGO\n"}} ==
               PromptGenerator.validate_input(%{"message" => "- persona: NGO\n"})
    end

    test "rejects a missing message" do
      assert {:error, _reason} = PromptGenerator.validate_input(%{})
    end

    test "rejects an empty message" do
      assert {:error, _reason} = PromptGenerator.validate_input(%{"message" => ""})
    end

    test "rejects a non-string message" do
      assert {:error, _reason} = PromptGenerator.validate_input(%{"message" => 123})
    end
  end

  describe "system_prompt/1" do
    test "is byte-identical across two calls with the same input" do
      input = %{"message" => "- persona: NGO\n- objective: help\n"}

      assert PromptGenerator.system_prompt(input) == PromptGenerator.system_prompt(input)
    end

    test "ignores input, since it is a fixed module attribute" do
      assert PromptGenerator.system_prompt(%{"message" => "one NGO's answers"}) ==
               PromptGenerator.system_prompt(%{"message" => "a completely different NGO's"})
    end

    test "documents the required output structure and few-shot vocabulary" do
      prompt = PromptGenerator.system_prompt(%{})

      assert prompt =~ "SYSTEM PROMPT"
      assert prompt =~ "persona"
      assert prompt =~ "objective"
      assert prompt =~ "fallback_answer"
      assert prompt =~ "escalation_details"
      assert prompt =~ "generated_prompt"
    end
  end

  describe "output_schema/0" do
    test "requires generated_prompt" do
      schema = PromptGenerator.output_schema()

      assert Keyword.get(schema, :generated_prompt)[:required] == true
      assert Keyword.get(schema, :generated_prompt)[:type] == :string
    end

    test "compiles as a valid req_llm keyword schema" do
      assert {:ok, _compiled} = ReqLLM.Schema.compile(PromptGenerator.output_schema())
    end
  end

  describe "no tools, no gating" do
    test "tools/0 is empty" do
      assert PromptGenerator.tools() == []
    end

    test "gate_policy/0 is :none" do
      assert PromptGenerator.gate_policy() == :none
    end
  end

  describe "budget and authorization" do
    test "max_steps/0 is 2" do
      assert PromptGenerator.max_steps() == 2
    end

    test "required_role/0 is :staff" do
      assert PromptGenerator.required_role() == :staff
    end

    test "feature_flag/0 is :is_prompt_generator_enabled" do
      assert PromptGenerator.feature_flag() == :is_prompt_generator_enabled
    end

    test "cache_ttl/0 defaults to nil" do
      assert PromptGenerator.cache_ttl() == nil
    end
  end
end
