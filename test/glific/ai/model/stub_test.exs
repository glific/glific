defmodule Glific.AI.Model.StubTest do
  # Not async: the Stub is a globally-named Agent shared with runtime_test.exs and
  # step_worker_test.exs, so concurrent queueing leaks canned responses between files.
  use ExUnit.Case, async: false

  alias Glific.AI.Model.Result
  alias Glific.AI.Model.Stub
  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  setup do
    start_supervised!(Stub)
    :ok
  end

  describe "queue_text/1 and chat/2" do
    test "returns a text result and appends the assistant reply to the context" do
      Stub.queue_text("hello there")

      context = Context.new([Context.user("hi")])
      assert {:ok, %Result{} = result} = Stub.chat(context, [])

      assert result.finish_reason == :stop
      assert result.tool_calls == []
      assert result.usage == Result.zero_usage()
      assert [%{type: :text, text: "hello there"}] = result.message.content
      assert length(Context.to_list(result.context)) == 2
    end

    test "records the context it was called with" do
      context = Context.new([Context.user("hi")])
      Stub.queue_text("hello there")
      Stub.chat(context, [])

      assert [^context] = Stub.calls()
    end
  end

  describe "queue_tool_calls/1 and chat/2" do
    test "returns a tool-call result with finish_reason: :tool_calls" do
      tool_calls = [ToolCall.new("call_1", "get_weather", ~s({"location":"Paris"}))]
      Stub.queue_tool_calls(tool_calls)

      context = Context.new([Context.user("what's the weather?")])
      assert {:ok, %Result{} = result} = Stub.chat(context, [])

      assert result.finish_reason == :tool_calls
      assert result.tool_calls == tool_calls
      assert result.message.tool_calls == tool_calls
    end
  end

  describe "queue_object/1 and object/3" do
    test "returns the queued map as-is" do
      Stub.queue_object(%{"answer" => "42"})

      context = Context.new([Context.user("what is the answer?")])
      assert {:ok, %{"answer" => "42"}} = Stub.object(context, [answer: [type: :string]], [])
    end
  end

  describe "queue_error/1" do
    test "is returned as-is by chat/2" do
      Stub.queue_error(:rate_limited)

      assert {:error, :rate_limited} = Stub.chat(Context.new([]), [])
    end

    test "is returned as-is by object/3" do
      Stub.queue_error(:rate_limited)

      assert {:error, :rate_limited} = Stub.object(Context.new([]), [], [])
    end
  end

  describe "queue ordering" do
    test "responses are returned in the order they were queued" do
      Stub.queue_text("first")
      Stub.queue_text("second")
      Stub.queue_error(:boom)

      context = Context.new([])

      assert {:ok, %Result{message: %{content: [%{text: "first"}]}}} = Stub.chat(context, [])
      assert {:ok, %Result{message: %{content: [%{text: "second"}]}}} = Stub.chat(context, [])
      assert {:error, :boom} = Stub.chat(context, [])
    end
  end

  describe "an empty queue" do
    test "returns a clear error instead of raising" do
      assert {:error, :stub_queue_empty} = Stub.chat(Context.new([]), [])
    end
  end

  describe "reset/0" do
    test "clears both the queue and the recorded calls" do
      Stub.queue_text("will be discarded")
      Stub.chat(Context.new([]), [])

      Stub.reset()

      assert Stub.calls() == []
      assert {:error, :stub_queue_empty} = Stub.chat(Context.new([]), [])
    end
  end
end
