defmodule Glific.AskGlific.BridgeTest do
  @moduledoc false
  use Glific.DataCase, async: false

  import Mock

  alias Glific.{
    AI.Codec,
    AI.Conversation,
    AI.Message,
    AskGlific.Bridge,
    Fixtures
  }

  defp encoded(reqllm_message) do
    {:ok, parts} = Codec.encode(reqllm_message)
    parts
  end

  describe "final_envelope/3" do
    test "extracts the answer text and stringifies ids" do
      conversation = %Conversation{id: 42, title: "About opt-outs"}
      message = %Message{id: 7, parts: encoded(ReqLLM.Context.assistant("The answer."))}

      envelope = Bridge.final_envelope(conversation, message, "req-1")

      assert envelope.answer == "The answer."
      assert envelope.conversation_id == "42"
      assert envelope.conversation_name == "About opt-outs"
      assert envelope.message_id == "7"
      assert envelope.request_id == "req-1"
      assert envelope.errors == []
    end

    test "falls back to an empty string when the message fails to decode" do
      conversation = %Conversation{id: 1, title: "x"}
      message = %Message{id: 2, parts: %{"not" => "valid"}}

      assert Bridge.final_envelope(conversation, message, nil).answer == ""
    end

    test "tolerates a nil request id" do
      conversation = %Conversation{id: 1, title: "x"}
      message = %Message{id: 2, parts: encoded(ReqLLM.Context.assistant("hi"))}

      assert Bridge.final_envelope(conversation, message, nil).request_id == nil
    end
  end

  describe "error_envelope/3" do
    test "carries the errors from fields, with a nil answer and message_id" do
      conversation = %Conversation{id: 5, title: "y"}
      errors = [%{key: "runtime", message: "step budget exhausted"}]

      envelope = Bridge.error_envelope(conversation, "req-2", %{errors: errors})

      assert envelope.answer == nil
      assert envelope.message_id == nil
      assert envelope.conversation_id == "5"
      assert envelope.conversation_name == "y"
      assert envelope.request_id == "req-2"
      assert envelope.errors == errors
    end

    test "defaults errors to an empty list" do
      conversation = %Conversation{id: 5, title: "y"}
      assert Bridge.error_envelope(conversation, "req-2", %{}).errors == []
    end
  end

  describe "publish/4" do
    test "does nothing for events the legacy frontend has no vocabulary for" do
      with_mock Absinthe.Subscription, publish: fn _endpoint, _payload, _opts -> :ok end do
        conversation = Fixtures.ai_conversation_fixture(%{skill: "ask_glific"})

        for event <- [:queued, :delta, :message, :proposal] do
          assert Bridge.publish(conversation, event, "req-1", %{}) == :ok
        end

        refute called(Absinthe.Subscription.publish(:_, :_, :_))
      end
    end

    test "publishes nothing on :final when no assistant answer has been persisted yet" do
      with_mock Absinthe.Subscription, publish: fn _endpoint, _payload, _opts -> :ok end do
        conversation = Fixtures.ai_conversation_fixture(%{skill: "ask_glific"})

        assert Bridge.publish(conversation, :final, "req-1", %{}) == :ok
        refute called(Absinthe.Subscription.publish(:_, :_, :_))
      end
    end

    test "publishes the newest complete assistant answer on :final" do
      test_pid = self()

      with_mock Absinthe.Subscription,
        publish: fn _endpoint, payload, opts ->
          send(test_pid, {:published, payload, opts})
          :ok
        end do
        conversation = Fixtures.ai_conversation_fixture(%{skill: "ask_glific"})

        Fixtures.ai_message_fixture(%{conversation: conversation, seq: 1, role: :user})

        Fixtures.ai_message_fixture(%{
          conversation: conversation,
          seq: 2,
          role: :assistant,
          reqllm_message: ReqLLM.Context.assistant("first draft")
        })

        answer =
          Fixtures.ai_message_fixture(%{
            conversation: conversation,
            seq: 3,
            role: :assistant,
            reqllm_message: ReqLLM.Context.assistant("final answer")
          })

        assert Bridge.publish(conversation, :final, "req-1", %{}) == :ok

        assert_receive {:published, payload, [ask_glific_response: topic]}
        assert payload.answer == "final answer"
        assert payload.message_id == to_string(answer.id)
        assert payload.conversation_id == to_string(conversation.id)
        assert payload.request_id == "req-1"
        assert topic == "#{conversation.organization_id}:#{conversation.user_id}"
      end
    end

    test "publishes an error envelope on :error" do
      test_pid = self()

      with_mock Absinthe.Subscription,
        publish: fn _endpoint, payload, _opts ->
          send(test_pid, {:published, payload})
          :ok
        end do
        conversation = Fixtures.ai_conversation_fixture(%{skill: "ask_glific"})
        errors = [%{key: "runtime", message: "boom"}]

        assert Bridge.publish(conversation, :error, "req-1", %{errors: errors}) == :ok

        assert_receive {:published, payload}
        assert payload.errors == errors
        assert payload.answer == nil
      end
    end
  end
end
