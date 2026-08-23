defmodule Glific.AI.PublisherTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import Mock

  alias Glific.AI.Conversation
  alias Glific.AI.Publisher
  alias Glific.AskGlific.Bridge

  # envelope/4 and topic/1 are exercised directly rather than through publish/4: the side effect
  # publish/4 adds is an Absinthe.Subscription.publish call whose delivery needs a live endpoint
  # and a subscribed socket, and standing that up would test Absinthe rather than the envelope
  # this module is responsible for getting right.
  defp conversation(overrides \\ %{}) do
    Map.merge(
      %Conversation{
        id: 42,
        skill: "echo",
        user_id: 7,
        organization_id: 3
      },
      overrides
    )
  end

  describe "topic/1" do
    test "is derived from the conversation, not the calling process" do
      assert Publisher.topic(conversation()) == "3:7"
    end

    test "matches the topic ask_glific_response and assistant_chat_response already share" do
      assert Publisher.topic(conversation(%{organization_id: 1, user_id: 1})) == "1:1"
    end
  end

  describe "envelope/4" do
    test "carries the event name as a string and echoes the request id" do
      envelope = Publisher.envelope(conversation(), :queued, "req-1", %{})

      assert envelope.event == "queued"
      assert envelope.request_id == "req-1"
      assert envelope.conversation_id == 42
    end

    test "defaults seq and payload to nil and errors to an empty list" do
      envelope = Publisher.envelope(conversation(), :queued, "req-1", %{})

      assert envelope.seq == nil
      assert envelope.payload == nil
      assert envelope.errors == []
    end

    test "carries seq on a message event so the client knows which bubble to append to" do
      envelope = Publisher.envelope(conversation(), :message, "req-1", %{seq: 4})

      assert envelope.seq == 4
    end

    test "carries the per-skill payload on a final event" do
      envelope =
        Publisher.envelope(conversation(), :final, "req-1", %{payload: %{"answer" => "42"}})

      assert envelope.payload == %{"answer" => "42"}
    end

    test "carries errors on an error event" do
      errors = [%{key: "runtime", message: "step budget exhausted"}]
      envelope = Publisher.envelope(conversation(), :error, "req-1", %{errors: errors})

      assert envelope.errors == errors
    end

    # A terminal event is built after the transaction that cleared active_request_id, so the
    # caller has to pass the id it captured beforehand. If it ever stops doing that, a client
    # filtering on request_id sees nothing and hangs instead of erroring — this asserts the
    # envelope propagates whatever it is given rather than reading the cleared field.
    test "takes request_id from the argument, never from the conversation" do
      released = conversation(%{active_request_id: nil})

      assert Publisher.envelope(released, :final, "req-1", %{}).request_id == "req-1"
    end

    test "tolerates a nil request id rather than raising" do
      assert Publisher.envelope(conversation(), :error, nil, %{}).request_id == nil
    end
  end

  describe "publish/4" do
    test "rejects an event outside the vocabulary" do
      assert_raise FunctionClauseError, fn ->
        Publisher.publish(conversation(), :not_an_event, "req-1", %{})
      end
    end

    test "rejects a request id that is neither a string nor nil" do
      assert_raise FunctionClauseError, fn ->
        Publisher.publish(conversation(), :queued, 123, %{})
      end
    end
  end

  # `publish_legacy/4` is exercised directly, the same way `envelope/4` and `topic/1` are:
  # `Glific.AskGlific.Bridge.publish/4` itself calls `Absinthe.Subscription.publish` on :final
  # and :error, which needs a live endpoint — the routing decision this dispatch makes doesn't.
  describe "publish_legacy/4" do
    test "dispatches to Glific.AskGlific.Bridge.publish/4 for the ask_glific skill" do
      with_mock Bridge, publish: fn _conversation, _event, _request_id, _fields -> :ok end do
        ask_glific_conversation = conversation(%{skill: "ask_glific"})

        assert Publisher.publish_legacy(ask_glific_conversation, :final, "req-1", %{}) == :ok

        assert called(Bridge.publish(ask_glific_conversation, :final, "req-1", %{}))
      end
    end

    test "does nothing for any other skill" do
      with_mock Bridge, publish: fn _conversation, _event, _request_id, _fields -> :ok end do
        assert Publisher.publish_legacy(conversation(%{skill: "echo"}), :final, "req-1", %{}) ==
                 :ok

        refute called(Bridge.publish(:_, :_, :_, :_))
      end
    end
  end
end
