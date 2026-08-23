defmodule Glific.AI.Tool.RegistryTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Tool
  alias Glific.AI.Tool.Registry
  alias Glific.AI.Tools.{DescribeTable, QueryOrgData}

  describe "the production registry" do
    test "all/0 lists every registered tool module" do
      assert Enum.sort(Registry.all()) == Enum.sort([DescribeTable, QueryOrgData])
    end

    test "names/0 lists every registered tool name" do
      assert Enum.sort(Registry.names()) == ["describe_table", "query_org_data"]
    end

    test "fetch/1 resolves a registered name to its module" do
      assert {:ok, DescribeTable} == Registry.fetch("describe_table")
      assert {:ok, QueryOrgData} == Registry.fetch("query_org_data")
    end

    test "fetch/1 returns an error for an unregistered name" do
      assert {:error, :unknown_tool} == Registry.fetch("anything")
    end
  end

  describe "registered module conformance" do
    test "every registered tool exports every required callback" do
      required = Tool.behaviour_info(:callbacks) -- Tool.behaviour_info(:optional_callbacks)

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

    test "every registered name is unique" do
      names = Registry.all() |> Enum.map(& &1.name())
      assert Enum.uniq(names) == names
    end
  end
end
