defmodule Glific.AI.Evals.EchoEvalTest do
  @moduledoc """
  The first eval, for `Glific.AI.Skills.Echo` — stubbed/recorded tier only. See
  `Glific.AI.EvalCase` for the two-tier design; the live tier lives in the separate
  `Glific.AI.Evals.EchoEvalLiveTest` (`echo_eval_live_test.exs`), deliberately **not** built on
  `Glific.AI.EvalCase` — that template's `@moduletag :eval` would otherwise apply to every test
  in the file, including a live one, and `mix test --only eval` (the tier CI runs) would then
  try to run the live test too and fail for want of a provider key.

  Scripts `Glific.AI.Model.Stub` to return exactly the input message back (the ideal echo
  behaviour) and asserts the deterministic graders against it. This proves the harness itself
  works end to end — `Run.sync/3` drives the skill, the transcript is readable back out, the
  graders can assert on it — and that `Echo`'s own contract (no tools, no schema, `max_steps`)
  holds. It proves nothing about whether a *real* model actually echoes verbatim; the "model"
  here is a canned response this test wrote.
  """

  use Glific.AI.EvalCase, async: false

  alias Glific.AI.EvalCase
  alias Glific.AI.Graders
  alias Glific.AI.Model.Stub
  alias Glific.AI.Run

  setup do
    start_supervised!(Stub)
    :ok
  end

  test "matches every recorded case's deterministic expectations", %{user: user} do
    for case_file <- EvalCase.load_cases("echo") do
      Stub.queue_text(case_file["input"]["message"])

      assert {:ok, outcome} = Run.sync("echo", case_file["input"], user)

      text = Graders.output_text(outcome.result)
      assert_contains(case_file, text)
      assert_max_steps(case_file, outcome)
    end
  end

  defp assert_contains(case_file, text) do
    for expected <- case_file["expect"]["contains"] || [] do
      case Graders.contains(text, expected) do
        :ok -> :ok
        {:error, reason} -> flunk("case #{inspect(case_file["name"])}: #{reason}")
      end
    end
  end

  defp assert_max_steps(case_file, outcome) do
    case case_file["expect"]["max_steps"] do
      nil ->
        :ok

      max ->
        case Graders.max_steps(outcome, max) do
          :ok -> :ok
          {:error, reason} -> flunk("case #{inspect(case_file["name"])}: #{reason}")
        end
    end
  end
end
