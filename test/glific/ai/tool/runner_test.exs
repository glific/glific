defmodule Glific.AI.Tool.RunnerTest.Skill do
  @moduledoc false
  # A local skill wrapping the tools this test file needs beyond `Glific.AI.Test.FixtureSkill`
  # (whose `tools/0` is fixed to `[FixtureTool]`) — the slow/large fixture tools plus the
  # production `QueryOrgData`, so its role gate can be exercised end to end.
  use Glific.AI.Skill

  alias Glific.AI.Test.{FixtureLargeTool, FixtureSlowTool}
  alias Glific.AI.Tools.QueryOrgData

  @impl true
  def name, do: "runner_test_skill"
  @impl true
  def description, do: "Wraps fixture and production tools for Runner tests."
  @impl true
  def model, do: "anthropic:claude-sonnet-5"
  @impl true
  def system_prompt(_input), do: "test"
  @impl true
  def output_schema, do: nil
  @impl true
  def tools, do: [FixtureSlowTool, FixtureLargeTool, QueryOrgData]
end

defmodule Glific.AI.Tool.RunnerTest do
  use Glific.DataCase, async: false

  alias Glific.AI.Actor
  alias Glific.AI.Test.FixtureSkill
  alias Glific.AI.Tool.Context
  alias Glific.AI.Tool.Runner
  alias Glific.AI.Tool.RunnerTest.Skill
  alias Glific.Fixtures
  alias Glific.Repo

  setup %{organization_id: organization_id} = tags do
    roles = Map.get(tags, :roles, ["manager"])
    user = Fixtures.user_fixture(%{organization_id: organization_id, roles: roles})
    acting_user = Actor.put!(organization_id, user.id)

    context = %Context{
      organization_id: organization_id,
      user: acting_user,
      request_id: "req-runner-test",
      step_index: 0
    }

    %{context: context, organization_id: organization_id, user: acting_user}
  end

  describe "call/4 — allow-list" do
    test "rejects a tool name the skill does not list, without crashing", %{context: context} do
      assert {:error, message} = Runner.call("does_not_exist", %{}, context, FixtureSkill)
      assert message =~ "Unknown tool"
    end

    test "runs a tool the skill lists", %{context: context} do
      assert {:ok, %{query: "flows", organization_id: organization_id}} =
               Runner.call("fixture_tool", %{"query" => "flows"}, context, FixtureSkill)

      assert organization_id == context.organization_id
    end
  end

  describe "call/4 — role gate" do
    @describetag roles: ["staff"]

    test "rejects a tool whose required_role/0 outranks the acting user", %{context: context} do
      assert {:error, message} =
               Runner.call(
                 "query_org_data",
                 %{"table" => "contacts", "limit" => 1},
                 context,
                 Skill
               )

      assert message =~ "permission"
    end
  end

  describe "call/4 — role gate, sufficient rank" do
    test "runs a manager-gated tool for a manager", %{context: context} do
      assert {:ok, rows} =
               Runner.call(
                 "query_org_data",
                 %{"table" => "contacts", "fields" => ["id"], "limit" => 1},
                 context,
                 Skill
               )

      assert is_list(rows)
    end
  end

  describe "call/4 — parameter validation" do
    test "returns a model-visible error for a wrong argument type, not a crash", %{
      context: context
    } do
      assert {:error, message} =
               Runner.call("fixture_tool", %{"query" => 123}, context, FixtureSkill)

      assert message =~ "Invalid arguments"
    end

    test "returns a model-visible error for a missing required argument", %{context: context} do
      assert {:error, message} = Runner.call("fixture_tool", %{}, context, FixtureSkill)
      assert message =~ "Invalid arguments"
    end
  end

  describe "call/4 — timeout" do
    setup do
      original = Application.get_env(:glific, Glific.AI.Tool.Runner)
      Application.put_env(:glific, Glific.AI.Tool.Runner, timeout_ms: 50)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:glific, Glific.AI.Tool.Runner)
          value -> Application.put_env(:glific, Glific.AI.Tool.Runner, value)
        end
      end)

      :ok
    end

    test "returns a timeout error instead of hanging when a tool outruns the budget", %{
      context: context
    } do
      assert {:error, message} =
               Runner.call("fixture_slow_tool", %{"sleep_ms" => 500}, context, Skill)

      assert message =~ "timed out"
    end
  end

  describe "call/4 — result size cap" do
    test "truncates an oversized result with an explicit marker", %{context: context} do
      assert {:ok, result} = Runner.call("fixture_large_tool", %{}, context, Skill)

      assert is_list(result)
      assert length(result) < 200
      assert List.last(result) =~ ~r/^\[truncated: \d+ more rows\]$/
      assert byte_size(Jason.encode!(result)) <= 300
    end
  end

  describe "call/4 — the root_user trap (Glific.AI.Actor.assert!/2)" do
    test "raises instead of silently running as org root when process state drifts", %{
      context: context,
      organization_id: organization_id
    } do
      # Exactly what would happen if the conventional Oban-worker preamble crept in above the
      # agent loop — see Glific.AI.ActorTest for the same scenario against Actor directly.
      Repo.put_process_state(organization_id)

      assert_raise Actor.Error, ~r/organization root user/, fn ->
        Runner.call("fixture_tool", %{"query" => "x"}, context, FixtureSkill)
      end
    end
  end
end
