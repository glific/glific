defmodule Glific.AI.StepWorkerTest do
  @moduledoc false
  use Glific.DataCase, async: false
  use Oban.Testing, repo: Glific.Repo

  alias Glific.AI.Codec
  alias Glific.AI.Conversation
  alias Glific.AI.Credentials
  alias Glific.AI.Message
  alias Glific.AI.Model.Stub
  alias Glific.AI.Runtime
  alias Glific.AI.Runtime.State
  alias Glific.AI.Skill.Registry
  alias Glific.AI.StepWorker
  alias Glific.Fixtures
  alias Glific.Repo
  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  setup do
    start_supervised!(Stub)
    :ok
  end

  defp seed_conversation(attrs, organization_id) do
    user = Fixtures.user_fixture(%{organization_id: organization_id})

    conversation =
      Fixtures.ai_conversation_fixture(
        Map.merge(
          %{
            organization_id: organization_id,
            user_id: user.id,
            skill: "runtime_fixture",
            max_steps: 5,
            active_status: :running,
            active_request_id: "req-1",
            step_count: 0
          },
          attrs
        )
      )

    Fixtures.ai_message_fixture(%{
      conversation: conversation,
      seq: 1,
      reqllm_message: Context.user("hello there")
    })

    %{conversation: conversation, user: user}
  end

  defp job_args(conversation, user, seq) do
    %{
      "conversation_id" => conversation.id,
      "organization_id" => conversation.organization_id,
      "user_id" => user.id,
      "seq" => seq
    }
  end

  defp resume_job_args(conversation, user, seq, decision),
    do: Map.put(job_args(conversation, user, seq), "decision", decision)

  defp message_at(conversation_id, seq),
    do: Repo.get_by(Message, conversation_id: conversation_id, seq: seq)

  # perform_job/2 does not dequeue, so enqueued jobs accumulate across steps. The high-water
  # seq is what says whether this step scheduled a successor.
  defp newest_enqueued_seq do
    [worker: StepWorker, prefix: "global"]
    |> all_enqueued()
    |> Enum.map(& &1.args["seq"])
    |> Enum.max(fn -> nil end)
  end

  defp fixture_tool_call(args) do
    %ToolCall{
      id: "call_1",
      type: "function",
      function: %{name: "fixture_tool", arguments: Jason.encode!(args)}
    }
  end

  describe "perform/1 — end-to-end run" do
    test "drives a tool_calls -> tool batch -> final answer run across 3 jobs", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} = seed_conversation(%{}, organization_id)

      # Step 1: model call, requests a tool.
      Stub.queue_tool_calls([fixture_tool_call(%{"query" => "flows"})])

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert %Message{role: :assistant, status: :complete} = message_at(conversation.id, 2)
      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == :running
      assert refreshed.step_count == 1

      assert newest_enqueued_seq() == 3

      # Step 2: tool batch, no model call.
      calls_before_step_2 = length(Stub.calls())
      assert :ok = perform_job(StepWorker, job_args(conversation, user, 3))
      assert length(Stub.calls()) == calls_before_step_2

      assert %Message{role: :tool, status: :complete} = message_at(conversation.id, 3)
      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == :running
      assert refreshed.step_count == 2

      assert newest_enqueued_seq() == 4

      # Step 3: model call, final answer.
      Stub.queue_text("final answer")
      assert :ok = perform_job(StepWorker, job_args(conversation, user, 4))

      assert %Message{role: :assistant, status: :complete} = message_at(conversation.id, 4)
      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == nil
      assert refreshed.active_request_id == nil
      assert refreshed.step_count == 3

      # A :done step schedules nothing further — seq 4 stays the high-water mark.
      assert newest_enqueued_seq() == 4
    end
  end

  describe "perform/1 — status guard" do
    test "a late job for an idle conversation is a harmless no-op", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_conversation(%{active_status: nil, active_request_id: nil}, organization_id)

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert message_at(conversation.id, 2) == nil
      assert Stub.calls() == []
      assert all_enqueued(worker: StepWorker, prefix: "global") == []
    end

    test "a late job for an already-suspended conversation is a no-op", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_conversation(%{active_status: :awaiting_confirmation}, organization_id)

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert message_at(conversation.id, 2) == nil
      assert Stub.calls() == []
    end
  end

  describe "perform/1 — budget guard" do
    test "step_count >= max_steps fails the run without calling the model", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_conversation(%{step_count: 5, max_steps: 5}, organization_id)

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert message_at(conversation.id, 2) == nil
      assert Stub.calls() == []

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == nil
      assert refreshed.active_request_id == nil
      assert refreshed.last_error["reason"] =~ "step budget exhausted"
      assert all_enqueued(worker: StepWorker, prefix: "global") == []
    end
  end

  describe "perform/1 — gate suspension" do
    test "a gated skill's final answer suspends the run and enqueues nothing", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_conversation(%{skill: "gated_runtime_fixture"}, organization_id)

      Stub.queue_text("proposed answer")

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert %Message{role: :assistant, status: :complete} = message_at(conversation.id, 2)

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == :awaiting_confirmation
      assert refreshed.step_count == 1
      assert is_binary(refreshed.gate_token)
      assert refreshed.gate_token != ""
      assert %DateTime{} = refreshed.gate_expires_at
      assert DateTime.compare(refreshed.gate_expires_at, DateTime.utc_now()) == :gt
      assert %{"input" => %{"message" => "hello there"}} = refreshed.pending_proposal

      assert all_enqueued(worker: StepWorker, prefix: "global") == []
    end
  end

  describe "perform/1 — resume" do
    defp seed_gated_conversation(attrs, organization_id) do
      proposal = %{"input" => %{"message" => "hello there"}, "result" => "proposed answer"}

      seed_conversation(
        Map.merge(
          %{
            skill: "gated_runtime_fixture",
            active_status: :running,
            step_count: 1,
            pending_proposal: proposal
          },
          attrs
        ),
        organization_id
      )
    end

    test "an accepted resume drives the run to :done and persists the decision message", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} = seed_gated_conversation(%{}, organization_id)

      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "accepted"))

      assert %Message{role: :user, status: :complete} = message = message_at(conversation.id, 2)
      {:ok, decoded} = Codec.decode(message.parts)
      assert %{content: [%{text: "The proposal was accepted."}]} = decoded

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == nil
      assert refreshed.active_request_id == nil
      assert refreshed.pending_proposal == nil
      # Resuming a gate is not a model/tool step — see Glific.AI.StepWorker's moduledoc,
      # "Budget guard" — so step_count is unchanged from what the suspending step already set.
      assert refreshed.step_count == 1

      assert newest_enqueued_seq() == nil
    end

    test "a rejected resume continues the run: decision message then the skill's own message", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} = seed_gated_conversation(%{}, organization_id)

      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "rejected"))

      assert %Message{role: :user} = decision_message = message_at(conversation.id, 2)
      {:ok, decoded_decision} = Codec.decode(decision_message.parts)
      assert %{content: [%{text: "The proposal was rejected."}]} = decoded_decision

      assert %Message{role: :user} = continuation_message = message_at(conversation.id, 3)
      {:ok, decoded_continuation} = Codec.decode(continuation_message.parts)
      assert %{content: [%{text: text}]} = decoded_continuation
      assert text =~ "That proposal was rejected"

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == :running
      assert refreshed.pending_proposal == nil
      assert refreshed.step_count == 1

      # The next job is an ordinary step: no "decision" key, so it will call Runtime.step/1.
      assert [next_job] = all_enqueued(worker: StepWorker, prefix: "global")
      assert next_job.args["seq"] == 4
      refute Map.has_key?(next_job.args, "decision")
    end

    test "a resume job while still awaiting confirmation (gate never resolved) is a no-op", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_gated_conversation(%{active_status: :awaiting_confirmation}, organization_id)

      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "accepted"))

      assert message_at(conversation.id, 2) == nil
      assert Stub.calls() == []
    end

    test "a resume job for a conversation that is no longer awaiting confirmation is a no-op", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} =
        seed_gated_conversation(%{active_status: :cancelled}, organization_id)

      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "accepted"))

      assert message_at(conversation.id, 2) == nil
      assert Stub.calls() == []

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.active_status == :cancelled
    end

    test "a replayed resume job does not duplicate rows", %{organization_id: organization_id} do
      %{conversation: conversation, user: user} = seed_gated_conversation(%{}, organization_id)

      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "accepted"))
      assert %Message{} = message_at(conversation.id, 2)

      # A redelivered job after Oban's at-least-once ack was lost: same args. The conversation
      # already advanced past :done, so the status guard no-ops the replay.
      assert :ok = perform_job(StepWorker, resume_job_args(conversation, user, 2, "accepted"))

      assert Message
             |> where([m], m.conversation_id == ^conversation.id and m.seq == 2)
             |> Repo.all()
             |> length() == 1
    end
  end

  describe "perform/1 — kill-mid-step replay" do
    test "resumes from the last complete message: one model call re-issued, no duplicate row", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} = seed_conversation(%{}, organization_id)

      # Simulate the process dying after the model call returned but before the Multi
      # committed: drive Runtime.step/1 directly, bypassing StepWorker's persistence
      # entirely, so this attempt writes nothing at all.
      Stub.queue_text("lost response")

      {:ok, skill} = Registry.fetch(conversation.skill)
      {:ok, context} = Glific.AI.build_context(conversation.id)
      {:ok, api_key} = Credentials.fetch(organization_id, skill.provider())

      lost_state =
        State.new(
          conversation: conversation,
          skill: skill,
          user: user,
          context: context,
          step_index: 2,
          organization_id: organization_id,
          api_key: api_key
        )

      assert {:done, _next_state, _result, _attrs} = Runtime.step(lost_state)
      assert message_at(conversation.id, 2) == nil

      # Oban.Pro.Plugins.DynamicLifeline reschedules the same orphaned job row: identical
      # args, identical seq.
      Stub.queue_text("replayed response")
      calls_before_replay = length(Stub.calls())

      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert length(Stub.calls()) == calls_before_replay + 1

      assert %Message{} = message = message_at(conversation.id, 2)
      {:ok, decoded} = Codec.decode(message.parts)
      assert %{content: [%{text: "replayed response"}]} = decoded

      assert Message
             |> where([m], m.conversation_id == ^conversation.id and m.seq == 2)
             |> Repo.all()
             |> length() == 1
    end

    test "a redelivered job after a successful commit does not duplicate the message row", %{
      organization_id: organization_id
    } do
      %{conversation: conversation, user: user} = seed_conversation(%{}, organization_id)

      Stub.queue_text("final answer")
      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))
      assert %Message{} = message_at(conversation.id, 2)

      refreshed = Repo.get!(Conversation, conversation.id)
      assert refreshed.step_count == 1

      # A redelivered job after Oban's at-least-once ack was lost: same args, conversation
      # already advanced past :done means the status guard now no-ops it.
      assert :ok = perform_job(StepWorker, job_args(conversation, user, 2))

      assert Message
             |> where([m], m.conversation_id == ^conversation.id and m.seq == 2)
             |> Repo.all()
             |> length() == 1
    end
  end
end
