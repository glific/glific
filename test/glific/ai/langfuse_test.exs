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

  describe "a turn that called tools in parallel" do
    setup %{message: message, conversation: conversation} do
      base = DateTime.utc_now()

      insert = fn step, type, data, tool_call_id, content, at ->
        Repo.insert!(%Event{
          message_id: message.id,
          conversation_id: conversation.id,
          organization_id: 1,
          step: step,
          type: type,
          content: content,
          data: data,
          tool_call_id: tool_call_id,
          inserted_at: at,
          updated_at: at
        })
      end

      insert.(6, :tool_call, %{"arguments" => %{}}, "toolu_fast", "list_flows", base)
      insert.(7, :tool_call, %{"arguments" => %{}}, "toolu_slow", "list_messages", base)

      # Both rows carry the same `inserted_at`: `Enum.zip/2` in run_tools/5 is
      # eager, so nothing is written until the slow tool returns. Only
      # `finished_at` distinguishes them, and it disagrees with the row time.
      written = DateTime.add(base, 4, :second)

      insert.(
        8,
        :tool_result,
        %{"output" => "[]", "finished_at" => DateTime.to_iso8601(DateTime.add(base, 1, :second))},
        "toolu_fast",
        nil,
        written
      )

      insert.(
        9,
        :tool_result,
        %{"output" => "[]", "finished_at" => DateTime.to_iso8601(written)},
        "toolu_slow",
        nil,
        written
      )

      :ok
    end

    test "each span ends when its own tool finished", %{message: message} do
      spans = spans(message.id)

      duration = fn name ->
        span = named(spans, name)
        String.to_integer(span.endTimeUnixNano) - String.to_integer(span.startTimeUnixNano)
      end

      assert duration.("list_flows") < duration.("list_messages"),
             "the quick tool was given the slow tool's duration"
    end

    test "a result with no recorded finish still gets an end", %{message: message} do
      # Anything written before this field existed, and the timeout path.
      assert spans(message.id) |> named("get_contact") |> Map.fetch!(:endTimeUnixNano) != nil
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

    test "redacts a number however the person wrote it" do
      for written <- [
            "+919000000001",
            "+91 90000 00001",
            "+91-90000-00001",
            "(919) 000-0001",
            "9000000001",
            "90000-00001",
            # The usual way an Indian number is typed, and the shape a guard
            # against two adjacent ids most easily blocks by accident.
            "90000 00001",
            "98765 43210",
            # Greedy matching used to run past the fifteen-digit ceiling here
            # and fail the count, leaving the whole string intact.
            "+91 90000 00001 12"
          ] do
        assert Langfuse.mask("reach her on " <> written) == "reach her on [phone]",
               "#{written} left the platform intact"
      end
    end

    test "a number with another figure after it is still masked" do
      # The run matches as one seventeen-digit string, which is nobody's number.
      # Giving up on it left the number itself in place; the trailing figure is
      # not part of the number and has to survive.
      assert Langfuse.mask("call +91 90000 00001 12345 now") == "call [phone] 12345 now"
      assert Langfuse.mask("+91 90000 00001 12") == "[phone]"
    end

    test "leaves the identifiers a trace is read by alone" do
      # Masking on separators as well as digits is what makes a number in any
      # shape reachable; it must not take an id, a date or a UUID with it.
      for kept <- [
            "2026-09-23 14:18:00",
            "flow_id 37740 node f1fub1",
            "contact ids 6298936 and 6289903",
            # Two short ids side by side: with whitespace in the separator class
            # these merged into one fourteen-digit match and both were lost.
            "contact ids 6298936 6289903",
            "uuid 44e1012d-7baf-43fc-87db-e35ac42ab097"
          ] do
        assert Langfuse.mask(kept) == kept
      end
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

    test "does nothing for feedback left without a rating", %{message: message} do
      # Someone can write a comment and pick neither thumb. A categorical score
      # has to carry a string value, so there is nothing to send.
      event = Repo.get_by!(Event, message_id: message.id, type: :assistant)

      {:ok, commented} =
        event
        |> Event.changeset(%{data: Map.put(event.data, "feedback", %{"content" => "unclear"})})
        |> Repo.update()

      assert Langfuse.score(commented) == :ok
    end
  end

  describe "what goes over the wire" do
    setup %{message: message} do
      test_pid = self()

      Application.put_env(:glific, Langfuse,
        host: "https://langfuse.test",
        public_key: "pk-lf-test",
        secret_key: "sk-lf-test",
        plug: {Req.Test, Langfuse}
      )

      on_exit(fn -> Application.delete_env(:glific, Langfuse) end)

      %{message: message, test_pid: test_pid}
    end

    defp stub_langfuse(test_pid, status \\ 200) do
      Req.Test.stub(Langfuse, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:posted, conn.request_path, Jason.decode!(body),
           Plug.Conn.get_req_header(conn, "authorization"),
           Plug.Conn.get_req_header(conn, "x-langfuse-ingestion-version")}
        )

        conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
      end)
    end

    test "a trace posts OTLP spans with basic auth and the version header", %{
      message: message,
      test_pid: test_pid
    } do
      stub_langfuse(test_pid)

      assert :ok = Langfuse.trace(message.id)

      assert_receive {:posted, "/api/public/otel/v1/traces", body, [auth], [version]}
      assert version == "4"
      assert auth == "Basic " <> Base.encode64("pk-lf-test:sk-lf-test")
      assert [%{"scopeSpans" => [%{"spans" => spans}]}] = body["resourceSpans"]
      assert length(spans) > 1
    end

    test "a rated event posts the score Langfuse expects", %{
      message: message,
      test_pid: test_pid
    } do
      stub_langfuse(test_pid)

      event = Repo.get_by!(Event, message_id: message.id, type: :assistant)

      {:ok, rated} =
        event
        |> Event.changeset(%{
          data:
            Map.put(event.data, "feedback", %{
              "rating" => "like",
              "content" => "ring me on 90000 00001"
            })
        })
        |> Repo.update()

      assert :ok = Langfuse.score(rated)

      assert_receive {:posted, "/api/public/scores", body, _auth, _version}
      assert body["dataType"] == "CATEGORICAL"
      assert body["value"] == "like"
      assert body["comment"] == "ring me on [phone]"
      assert is_binary(body["traceId"])
      assert is_binary(body["id"])
    end

    test "the score id is derived, so a changed rating updates in place", %{
      message: message,
      test_pid: test_pid
    } do
      stub_langfuse(test_pid)
      event = Repo.get_by!(Event, message_id: message.id, type: :assistant)

      for rating <- ["like", "dislike"] do
        {:ok, rated} =
          event
          |> Event.changeset(%{data: Map.put(event.data, "feedback", %{"rating" => rating})})
          |> Repo.update()

        assert :ok = Langfuse.score(rated)
      end

      assert_receive {:posted, _path, first, _a, _v}
      assert_receive {:posted, _path, second, _a2, _v2}
      assert first["id"] == second["id"]
    end

    test "a refusal is reported, not raised", %{message: message, test_pid: test_pid} do
      stub_langfuse(test_pid, 401)

      assert {:error, reason} = Langfuse.trace(message.id)
      assert reason =~ "401"
    end

    test "an unreachable Langfuse is reported, not raised", %{message: message} do
      Req.Test.stub(Langfuse, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, reason} = Langfuse.trace(message.id)
      assert reason =~ "could not be reached"
    end

    test "a message that does not exist is an error, not a crash" do
      assert {:error, _reason} = Langfuse.trace(0)
    end
  end

  describe "configuration" do
    setup do
      original = Application.get_env(:glific, Langfuse, [])
      on_exit(fn -> Application.put_env(:glific, Langfuse, original) end)
      :ok
    end

    test "an incomplete setting sends nothing" do
      for settings <- [
            [],
            [host: "https://us.cloud.langfuse.com"],
            [host: "https://us.cloud.langfuse.com", public_key: "pk-lf-x"],
            [public_key: "pk-lf-x", secret_key: "sk-lf-x"],
            [host: "", public_key: "pk-lf-x", secret_key: "sk-lf-x"],
            [host: "https://us.cloud.langfuse.com", public_key: "pk-lf-x", secret_key: "  "]
          ] do
        Application.put_env(:glific, Langfuse, settings)

        refute Langfuse.configured?(), "#{inspect(settings)} should not reach Langfuse"
      end
    end

    test "the host and both keys together send" do
      Application.put_env(:glific, Langfuse,
        host: "https://us.cloud.langfuse.com",
        public_key: "pk-lf-x",
        secret_key: "sk-lf-x"
      )

      assert Langfuse.configured?()
    end

    test "an unconfigured project still answers the caller", %{message: message} do
      Application.put_env(:glific, Langfuse, [])

      assert Langfuse.trace_async(message.id) == :ok
      assert Langfuse.score_async(%Event{message_id: message.id, data: %{}}) == :ok
    end
  end
end
