defmodule Glific.AI.Skill.RegistryTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Skill
  alias Glific.AI.Skill.Registry
  alias Glific.AI.Skills.Echo

  describe "fetch/1" do
    test "finds a registered skill by name" do
      assert {:ok, Echo} == Registry.fetch("echo")
    end

    test "returns an error for an unknown name" do
      assert {:error, :unknown_skill} == Registry.fetch("does_not_exist")
    end
  end

  describe "all/0 and names/0" do
    test "all/0 lists every registered module" do
      assert Echo in Registry.all()
    end

    test "names/0 lists every registered name, one per module in all/0" do
      assert length(Registry.names()) == length(Registry.all())
      assert "echo" in Registry.names()
    end

    test "every registered name is unique" do
      names = Registry.all() |> Enum.map(& &1.name())
      assert Enum.uniq(names) == names
    end
  end

  describe "registered module conformance" do
    test "every registered skill exports every required (non-optional) callback" do
      required = Skill.behaviour_info(:callbacks) -- Skill.behaviour_info(:optional_callbacks)

      for module <- Registry.all() do
        # function_exported?/3 only consults already-loaded code; it does not load a module
        # that mix test skipped recompiling in this run, so it must be loaded explicitly first.
        Code.ensure_loaded!(module)

        for {function, arity} <- required do
          assert function_exported?(module, function, arity),
                 "#{inspect(module)} does not export #{function}/#{arity}"
        end
      end
    end

    test "every registered skill's name/0 matches the key it is registered under" do
      for module <- Registry.all() do
        assert {:ok, ^module} = Registry.fetch(module.name())
      end
    end
  end
end
