defmodule Glific.AI.SkillsTest do
  use Glific.DataCase

  alias FunWithFlags.Store.Cache

  alias Glific.AI.{Router, Skills, Tools}
  alias Glific.Fixtures
  alias Glific.AI.Skills.{DraftHSM, Knowledge}

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, Glific.FakeProvider.start()))

    # AI.generate/3 checks the flag on every call, and FunWithFlags state is
    # global, so set it here rather than inheriting whatever ran before.
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    # The flag row is rolled back with the transaction, but its ETS cache is not,
    # so a later test that expects the flag off would read a stale true. Only the
    # cache is flushed here: `on_exit` runs after the sandbox connection is
    # checked in, so it cannot touch the database.
    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkout(Glific.Repo)
      FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})
      Cache.flush()
    end)

    on_exit(fn ->
      Glific.FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    :ok
  end

  describe "the catalogue" do
    test "every skill declares a name, a description and a prompt" do
      names = Enum.map(Skills.all(), & &1.name())
      assert names == Enum.uniq(names)

      for skill <- Skills.all() do
        assert is_binary(skill.name()) and skill.name() != ""
        assert is_binary(skill.description()) and skill.description() != ""
        assert is_binary(skill.prompt()) and skill.prompt() != ""
        assert {:ok, ^skill} = Skills.fetch(skill.name())
      end
    end

    test "an unknown skill is refused rather than silently defaulted" do
      assert {:error, message} = Skills.fetch("no_such_skill")
      assert message == ~s(There is no skill called "no_such_skill".)
    end

    test "a blank name is refused too, so it cannot stand in for a choice" do
      assert {:error, _} = Skills.fetch(nil)
      assert {:error, _} = Skills.fetch("")
    end

    test "the default is the broad read-only skill, and is asked for by name" do
      assert Skills.default() == Knowledge
      assert {:ok, Knowledge} = Skills.fetch("knowledge")
    end

    test "a narrowed skill sends far fewer tool schemas than the broad one" do
      broad = Skills.tools(Knowledge)
      narrow = Skills.tools(DraftHSM)

      assert length(broad) == length(Tools.all())
      assert length(narrow) < length(broad)

      # Every tool a skill declares must be one the gateway can actually run.
      for spec <- narrow, do: assert({:ok, {_module, ^spec}} = Tools.fetch(spec.name))
    end

    test "a tool outside the skill's set is refused when the model names it anyway" do
      # A model can name a tool it knows from training rather than from the
      # schemas it was sent, so narrowing has to hold at execution too.
      user = Fixtures.user_fixture(%{organization_id: 1})

      refute Enum.any?(Skills.tools(DraftHSM), &(&1.name == "list_contacts"))

      assert {:error, message} =
               Tools.run("list_contacts", %{}, user, Skills.modules(DraftHSM))

      assert message =~ "list_contacts"
    end
  end

  describe "classifying intent" do
    test "the named skill is used when the model returns one" do
      Glific.FakeProvider.script([Glific.FakeProvider.answer("draft_hsm")])

      assert {DraftHSM, usage, true} = Router.classify(1, "write me a reminder template")
      assert usage.input_tokens > 0
    end

    test "surrounding whitespace and casing do not stop it matching" do
      Glific.FakeProvider.script([Glific.FakeProvider.answer("  Draft_HSM \n")])

      assert {DraftHSM, _, true} = Router.classify(1, "draft something")
    end

    test "a skill the model invented falls back to the default" do
      Glific.FakeProvider.script([Glific.FakeProvider.answer("book_me_a_flight")])

      assert {Knowledge, _, true} = Router.classify(1, "anything")
    end

    test "a provider failure falls back to the default and costs nothing" do
      Glific.FakeProvider.stop()

      assert {Knowledge, usage, false} = Router.classify(1, "anything")
      assert usage == %{input_tokens: 0, output_tokens: 0, cost: 0}
    end

    test "classifying uses the classifier model, not the one that answers" do
      config = Application.get_env(:glific, Glific.AI, [])

      Application.put_env(
        :glific,
        Glific.AI,
        Keyword.merge(config,
          model: "anthropic:claude-sonnet-4-5",
          classifier_model: "anthropic:claude-haiku-4-5"
        )
      )

      on_exit(fn -> Application.put_env(:glific, Glific.AI, config) end)

      Glific.FakeProvider.script([Glific.FakeProvider.answer("knowledge")])
      Router.classify(1, "what flows do I have?")

      body = Glific.FakeProvider.seen() |> List.last() |> Jason.decode!()
      assert body["model"] =~ "haiku"
    end

    test "classifying sends no tools, so it stays cheap" do
      Glific.FakeProvider.script([Glific.FakeProvider.answer("knowledge")])
      Router.classify(1, "what flows do I have?")

      body = Glific.FakeProvider.seen() |> List.last() |> Jason.decode!()
      refute Map.has_key?(body, "tools")
    end
  end
end
