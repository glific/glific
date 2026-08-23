defmodule Glific.AI.GradersTest do
  @moduledoc false
  use Glific.DataCase, async: false

  alias Glific.AI.Graders
  alias Glific.AI.Skills.Echo
  alias Glific.AI.Test.FixtureTool
  alias Glific.AI.Test.RuntimeSkill
  alias Glific.Fixtures
  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  describe "output_text/1" do
    test "extracts text from a plain string" do
      assert Graders.output_text("hello") == "hello"
    end

    test "extracts text from a ReqLLM.Message-shaped output" do
      message = Context.assistant("hello back")
      assert Graders.output_text(message) == "hello back"
    end
  end

  describe "contains/2" do
    test "ok when the substring is present" do
      assert Graders.contains("hello there", "hello") == :ok
    end

    test "error with a descriptive message when absent" do
      assert {:error, reason} = Graders.contains("hello there", "goodbye")
      assert reason =~ "goodbye"
    end
  end

  describe "matches/2" do
    test "ok for a matching regex" do
      assert Graders.matches("hello there", ~r/^hello/) == :ok
    end

    test "ok for a matching string pattern" do
      assert Graders.matches("hello there", "^hello") == :ok
    end

    test "error for a non-matching pattern" do
      assert {:error, _reason} = Graders.matches("hello there", ~r/goodbye/)
    end
  end

  describe "max_steps/2" do
    test "ok when steps are within budget" do
      assert Graders.max_steps(%{steps: 2}, 3) == :ok
    end

    test "error when steps exceed the budget" do
      assert {:error, reason} = Graders.max_steps(%{steps: 5}, 3)
      assert reason =~ "5"
    end
  end

  describe "tools_within_allowlist/2" do
    test "ok when every called tool is in the skill's allowlist", %{
      organization_id: organization_id
    } do
      conversation =
        Fixtures.ai_conversation_fixture(%{
          organization_id: organization_id,
          skill: "runtime_fixture"
        })

      tool_call = %ToolCall{
        id: "call_1",
        type: "function",
        function: %{name: FixtureTool.name(), arguments: Jason.encode!(%{"query" => "flows"})}
      }

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :assistant,
        reqllm_message: Context.assistant("", tool_calls: [tool_call])
      })

      assert Graders.tools_within_allowlist(conversation, RuntimeSkill) == :ok
    end

    test "error when a called tool is outside the allowlist", %{organization_id: organization_id} do
      conversation =
        Fixtures.ai_conversation_fixture(%{organization_id: organization_id, skill: "echo"})

      tool_call = %ToolCall{
        id: "call_1",
        type: "function",
        function: %{name: "not_a_real_tool", arguments: "{}"}
      }

      Fixtures.ai_message_fixture(%{
        conversation: conversation,
        seq: 1,
        role: :assistant,
        reqllm_message: Context.assistant("", tool_calls: [tool_call])
      })

      assert {:error, reason} = Graders.tools_within_allowlist(conversation, Echo)
      assert reason =~ "not_a_real_tool"
    end
  end

  describe "validates_against_schema/2" do
    test "a nil schema trivially passes" do
      assert Graders.validates_against_schema(%{"anything" => 1}, nil) == :ok
    end

    test "ok when the output satisfies the schema" do
      schema = [answer: [type: :string, required: true]]
      assert Graders.validates_against_schema(%{"answer" => "42"}, schema) == :ok
    end

    test "error when the output violates the schema" do
      schema = [answer: [type: :string, required: true]]
      assert {:error, _reason} = Graders.validates_against_schema(%{}, schema)
    end
  end

  describe "template_variables_preserved/2" do
    test "ok when the token set, order, and count match" do
      before_text = "Hi {{1}}, your code is {{2}}."
      after_text = "Hello {{1}}, code: {{2}}."
      assert Graders.template_variables_preserved(before_text, after_text) == :ok
    end

    test "error when a token is dropped" do
      before_text = "Hi {{1}}, code {{2}}."
      after_text = "Hi {{1}}."
      assert {:error, _reason} = Graders.template_variables_preserved(before_text, after_text)
    end

    test "error when tokens are reordered" do
      before_text = "{{1}} and {{2}}"
      after_text = "{{2}} and {{1}}"
      assert {:error, _reason} = Graders.template_variables_preserved(before_text, after_text)
    end
  end

  describe "template_length_within_limit/1" do
    test "ok within the limit" do
      assert Graders.template_length_within_limit(%{body: "short body"}) == :ok
    end

    test "sums body, every button's text, and the footer" do
      template = %{
        body: String.duplicate("a", 1000),
        buttons: [String.duplicate("b", 20)],
        footer: String.duplicate("c", 10)
      }

      assert {:error, reason} = Graders.template_length_within_limit(template)
      assert reason =~ "1030"
    end
  end

  describe "judge/3 — live-tier gate" do
    setup do
      previous = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      on_exit(fn ->
        if previous,
          do: System.put_env("ANTHROPIC_API_KEY", previous),
          else: System.delete_env("ANTHROPIC_API_KEY")
      end)

      :ok
    end

    test "refuses without a live provider credential in the environment" do
      assert {:error, :missing_live_credentials} = Graders.judge("output", "rubric", 0.5)
    end
  end
end
