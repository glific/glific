defmodule Glific.AI.LangfuseTest do
  use Glific.DataCase

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Langfuse,
    AI.Message,
    Fixtures,
    Repo
  }

  setup do
    user = Fixtures.user_fixture(%{organization_id: 1})

    conversation =
      Repo.insert!(%Conversation{
        title: "why did the reminder not go out?",
        kind: :chat,
        user_id: user.id,
        organization_id: 1
      })

    message =
      Repo.insert!(%Message{
        skill: "knowledge",
        status: :succeeded,
        model: "anthropic:claude-haiku-4-5",
        input_tokens: 900,
        output_tokens: 120,
        cost: Decimal.new("0.004321"),
        conversation_id: conversation.id,
        user_id: user.id,
        organization_id: 1
      })

    append = fn step, type, content, data, tool_call_id ->
      Repo.insert!(%Event{
        message_id: message.id,
        conversation_id: conversation.id,
        organization_id: 1,
        step: step,
        type: type,
        content: content,
        data: data,
        tool_call_id: tool_call_id
      })
    end

    append.(1, :user, "why did the reminder not go out?", %{}, nil)
    append.(2, :routing, "knowledge", %{"input_tokens" => 212, "output_tokens" => 4}, nil)

    append.(
      3,
      :tool_call,
      "get_contact",
      %{"arguments" => %{"phone" => "919000000001"}, "input_tokens" => 800, "cost" => 0.003},
      "toolu_1"
    )

    append.(4, :tool_result, nil, %{"output" => ~s({"optin_status":false})}, "toolu_1")

    append.(
      5,
      :assistant,
      "She opted out five days ago.",
      %{"input_tokens" => 1100, "output_tokens" => 60, "cost" => 0.0013},
      nil
    )

    %{message: message, conversation: conversation, user: user}
  end

  defp spans(message_id) do
    assert {:ok, payload} = Langfuse.payload(message_id)
    [%{scopeSpans: [%{spans: spans}]}] = payload.resourceSpans
    spans
  end

  defp attribute(span, key) do
    Enum.find_value(span.attributes, fn
      %{key: ^key, value: %{stringValue: value}} -> value
      %{key: ^key, value: %{intValue: value}} -> value
      %{key: ^key, value: %{doubleValue: value}} -> value
      _other -> nil
    end)
  end

  defp named(spans, name), do: Enum.find(spans, &(&1.name == name))

  describe "the payload" do
    test "hangs every observation off one trace", %{message: message} do
      spans = spans(message.id)

      assert [trace_id] = spans |> Enum.map(& &1.traceId) |> Enum.uniq()
      assert String.length(trace_id) == 32
      assert Enum.all?(spans, &(String.length(&1.spanId) == 16))

      root = named(spans, "answer-question")
      refute Map.has_key?(root, :parentSpanId)
      children = Enum.reject(spans, &(&1.spanId == root.spanId))
      assert Enum.all?(children, &(&1.parentSpanId == root.spanId))
    end

    test "carries the session and user so Langfuse can group conversations", %{
      message: message,
      conversation: conversation,
      user: user
    } do
      root = message.id |> spans() |> named("answer-question")

      assert attribute(root, "session.id") == to_string(conversation.id)
      assert attribute(root, "user.id") == to_string(user.id)
      assert attribute(root, "langfuse.trace.name") == "answer-question"
      assert attribute(root, "gen_ai.prompt") == "why did the reminder not go out?"
      assert attribute(root, "gen_ai.completion") == "She opted out five days ago."
    end

    test "reports the question's cost as a number, not a Decimal", %{message: message} do
      root = message.id |> spans() |> named("answer-question")

      assert attribute(root, "gen_ai.usage.cost") == 0.004321
      assert attribute(root, "gen_ai.usage.input_tokens") == "900"
    end

    test "pairs a tool call with its result in one span", %{message: message} do
      tool = message.id |> spans() |> named("get_contact")

      assert attribute(tool, "langfuse.observation.type") == "tool"
      assert attribute(tool, "langfuse.observation.input") =~ "phone"
      assert attribute(tool, "langfuse.observation.output") =~ "optin_status"
      assert tool.endTimeUnixNano >= tool.startTimeUnixNano
    end

    test "attributes tokens to the turn that spent them", %{message: message} do
      spans = spans(message.id)

      assert named(spans, "classify-intent") |> attribute("gen_ai.usage.input_tokens") == "212"
      assert named(spans, "generate-answer") |> attribute("gen_ai.usage.output_tokens") == "60"
      assert named(spans, "generate-answer") |> attribute("gen_ai.usage.cost") == 0.0013
    end

    test "drops attributes it has no value for", %{message: message} do
      root = message.id |> spans() |> named("answer-question")

      refute Enum.any?(root.attributes, fn %{value: value} -> value == %{stringValue: nil} end)
    end

    test "gives the same message the same ids every time", %{message: message} do
      assert Enum.map(spans(message.id), & &1.spanId) == Enum.map(spans(message.id), & &1.spanId)
    end
  end

  describe "best practices" do
    test "records the tool-requesting turn as its own generation", %{message: message} do
      # Without this, only the routing call and the final answer would be
      # visible and the turn that actually spent 800 tokens would not be.
      turn = message.id |> spans() |> named("generate-tool-calls")

      assert attribute(turn, "langfuse.observation.type") == "generation"
      assert attribute(turn, "gen_ai.usage.input_tokens") == "800"
      assert attribute(turn, "gen_ai.completion") == "get_contact"
    end

    test "names observations after the action, not the run", %{message: message} do
      names = message.id |> spans() |> Enum.map(& &1.name)

      assert "answer-question" in names
      assert "classify-intent" in names
      assert "generate-tool-calls" in names
      assert "generate-answer" in names
      refute Enum.any?(names, &String.contains?(&1, to_string(message.id)))
      refute Enum.any?(names, &String.contains?(&1, "claude"))
    end

    test "tags the trace so it can be filtered by skill and organisation", %{message: message} do
      root = message.id |> spans() |> named("answer-question")

      tags =
        Enum.find_value(root.attributes, fn
          %{key: "langfuse.trace.tags", value: %{arrayValue: %{values: values}}} ->
            Enum.map(values, & &1.stringValue)

          _other ->
            nil
        end)

      assert "ask-glific" in tags
      assert "skill:knowledge" in tags
      assert "org:1" in tags
    end

    test "marks the environment so test traces stay out of real dashboards", %{
      message: message
    } do
      root = message.id |> spans() |> named("answer-question")
      assert attribute(root, "langfuse.environment") == "test"
    end
  end

  describe "masking" do
    test "redacts phone numbers and emails" do
      assert Langfuse.mask("call 919000000001 or asha@example.org") ==
               "call [phone] or [email]"
    end

    test "leaves the rest of the sentence alone" do
      assert Langfuse.mask("her checkup is on Monday") == "her checkup is on Monday"
    end

    test "redacts the phone number a tool was called with", %{message: message} do
      tool = message.id |> spans() |> named("get_contact")

      assert attribute(tool, "langfuse.observation.input") =~ "[phone]"
      refute attribute(tool, "langfuse.observation.input") =~ "919000000001"
    end
  end

  describe "scores" do
    test "does nothing for an event nobody rated", %{message: message} do
      event = Repo.get_by!(Event, message_id: message.id, type: :user)
      assert Langfuse.score(event) == :ok
    end
  end
end
