defmodule Glific.AI.EvalCase do
  @moduledoc """
  `Glific.DataCase`-equivalent setup for an AI skill eval, plus the harness for loading and
  running case files against `Glific.AI.Run.sync/3`.

  ## The two eval tiers

  This template applies `@moduletag :eval` to every test in the using module, so it is meant
  for **stubbed/recorded**-tier files only:

    * **`:eval`** (stubbed/recorded, built on this template) — scripts `Glific.AI.Model.Stub`
      and drives a skill through `Glific.AI.Run.sync/3`. Cheap, deterministic, runs in CI
      (`mix test --only eval`). It proves the harness and the skill's own logic (prompt
      building, tool wiring, output shape); it does **not** prove the underlying model produces
      a good answer, because the "model" here is a canned response the test itself queued.
    * **`:eval_live`** (live, its own file, plain `Glific.DataCase`) — hits a real provider,
      following `codec_live_test.exs`'s key-reading and gating idiom. Never runs in CI; run
      deliberately before a model change ships. See `Glific.AI.Graders.judge/3` for the
      LLM-as-judge grader, which only makes sense in this tier. A live-tier file must **not**
      `use Glific.AI.EvalCase` — this template's blanket `:eval` moduletag would make
      `mix test --only eval` pick it up too and fail it for want of a provider key.
      `load_cases/1` is a plain function, safe to call from a live-tier file directly (see
      `Glific.AI.Evals.EchoEvalLiveTest`).

  ## Case file shape

  A skill's eval cases live under `test/support/fixtures/ai/evals/<skill_name>/*.json`, one
  JSON file per case, loaded with `load_cases/1`:

      {
        "name": "repeats a short message verbatim",
        "input": {"message": "hello there"},
        "expect": {
          "contains": ["hello there"],
          "max_steps": 1
        }
      }

  Only `name` and `input` are contractual — `input` is passed straight to
  `Glific.AI.Run.sync/3` as the skill's input map. `expect` has no fixed schema: it is read
  directly by the eval test, which decides which `Glific.AI.Graders` functions apply to a given
  skill's output shape. Keeping it free-form avoids forcing every skill's eval file into one
  grader shape when skills differ in whether they use tools, structured output, or gating.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Glific.AI.Run
  alias Glific.{Fixtures, Partners, Repo}

  using do
    quote do
      @moduletag :eval

      import Glific.AI.EvalCase
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    organization_id = 1
    Repo.put_organization_id(organization_id)

    user = Fixtures.user_fixture(%{name: "AI Eval User", roles: ["manager"]})
    Repo.put_current_user(user)

    organization_id |> Partners.get_organization!() |> Partners.fill_cache()

    %{organization_id: organization_id, user: user}
  end

  @doc """
  Loads every case file for `skill_name` from
  `test/support/fixtures/ai/evals/<skill_name>/*.json`, sorted by filename for a deterministic
  run order.
  """
  @spec load_cases(String.t()) :: [map()]
  def load_cases(skill_name) do
    "test/support/fixtures/ai/evals/#{skill_name}/*.json"
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path -> path |> File.read!() |> Jason.decode!() end)
  end

  @doc """
  Runs one loaded case against `skill_name` through `Glific.AI.Run.sync/3`, as the current
  process's actor (set up by this template's `setup`).
  """
  @spec run_case(String.t(), map()) ::
          {:ok, Glific.AI.Run.outcome()} | {:error, Glific.AI.Run.error()}
  def run_case(skill_name, %{"input" => input}) do
    user = Repo.get_current_user()
    Run.sync(skill_name, input, user)
  end
end
