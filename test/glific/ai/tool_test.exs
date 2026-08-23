defmodule Glific.AI.ToolTest.DefaultsOnlyTool do
  @moduledoc false
  # Defines only the callbacks with no `use Glific.AI.Tool` default, so this module's
  # behaviour is exactly what the macro injects for `required_role/0` and `max_result_bytes/0`.
  use Glific.AI.Tool

  @impl true
  def name, do: "defaults_only_tool"
  @impl true
  def description, do: "Exercises the bare use Glific.AI.Tool defaults."
  @impl true
  def parameters, do: []
  @impl true
  def run(_args, _context), do: {:ok, %{}}
end

defmodule Glific.AI.ToolTest do
  use ExUnit.Case, async: true

  alias Glific.AI.Test.FixtureTool
  alias Glific.AI.Tool
  alias Glific.AI.Tool.Context
  alias Glific.AI.ToolTest.DefaultsOnlyTool
  alias Glific.Users.User

  describe "use Glific.AI.Tool defaults" do
    test "required_role/0 and max_result_bytes/0 fall back to the documented defaults" do
      assert DefaultsOnlyTool.required_role() == :staff
      assert DefaultsOnlyTool.max_result_bytes() == 32_768
    end
  end

  describe "use Glific.AI.Tool overrides" do
    test "a fixture tool runs against an explicit Context, never process state" do
      context = %Context{
        organization_id: 1,
        user: %User{id: 1},
        request_id: "req-1",
        step_index: 0
      }

      assert {:ok, %{query: "flows", organization_id: 1}} =
               FixtureTool.run(%{"query" => "flows"}, context)

      assert {:error, "query is required"} = FixtureTool.run(%{}, context)
    end
  end

  describe "behaviour conformance" do
    test "every fixture tool exports every required (non-optional) callback" do
      required = Tool.behaviour_info(:callbacks) -- Tool.behaviour_info(:optional_callbacks)

      for module <- [FixtureTool, DefaultsOnlyTool] do
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
end
