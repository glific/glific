defmodule Glific.AI.Test.RuntimeSkill do
  @moduledoc """
  Minimal `Glific.AI.Skill` used by `Glific.AI.Runtime`/`Glific.AI.StepWorker` tests: one tool
  (`Glific.AI.Test.FixtureTool`), no gating, no structured output. `system_prompt/1` follows
  `Glific.AI.Skills.Echo`'s `input["message"]` contract, which `Glific.AI.Runtime` derives from
  a conversation's first stored message.

  Registered for tests only, via `config :glific, :ai_extra_skills` in `config/test.exs` —
  never referenced from `lib/glific/ai/skill/registry.ex` directly, since `test/support/`
  compiles after `lib/`.
  """

  use Glific.AI.Skill

  alias Glific.AI.Test.FixtureTool

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "runtime_fixture"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A fixture skill used only in Runtime/StepWorker tests."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(%{"message" => message}), do: "Respond helpfully to: #{message}"
  def system_prompt(_input), do: "Respond helpfully."

  @doc false
  @spec output_schema() :: nil
  @impl true
  def output_schema, do: nil

  @doc false
  @spec tools() :: [module()]
  @impl true
  def tools, do: [FixtureTool]

  @doc false
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end

defmodule Glific.AI.Test.GatedRuntimeSkill do
  @moduledoc """
  `Glific.AI.Skill` used to exercise the `{:on_final, ttl}` gate path in `Glific.AI.Runtime`
  and `Glific.AI.StepWorker` tests. `build_proposal/2` fails on demand — when
  `input["message"] == "trigger_proposal_error"` — so both the suspend path and the
  `build_proposal/2`-failure permanent-error path can be exercised without a second module.

  `on_decision/3` has two more on-demand failure clauses, keyed off the stored proposal's
  `input["message"]` (rather than a second registered skill — `config/test.exs`'s
  `:ai_extra_skills` list is owned by another workstream right now):

    * `"trigger_on_decision_raise"` — raises, to exercise `Glific.AI.Runtime.resume/2`'s
      broad `rescue`.
    * `"trigger_on_decision_malformed"` — returns a shape that is neither `{:done, _}` nor
      `{:continue, list}`, to exercise the "malformed return" `:permanent_error` path.

  Registered for tests only, via `config :glific, :ai_extra_skills` in `config/test.exs`.
  """

  use Glific.AI.Skill

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "gated_runtime_fixture"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A gated fixture skill used only in Runtime/StepWorker tests."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(%{"message" => message}), do: "Propose an action for: #{message}"
  def system_prompt(_input), do: "Propose an action."

  @doc false
  @spec output_schema() :: nil
  @impl true
  def output_schema, do: nil

  @doc false
  @spec gate_policy() :: Glific.AI.Skill.gate_policy()
  @impl true
  def gate_policy, do: {:on_final, 300}

  @doc false
  @spec build_proposal(term(), map()) :: {:ok, map()} | {:error, term()}
  @impl true
  def build_proposal(_result, %{"message" => "trigger_proposal_error"}),
    do: {:error, "build_proposal failed"}

  def build_proposal(result, input), do: {:ok, %{"input" => input, "result" => result}}

  @doc false
  @spec on_decision(:accepted | :rejected, term(), map()) ::
          {:done, map()} | {:continue, [ReqLLM.Message.t()]}
  @impl true
  def on_decision(_decision, _conversation, %{
        "input" => %{"message" => "trigger_on_decision_raise"}
      }),
      do: raise("on_decision blew up")

  def on_decision(_decision, _conversation, %{
        "input" => %{"message" => "trigger_on_decision_malformed"}
      }),
      do: :not_a_valid_on_decision_result

  def on_decision(:accepted, _conversation, proposal), do: {:done, proposal}

  def on_decision(:rejected, _conversation, proposal),
    do: {:continue, [ReqLLM.Context.user("That proposal was rejected: #{inspect(proposal)}")]}

  @doc false
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end

defmodule Glific.AI.Test.StructuredRuntimeSkill do
  @moduledoc """
  `Glific.AI.Skill` used to exercise the `output_schema/0` validation path in
  `Glific.AI.Runtime` tests: a non-nil schema routes the final answer through
  `Glific.AI.Model.object/3` instead of returning the raw assistant message.

  Registered for tests only, via `config :glific, :ai_extra_skills` in `config/test.exs`.
  """

  use Glific.AI.Skill

  @doc false
  @spec name() :: String.t()
  @impl true
  def name, do: "structured_runtime_fixture"

  @doc false
  @spec description() :: String.t()
  @impl true
  def description, do: "A structured-output fixture skill used only in Runtime tests."

  @doc false
  @spec model() :: String.t()
  @impl true
  def model, do: "anthropic:claude-sonnet-5"

  @doc false
  @spec system_prompt(map()) :: String.t()
  @impl true
  def system_prompt(%{"message" => message}), do: "Answer, structured, for: #{message}"
  def system_prompt(_input), do: "Answer, structured."

  @doc false
  @spec output_schema() :: keyword()
  @impl true
  def output_schema, do: [answer: [type: :string, required: true]]

  @doc false
  @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
  @impl true
  def validate_input(%{"message" => message} = input) when is_binary(message) and message != "",
    do: {:ok, input}

  def validate_input(_input), do: {:error, "message is required"}
end
