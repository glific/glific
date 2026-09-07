defmodule Glific.AI.SkillRunTest do
  use Glific.DataCase

  alias Glific.{
    AI.Conversation,
    AI.Event,
    AI.Message,
    AI.SkillRun,
    AskGlific,
    FakeProvider,
    Fixtures,
    Repo
  }

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, FakeProvider.start()))

    on_exit(fn ->
      FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})
    FakeProvider.always(FakeProvider.answer("a draft"))

    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  describe "running one skill" do
    test "answers, and records the run against a skill_run thread", %{user: user} do
      assert {:ok, result} = SkillRun.start("draft_hsm", "draft something", user)

      assert result.answer == "a draft"
      assert result.skill == "draft_hsm"
      assert is_binary(result.message_id)

      conversation = Repo.one!(from(c in Conversation, where: c.user_id == ^user.id))
      assert conversation.kind == :skill_run
      assert conversation.title == "draft_hsm"

      message = Repo.one!(from(m in Message, where: m.conversation_id == ^conversation.id))
      assert message.status == :succeeded
      assert message.skill == "draft_hsm"
    end

    test "the question and the answer are both recorded", %{user: user} do
      assert {:ok, _} = SkillRun.start("draft_hsm", "draft something", user)

      types = Repo.all(from(e in Event, order_by: e.step, select: e.type))
      assert :user in types
      assert :assistant in types
    end

    test "a tool outside the skill's set is refused even when the model asks for it",
         %{user: user} do
      # The model can name a tool it knows from training rather than from the
      # schemas it was sent, so the skill's set has to hold at execution.
      FakeProvider.script([
        FakeProvider.tool_use("list_contacts", %{}),
        FakeProvider.answer("a draft")
      ])

      assert {:ok, _} = SkillRun.start("draft_hsm", "draft something", user)

      result = Repo.one!(from(e in Event, where: e.type == :tool_result))
      assert result.data["output"] =~ "There is no tool called"
      assert result.data["output"] =~ "list_contacts"
    end

    test "a named skill is not classified, so no routing event is recorded", %{user: user} do
      assert {:ok, _} = SkillRun.start("draft_hsm", "draft something", user)

      refute Repo.exists?(from(e in Event, where: e.type == :routing))
    end

    test "an unknown skill is an error rather than a fallback", %{user: user} do
      assert {:error, message} = SkillRun.start("no_such_skill", "draft something", user)
      assert message =~ "no_such_skill"

      refute Repo.exists?(from(c in Conversation, where: c.user_id == ^user.id))
    end

    test "a skill is required", %{user: user} do
      assert {:error, "Skill is required"} = SkillRun.start(nil, "draft something", user)
      assert {:error, "Skill is required"} = SkillRun.start("", "draft something", user)
    end

    test "a query is required", %{user: user} do
      assert {:error, "Query is required"} = SkillRun.start("draft_hsm", "   ", user)
    end
  end

  describe "separation from the chat window" do
    test "a skill run does not appear in the chat history", %{user: user} do
      assert {:ok, _} = SkillRun.start("draft_hsm", "draft something", user)

      assert {:ok, %{conversations: []}} = AskGlific.get_conversations(user)
    end

    test "a skill_run thread cannot be read back as a chat thread", %{user: user} do
      assert {:ok, _} = SkillRun.start("draft_hsm", "draft something", user)
      conversation = Repo.one!(from(c in Conversation, where: c.user_id == ^user.id))

      assert {:error, "Conversation not found"} =
               AskGlific.get_messages(to_string(conversation.id), user)
    end

    test "a chat question still appears in the chat history", %{user: user} do
      assert {:ok, _} = AskGlific.ask(%{query: "what is an HSM?"}, user)

      assert {:ok, %{conversations: [conversation]}} = AskGlific.get_conversations(user)
      assert conversation.name == "what is an HSM?"
    end
  end

  describe "the routing record" do
    test "a classified question records which skill was chosen, and its cost", %{user: user} do
      FakeProvider.script([FakeProvider.answer("draft_hsm"), FakeProvider.answer("a draft")])

      assert {:ok, _} = AskGlific.ask(%{query: "draft me a template"}, user)

      routing = Repo.one!(from(e in Event, where: e.type == :routing))
      assert routing.content == "draft_hsm"
      assert Map.has_key?(routing.data, "input_tokens")
      assert Map.has_key?(routing.data, "cost")
    end

    test "routing does not spend the step budget", %{user: user} do
      FakeProvider.script([FakeProvider.answer("draft_hsm"), FakeProvider.answer("a draft")])

      assert {:ok, _} = AskGlific.ask(%{query: "draft me a template"}, user)

      # user + routing + assistant, and the routing row does not collide with
      # either on (message_id, step).
      steps = Repo.all(from(e in Event, order_by: e.step, select: e.step))
      assert steps == Enum.uniq(steps)
    end
  end
end
