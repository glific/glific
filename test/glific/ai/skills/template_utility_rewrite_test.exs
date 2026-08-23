defmodule Glific.AI.Skills.TemplateUtilityRewriteTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Skills.TemplateUtilityRewrite

  describe "identity" do
    test "name/0, description/0 and model/0" do
      assert TemplateUtilityRewrite.name() == "template_utility_rewrite"
      assert is_binary(TemplateUtilityRewrite.description())
      assert TemplateUtilityRewrite.model() == "anthropic:claude-sonnet-5"
    end
  end

  describe "validate_input/1" do
    test "accepts a non-empty message" do
      assert {:ok, %{"message" => "hi"}} ==
               TemplateUtilityRewrite.validate_input(%{"message" => "hi"})
    end

    test "rejects a missing message" do
      assert {:error, _reason} = TemplateUtilityRewrite.validate_input(%{})
    end

    test "rejects an empty message" do
      assert {:error, _reason} = TemplateUtilityRewrite.validate_input(%{"message" => ""})
    end

    test "rejects a non-string message" do
      assert {:error, _reason} = TemplateUtilityRewrite.validate_input(%{"message" => 123})
    end
  end

  describe "system_prompt/1" do
    test "is deterministic for the same input" do
      input = %{"message" => "LABEL: (none)\n\nBODY:\nHello {{1}}"}

      assert TemplateUtilityRewrite.system_prompt(input) ==
               TemplateUtilityRewrite.system_prompt(input)
    end

    test "is deterministic regardless of input, since it is a fixed module attribute" do
      assert TemplateUtilityRewrite.system_prompt(%{"message" => "one draft"}) ==
               TemplateUtilityRewrite.system_prompt(%{
                 "message" => "a completely different draft"
               })
    end

    test "documents the UTILITY vs MARKETING distinction" do
      prompt = TemplateUtilityRewrite.system_prompt(%{})
      assert prompt =~ "UTILITY"
      assert prompt =~ "MARKETING"
    end

    test "documents the draft's input layout" do
      prompt = TemplateUtilityRewrite.system_prompt(%{})
      assert prompt =~ "LABEL:"
      assert prompt =~ "BODY:"
      assert prompt =~ "FOOTER:"
      assert prompt =~ "BUTTONS:"
    end
  end

  describe "output_schema/0" do
    test "requires body, suggested_category and changes" do
      schema = TemplateUtilityRewrite.output_schema()

      assert Keyword.get(schema, :body)[:required] == true
      assert Keyword.get(schema, :suggested_category)[:required] == true
      assert Keyword.get(schema, :changes)[:required] == true
    end

    test "compiles as a valid req_llm keyword schema" do
      assert {:ok, _compiled} = ReqLLM.Schema.compile(TemplateUtilityRewrite.output_schema())
    end
  end

  describe "no tools, no gating" do
    test "tools/0 is empty" do
      assert TemplateUtilityRewrite.tools() == []
    end

    test "gate_policy/0 is :none" do
      assert TemplateUtilityRewrite.gate_policy() == :none
    end
  end

  describe "budget and authorization" do
    test "max_steps/0 is 2" do
      assert TemplateUtilityRewrite.max_steps() == 2
    end

    test "required_role/0 is :staff" do
      assert TemplateUtilityRewrite.required_role() == :staff
    end

    test "feature_flag/0 is a distinct atom" do
      assert TemplateUtilityRewrite.feature_flag() == :is_template_utility_rewrite_enabled
    end

    test "cache_ttl/0 defaults to nil" do
      assert TemplateUtilityRewrite.cache_ttl() == nil
    end
  end
end
