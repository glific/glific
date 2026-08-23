defmodule Glific.AI.RuntimeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Glific.AI.Actor
  alias Glific.AI.Codec
  alias Glific.AI.Conversation
  alias Glific.AI.Model.Stub
  alias Glific.AI.Runtime
  alias Glific.AI.Runtime.State
  alias Glific.AI.Test.GatedRuntimeSkill
  alias Glific.AI.Test.RuntimeSkill
  alias Glific.AI.Test.StructuredRuntimeSkill
  alias Glific.Repo
  alias Glific.Users.User
  alias ReqLLM.Context

  @organization_id 1
  # Deliberately not id 1: organization 1's root_user is id 1, and Actor.assert!/2 refuses to let
  # an agent act as the org root. That check only fires once the Partners cache is warm, so a
  # colliding id passes this file in isolation and fails it in a full suite run.
  @user %User{id: 999_001, organization_id: 1, roles: [:staff]}

  setup do
    start_supervised!(Stub)
    Repo.put_organization_id(@organization_id)
    Repo.put_current_user(@user)
    :ok
  end

  defp conversation(overrides \\ %{}) do
    Map.merge(
      %Conversation{
        id: 1,
        skill: "runtime_fixture",
        active_request_id: "req-1",
        active_status: :running,
        step_count: 0,
        max_steps: 10,
        user_id: @user.id,
        organization_id: @organization_id
      },
      overrides
    )
  end

  defp state(overrides \\ []) do
    defaults = [
      conversation: conversation(),
      skill: RuntimeSkill,
      user: @user,
      context: Context.new([Context.user("hello there")]),
      step_index: 1,
      organization_id: @organization_id,
      api_key: "test-api-key"
    ]

    State.new(Keyword.merge(defaults, overrides))
  end

  describe "step/1 — model call, plain text finish" do
    test "returns :done with the assistant's message and one continue-shaped message_attrs" do
      Stub.queue_text("hello back")

      assert {:done, %State{} = next_state, result, [attrs]} = Runtime.step(state())

      assert next_state.step_index == 2
      assert %{content: [%{text: "hello back"}]} = result
      assert attrs.role == :assistant
      assert attrs.status == :complete
      assert attrs.request_id == "req-1"
      assert attrs.model == RuntimeSkill.model()
      assert is_map(attrs.parts)
    end

    test "sends the rendered system prompt ahead of the stored context" do
      Stub.queue_text("hi")
      Runtime.step(state())

      assert [%Context{messages: [system_msg, user_msg]}] = Stub.calls()
      assert system_msg.role == :system
      assert [%{text: "Respond helpfully to: hello there"}] = system_msg.content
      assert user_msg.role == :user
    end
  end

  describe "step/1 — model call, tool_calls finish" do
    test "returns :continue with the assistant's tool-call message, tools not yet run" do
      tool_calls = [
        %ReqLLM.ToolCall{
          id: "call_1",
          type: "function",
          function: %{name: "fixture_tool", arguments: Jason.encode!(%{"query" => "flows"})}
        }
      ]

      Stub.queue_tool_calls(tool_calls)

      assert {:continue, %State{} = next_state, [attrs]} = Runtime.step(state())

      assert next_state.step_index == 2
      assert attrs.role == :assistant
      assert attrs.status == :complete
    end
  end

  describe "step/1 — tool batch" do
    defp context_with_pending_tool_call(arguments) do
      tool_call = %ReqLLM.ToolCall{
        id: "call_1",
        type: "function",
        function: %{name: "fixture_tool", arguments: Jason.encode!(arguments)}
      }

      Context.new([
        Context.user("hello there"),
        Context.assistant("", tool_calls: [tool_call])
      ])
    end

    test "runs the pending tool call and returns one :tool message, no model call made" do
      context = context_with_pending_tool_call(%{"query" => "flows"})

      assert {:continue, %State{} = next_state, [attrs]} =
               Runtime.step(state(context: context))

      assert next_state.step_index == 2
      assert attrs.role == :tool
      assert Stub.calls() == []
    end

    test "an invalid tool call is self-repaired: an error tool result, not a crash" do
      context = context_with_pending_tool_call(%{})

      assert {:continue, _state, [attrs]} = Runtime.step(state(context: context))
      assert attrs.role == :tool
    end

    test "not-valid-JSON tool arguments are self-repaired the same way" do
      tool_call = %ReqLLM.ToolCall{
        id: "call_1",
        type: "function",
        function: %{name: "fixture_tool", arguments: "not json"}
      }

      context =
        Context.new([
          Context.user("hello there"),
          Context.assistant("", tool_calls: [tool_call])
        ])

      assert {:continue, _state, [attrs]} = Runtime.step(state(context: context))
      assert attrs.role == :tool
    end

    test "an unlisted tool name comes back as a model-visible error, not a crash" do
      tool_call = %ReqLLM.ToolCall{
        id: "call_1",
        type: "function",
        function: %{name: "not_a_real_tool", arguments: "{}"}
      }

      context =
        Context.new([
          Context.user("hello there"),
          Context.assistant("", tool_calls: [tool_call])
        ])

      assert {:continue, _state, [attrs]} = Runtime.step(state(context: context))
      assert attrs.role == :tool
    end

    test "a drifted acting identity raises Actor.Error, caught as :permanent_error" do
      context = context_with_pending_tool_call(%{"query" => "flows"})
      step_state = state(context: context)

      # A freshly spawned process has no acting user in its dictionary at all — the same
      # "identity never established" failure Actor.current!/0 raises on.
      result = Task.async(fn -> Runtime.step(step_state) end) |> Task.await()

      assert {:permanent_error, %Actor.Error{}} = result
    end
  end

  describe "step/1 — gate_policy :none vs {:on_final, ttl}" do
    test ":none finishes as :done" do
      Stub.queue_text("plain answer")
      assert {:done, _state, _result, _attrs} = Runtime.step(state(skill: RuntimeSkill))
    end

    test "{:on_final, ttl} finishes as :suspend, carrying build_proposal/2's result" do
      Stub.queue_text("proposed answer")

      assert {:suspend, %State{} = next_state, proposal, [attrs]} =
               Runtime.step(state(skill: GatedRuntimeSkill))

      assert next_state.step_index == 2
      assert %{"input" => %{"message" => "hello there"}, "result" => _} = proposal
      assert attrs.role == :assistant
    end

    test "a failing build_proposal/2 becomes :permanent_error" do
      Stub.queue_text("proposed answer")

      context = Context.new([Context.user("trigger_proposal_error")])

      assert {:permanent_error, "build_proposal failed"} =
               Runtime.step(state(skill: GatedRuntimeSkill, context: context))
    end
  end

  describe "step/1 — output_schema" do
    test "a non-nil schema routes the final answer through Model.object/3" do
      Stub.queue_text("draft answer")
      Stub.queue_object(%{"answer" => "42"})

      assert {:done, _state, %{"answer" => "42"}, [attrs]} =
               Runtime.step(state(skill: StructuredRuntimeSkill))

      assert attrs.role == :assistant
      assert length(Stub.calls()) == 2
    end

    # Anthropic's generate_object rejects a context ending in an assistant message outright.
    # The chat call leaves exactly that shape behind, so the structuring pass has to append a
    # user turn — without it every schema-bearing skill fails at its final step, on the
    # provider rather than anywhere a test would normally look.
    test "the structuring call is sent a context ending in a user message" do
      Stub.queue_text("draft answer")
      Stub.queue_object(%{"answer" => "42"})

      Runtime.step(state(skill: StructuredRuntimeSkill))

      object_context = Stub.calls() |> Enum.at(1)
      assert %ReqLLM.Message{role: :user} = List.last(Context.to_list(object_context))
    end

    test "an object/3 failure is :transient_error" do
      Stub.queue_text("draft answer")
      Stub.queue_error(:schema_validation_failed)

      assert {:transient_error, :schema_validation_failed} =
               Runtime.step(state(skill: StructuredRuntimeSkill))
    end
  end

  describe "step/1 — model call failures" do
    test "chat/2 failure is :transient_error, indiscriminately" do
      Stub.queue_error(%{status: 429, retryable: true})

      assert {:transient_error, %{status: 429}} = Runtime.step(state())
    end

    test "an empty stub queue is also a :transient_error (not a crash)" do
      assert {:transient_error, :stub_queue_empty} = Runtime.step(state())
    end
  end

  describe "resume/2" do
    defp gated_state(pending_proposal, overrides \\ []) do
      state(
        Keyword.merge(
          [
            skill: GatedRuntimeSkill,
            conversation: conversation(%{pending_proposal: pending_proposal})
          ],
          overrides
        )
      )
    end

    defp decoded_text(attrs) do
      {:ok, message} = Codec.decode(attrs.parts)

      message.content
      |> Enum.filter(&(&1.type == :text))
      |> Enum.map_join("", & &1.text)
    end

    test ":accepted maps GatedRuntimeSkill's {:done, payload} onto :done" do
      proposal = %{"input" => %{"message" => "hello there"}, "result" => "proposed answer"}

      assert {:done, %State{} = next_state, payload, [decision_attrs]} =
               Runtime.resume(gated_state(proposal), :accepted)

      assert next_state.step_index == 2
      assert payload == proposal
      assert decision_attrs.role == :user
      assert decision_attrs.request_id == "req-1"
      assert decoded_text(decision_attrs) == "The proposal was accepted."
    end

    test ":rejected maps GatedRuntimeSkill's {:continue, messages} onto :continue, decision first" do
      proposal = %{"input" => %{"message" => "hello there"}, "result" => "proposed answer"}

      assert {:continue, %State{} = next_state, [decision_attrs, continuation_attrs]} =
               Runtime.resume(gated_state(proposal), :rejected)

      assert next_state.step_index == 2
      assert decision_attrs.role == :user
      assert decoded_text(decision_attrs) == "The proposal was rejected."

      assert continuation_attrs.role == :user
      assert continuation_attrs.request_id == "req-1"
      assert decoded_text(continuation_attrs) =~ "That proposal was rejected"
    end

    test "the synthesized decision message is deterministic across calls" do
      proposal = %{"input" => %{"message" => "hello there"}, "result" => "proposed answer"}

      assert {:done, _state, _payload, [first]} = Runtime.resume(gated_state(proposal), :accepted)

      assert {:done, _state, _payload, [second]} =
               Runtime.resume(gated_state(proposal), :accepted)

      assert first.parts == second.parts
    end

    test "a skill's on_decision/3 raising is a :permanent_error" do
      proposal = %{"input" => %{"message" => "trigger_on_decision_raise"}}

      assert {:permanent_error, %RuntimeError{message: "on_decision blew up"}} =
               Runtime.resume(gated_state(proposal), :accepted)
    end

    test "a malformed on_decision/3 return is a :permanent_error" do
      proposal = %{"input" => %{"message" => "trigger_on_decision_malformed"}}

      assert {:permanent_error, {:invalid_on_decision_result, :not_a_valid_on_decision_result}} =
               Runtime.resume(gated_state(proposal), :accepted)
    end

    test "a gated skill that never implemented on_decision/3 is a :permanent_error" do
      assert {:permanent_error, {:on_decision_not_implemented, RuntimeSkill}} =
               Runtime.resume(state(skill: RuntimeSkill), :accepted)
    end
  end
end
