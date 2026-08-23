defmodule Glific.AI.SkillTest.DefaultsOnlySkill do
  @moduledoc false
  # Defines only the callbacks with no `use Glific.AI.Skill` default, so this module's
  # behaviour is exactly what the macro injects for everything else.
  use Glific.AI.Skill

  @impl true
  def name, do: "defaults_only"
  @impl true
  def description, do: "Exercises the bare use Glific.AI.Skill defaults."
  @impl true
  def model, do: "anthropic:claude-sonnet-5"
  @impl true
  def system_prompt(_input), do: "static prompt"
  @impl true
  def output_schema, do: nil
end

defmodule Glific.AI.SkillTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Skill
  alias Glific.AI.Skills.Echo
  alias Glific.AI.SkillTest.DefaultsOnlySkill
  alias Glific.AI.Test.{FixtureSkill, FixtureTool}

  describe "use Glific.AI.Skill defaults" do
    test "a skill that only defines the callbacks without a default gets the documented ones" do
      assert DefaultsOnlySkill.tools() == []
      assert DefaultsOnlySkill.max_steps() == 8
      assert DefaultsOnlySkill.gate_policy() == :none
      assert DefaultsOnlySkill.required_role() == :staff
      assert DefaultsOnlySkill.feature_flag() == nil
      assert DefaultsOnlySkill.provider() == :anthropic
      assert DefaultsOnlySkill.stream_thinking?() == false
      assert DefaultsOnlySkill.cache_ttl() == nil
      assert DefaultsOnlySkill.initial_messages(%{}) == []
      assert DefaultsOnlySkill.validate_input(%{"anything" => 1}) == {:ok, %{"anything" => 1}}
    end
  end

  describe "use Glific.AI.Skill overrides" do
    test "every default can be overridden" do
      assert FixtureSkill.tools() == [FixtureTool]
      assert FixtureSkill.max_steps() == 3
      assert FixtureSkill.gate_policy() == {:on_final, 300}
      assert FixtureSkill.required_role() == :manager
      assert FixtureSkill.feature_flag() == :ai_fixture_skill_enabled
      assert FixtureSkill.provider() == :google
      assert FixtureSkill.stream_thinking?() == true
      assert FixtureSkill.cache_ttl() == "1h"
    end

    test "validate_input/1 override replaces the default pass-through" do
      assert {:ok, %{"topic" => "flows"}} = FixtureSkill.validate_input(%{"topic" => "flows"})
      assert {:error, _reason} = FixtureSkill.validate_input(%{})
    end

    test "initial_messages/1 override returns real ReqLLM messages" do
      assert [%ReqLLM.Message{role: :user}] = FixtureSkill.initial_messages(%{"topic" => "flows"})
    end

    test "the optional gating callbacks work end to end" do
      assert {:ok, proposal} = FixtureSkill.build_proposal(%{answer: "42"}, %{"topic" => "flows"})

      assert {:done, ^proposal} =
               FixtureSkill.on_decision(:accepted, :fake_conversation, proposal)

      assert {:continue, [%ReqLLM.Message{role: :user}]} =
               FixtureSkill.on_decision(:rejected, :fake_conversation, proposal)
    end
  end

  describe "behaviour conformance" do
    test "every skill exports every required (non-optional) callback" do
      required =
        Skill.behaviour_info(:callbacks) -- Skill.behaviour_info(:optional_callbacks)

      for module <- [Echo, FixtureSkill, DefaultsOnlySkill] do
        # function_exported?/3 only consults already-loaded code; it does not load a module
        # that mix test skipped recompiling in this run, so it must be loaded explicitly first.
        Code.ensure_loaded!(module)

        for {function, arity} <- required do
          assert function_exported?(module, function, arity),
                 "#{inspect(module)} does not export #{function}/#{arity}"
        end
      end
    end
  end

  describe "system_prompt/1 determinism" do
    test "returns the same string for the same input, every time" do
      input = %{"message" => "hello"}
      assert Echo.system_prompt(input) == Echo.system_prompt(input)

      assert FixtureSkill.system_prompt(%{"topic" => "flows"}) ==
               FixtureSkill.system_prompt(%{"topic" => "flows"})
    end
  end
end
