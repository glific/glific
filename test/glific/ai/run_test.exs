defmodule Glific.AI.RunTest do
  @moduledoc false
  use Glific.DataCase, async: false

  alias Glific.AI.Conversation
  alias Glific.AI.Message
  alias Glific.AI.Model.Stub
  alias Glific.AI.Run
  alias Glific.Fixtures
  alias Glific.Repo
  alias ReqLLM.ToolCall

  setup do
    start_supervised!(Stub)
    :ok
  end

  defp fixture_tool_call(args) do
    %ToolCall{
      id: "call_1",
      type: "function",
      function: %{name: "fixture_tool", arguments: Jason.encode!(args)}
    }
  end

  defp messages_for(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.seq)
    |> Repo.all()
  end

  describe "sync/3 — happy path" do
    test "a no-tool skill completes in one step and releases the conversation", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      Stub.queue_text("hello back")

      assert {:ok, %{result: result, steps: 1} = outcome} =
               Run.sync("echo", %{"message" => "hello there"}, user)

      assert %{content: [%{text: "hello back"}]} = result

      assert [
               %Message{seq: 1, role: :user, status: :complete},
               %Message{seq: 2, role: :assistant, status: :complete}
             ] = messages_for(outcome.conversation.id)

      assert outcome.conversation.active_status == nil
      assert outcome.conversation.active_request_id == nil
    end
  end

  describe "sync/3 — tool-using skill" do
    test "a model call, a tool batch, then a final answer are reflected in steps", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      Stub.queue_tool_calls([fixture_tool_call(%{"query" => "flows"})])
      Stub.queue_text("final answer")

      assert {:ok, %{result: result, steps: 3} = outcome} =
               Run.sync("runtime_fixture", %{"message" => "look something up"}, user)

      assert %{content: [%{text: "final answer"}]} = result

      assert [
               %Message{seq: 1, role: :user},
               %Message{seq: 2, role: :assistant},
               %Message{seq: 3, role: :tool},
               %Message{seq: 4, role: :assistant}
             ] = messages_for(outcome.conversation.id)

      assert outcome.conversation.active_status == nil
    end
  end

  describe "sync/3 — unknown skill" do
    test "an unregistered skill name is rejected before any model call", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      assert {:error, :unknown_skill} = Run.sync("does_not_exist", %{}, user)
      assert Stub.calls() == []
    end
  end

  describe "sync/3 — authorization" do
    test "a user ranked below the skill's required_role is forbidden", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["none"]})

      assert {:error, :forbidden} = Run.sync("echo", %{"message" => "hello"}, user)
      assert Stub.calls() == []
    end
  end

  describe "sync/3 — feature flag" do
    test "a skill whose feature_flag is off for the org is refused before any model call", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      FunWithFlags.disable(:is_template_utility_rewrite_enabled,
        for_actor: %{organization_id: organization_id}
      )

      assert {:error, :feature_disabled} =
               Run.sync("template_utility_rewrite", %{"message" => "BODY: hello"}, user)

      assert Stub.calls() == []
    end

    test "a skill declaring no feature_flag runs regardless", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})
      Stub.queue_text("hello")

      assert {:ok, _outcome} = Run.sync("echo", %{"message" => "hello"}, user)
    end
  end

  describe "sync/3 — gated skill" do
    test "a gated skill is refused before any model call is made", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      assert {:error, :gated_skill} =
               Run.sync("gated_runtime_fixture", %{"message" => "please approve this"}, user)

      assert Stub.calls() == []
    end
  end

  describe "sync/3 — step budget" do
    test "the model requesting tools past max_steps ends the run with :step_budget_exhausted", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      # runtime_fixture's max_steps/0 defaults to 8 (Glific.AI.Skill's `use` default). Each
      # tool-call round trip is two loop steps (the model call requesting the tool, then the
      # tool batch), so 4 rounds walks step_count from 0 to 8 without ever reaching a final
      # answer.
      for _round <- 1..4, do: Stub.queue_tool_calls([fixture_tool_call(%{"query" => "flows"})])

      assert {:error, :step_budget_exhausted} =
               Run.sync("runtime_fixture", %{"message" => "keep looping"}, user)

      conversation = Repo.get_by!(Conversation, user_id: user.id, skill: "runtime_fixture")
      assert conversation.active_status == nil
      assert conversation.active_request_id == nil
      assert conversation.last_error["reason"] =~ "step_budget_exhausted"
    end
  end

  describe "sync/3 — model failure" do
    test "a model error is returned and the conversation is released with last_error set", %{
      organization_id: organization_id
    } do
      user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["staff"]})

      Stub.queue_error(%{status: 500, message: "upstream failure"})

      assert {:error, %{status: 500}} = Run.sync("echo", %{"message" => "hello"}, user)

      conversation = Repo.get_by!(Conversation, user_id: user.id, skill: "echo")
      assert conversation.active_status == nil
      assert conversation.active_request_id == nil
      assert conversation.last_error["reason"] =~ "500"
    end
  end
end
