defmodule Glific.AI.Evals.EchoEvalLiveTest do
  @moduledoc """
  The live tier of the `Glific.AI.Skills.Echo` eval — hits a real provider, following
  `Glific.AI.CodecLiveTest`'s key-reading and gating idiom. Never runs in CI (see
  `test/test_helper.exs`, which excludes `:eval_live` by default). Run deliberately, before a
  model change ships:

      ANTHROPIC_API_KEY=sk-... mix test --only eval_live

  Deliberately **not** built on `Glific.AI.EvalCase`: that template applies `@moduletag :eval`
  to every test in the using module, which would make `mix test --only eval` (the tier CI runs
  on every PR) pick up this live test too and fail it for want of a provider key. `Glific.AI.EvalCase.load_cases/1`
  is still reused directly — it is a plain function, not tied to the template's tagging.
  """

  use Glific.DataCase, async: false

  @moduletag :eval_live

  alias Glific.AI.EvalCase
  alias Glific.AI.Graders
  alias Glific.AI.Model.ReqLLM, as: LiveModel
  alias Glific.AI.Run
  alias Glific.Fixtures

  setup %{organization_id: organization_id} do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> raise "ANTHROPIC_API_KEY must be set to run :eval_live tests"
      "" -> raise "ANTHROPIC_API_KEY is empty"
      _key -> :ok
    end

    previous_adapter = Application.get_env(:glific, :ai_model_adapter)
    Application.put_env(:glific, :ai_model_adapter, LiveModel)

    on_exit(fn ->
      if previous_adapter,
        do: Application.put_env(:glific, :ai_model_adapter, previous_adapter),
        else: Application.delete_env(:glific, :ai_model_adapter)
    end)

    user = Fixtures.user_fixture(%{organization_id: organization_id, roles: ["manager"]})
    %{user: user}
  end

  test "a real provider echoes every recorded case's message verbatim", %{user: user} do
    for case_file <- EvalCase.load_cases("echo") do
      assert {:ok, outcome} = Run.sync("echo", case_file["input"], user)

      text = Graders.output_text(outcome.result)

      for expected <- case_file["expect"]["contains"] || [] do
        assert Graders.contains(text, expected) == :ok,
               "case #{inspect(case_file["name"])}: expected #{inspect(text)} to contain " <>
                 inspect(expected)
      end
    end
  end
end
