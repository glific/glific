defmodule Glific.AI.Skill do
  @moduledoc """
  Behaviour for a single AI agent skill: the model, prompt, tools, and gating a runtime
  step needs to run one unit of agent work end to end.

  A skill is a pure description — it names a provider/model, builds a system prompt from
  validated input, lists the `Glific.AI.Tool` modules it may call, and states whether its
  final result requires human approval before anything is applied
  (see `gate_policy/0`). Nothing in this module touches the database, Oban, or HTTP; the
  runtime that drives a skill through its steps, persists messages, and executes tools
  lives elsewhere.

  Implement a skill with `use Glific.AI.Skill`, which injects `@behaviour` and defaults for
  every callback that has a reasonable one. Override only what the skill needs to say for
  itself — see `Glific.AI.Skills.Echo` for the minimal shape.

  ## Prompt caching and determinism

  `system_prompt/1` is called on every step of a run, and provider prompt caching keys off a
  byte-identical prefix between calls. A prompt that embeds a timestamp, "today is …", the
  result of `Enum.shuffle/1`, or text built from map iteration order will still *work* — the
  model still answers — but it silently pays full price on every call instead of a cached-read
  discount, with no error and no functional symptom to point at the cause. Build the prompt
  only from `input` and from constants baked into the skill module.
  """

  @typedoc "The legacy role hierarchy this codebase authorizes against — see `Glific.Users.Roles`."
  @type role :: :staff | :manager | :admin | :glific_admin

  @typedoc """
  When a skill's final result needs a human decision before anything downstream acts on it.

  `:none` — the result is applied immediately. `{:on_final, ttl_seconds}` — the proposal built
  by `build_proposal/2` is held for `ttl_seconds` awaiting `on_decision/3`.
  """
  @type gate_policy :: :none | {:on_final, ttl_seconds :: pos_integer()}

  @typedoc "A schema for structured output, in any form `ReqLLM.generate_object/4` accepts."
  @type output_schema :: keyword() | map() | Zoi.Type.t() | nil

  @doc "Unique skill name, snake_case. Used as the registry key and as durable stored state."
  @callback name() :: String.t()

  @doc "Human-readable summary of what the skill does."
  @callback description() :: String.t()

  @doc "The provider this skill talks to."
  @callback provider() :: atom()

  @doc ~S(A req_llm model spec, e.g. "anthropic:claude-sonnet-5".)
  @callback model() :: String.t()

  # Must be deterministic for the same `input` — no timestamps, no "today is…", no
  # Enum.shuffle, no map-iteration-order leaking into the rendered text. See the moduledoc:
  # a non-deterministic prompt defeats provider prompt caching with no functional symptom.
  @doc "Builds the system prompt from the validated input map. Must be deterministic."
  @callback system_prompt(input :: map()) :: String.t()

  @doc "Seed messages placed before the first user turn, e.g. worked examples. Defaults to `[]`."
  @callback initial_messages(input :: map()) :: [ReqLLM.Message.t()]

  @doc "Tool modules this skill may call. `[]` for a one-shot skill with no tool use."
  @callback tools() :: [module()]

  @doc "Schema for structured output, or `nil` for free-text output."
  @callback output_schema() :: output_schema()

  @doc "Validates and normalises caller-supplied input before it reaches `system_prompt/1`."
  @callback validate_input(input :: map()) :: {:ok, map()} | {:error, String.t()}

  @doc "Upper bound on tool-call steps for one run, including the final answer step."
  @callback max_steps() :: pos_integer()

  @doc "Whether the skill's final result requires a human decision before it takes effect."
  @callback gate_policy() :: gate_policy()

  @doc """
  Builds the proposal held for a human decision when `gate_policy/0` is `{:on_final, _}`.

  Takes the skill's final result and the validated input; returns the map to persist and show
  to the reviewer.
  """
  @callback build_proposal(result :: term(), input :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Resumes a gated run after a human decision.

  `conversation` is whatever conversation-ish struct the runtime passes through — this
  behaviour treats it as opaque. Returns `{:done, result}` to end the run, or
  `{:continue, messages}` to feed more messages back into the model.
  """
  @callback on_decision(
              decision :: :accepted | :rejected,
              conversation :: term(),
              proposal :: map()
            ) :: {:done, map()} | {:continue, [ReqLLM.Message.t()]}

  @doc "Minimum role required to invoke this skill. See `Glific.Users.Roles`."
  @callback required_role() :: role()

  @doc "Feature flag gating this skill, or `nil` if it is always available."
  @callback feature_flag() :: atom() | nil

  @doc """
  Whether reasoning text is streamed to the client.

  Streaming the thinking `signature` itself is never correct regardless of this setting — it
  is not user-facing content, and it must survive into storage (or the next Anthropic turn
  responds 400). Only the human-readable reasoning text is subject to this flag.
  """
  @callback stream_thinking?() :: boolean()

  @doc """
  Prompt-cache TTL for this skill's cache breakpoints, or `nil` for the provider default
  (~5 minutes). Conversational skills where the gap between turns is human thinking time
  should use `"1h"` so a slow reply doesn't fall out of cache.
  """
  @callback cache_ttl() :: nil | String.t()

  @optional_callbacks initial_messages: 1, build_proposal: 2, on_decision: 3

  @doc """
  Whether `skill`'s declared `feature_flag/0` is enabled for `organization_id`.

  Lives here rather than in each entry point because a skill is startable from more than one:
  `Glific.AI.Run.sync/3` for a synchronous caller, `GlificWeb.Resolvers.AI.start_ai_request/3`
  for the durable path. A flag enforced in only one of them is a flag that does nothing, since
  the callback itself is just a declaration — nothing in the runtime reads it otherwise.
  """
  @spec enabled?(module(), non_neg_integer()) :: boolean()
  def enabled?(skill, organization_id) do
    case skill.feature_flag() do
      nil -> true
      flag -> FunWithFlags.enabled?(flag, for: %{organization_id: organization_id})
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Glific.AI.Skill

      @doc false
      @spec tools() :: [module()]
      @impl true
      def tools, do: []

      @doc false
      @spec max_steps() :: pos_integer()
      @impl true
      def max_steps, do: 8

      @doc false
      @spec gate_policy() :: Glific.AI.Skill.gate_policy()
      @impl true
      def gate_policy, do: :none

      @doc false
      @spec required_role() :: Glific.AI.Skill.role()
      @impl true
      def required_role, do: :staff

      @doc false
      @spec feature_flag() :: atom() | nil
      @impl true
      def feature_flag, do: nil

      @doc false
      @spec provider() :: atom()
      @impl true
      def provider, do: :anthropic

      @doc false
      @spec stream_thinking?() :: boolean()
      @impl true
      def stream_thinking?, do: false

      @doc false
      @spec cache_ttl() :: nil | String.t()
      @impl true
      def cache_ttl, do: nil

      @doc false
      @spec initial_messages(map()) :: [ReqLLM.Message.t()]
      @impl true
      def initial_messages(_input), do: []

      @doc false
      @spec validate_input(map()) :: {:ok, map()} | {:error, String.t()}
      @impl true
      def validate_input(input), do: {:ok, input}

      defoverridable tools: 0,
                     max_steps: 0,
                     gate_policy: 0,
                     required_role: 0,
                     feature_flag: 0,
                     provider: 0,
                     stream_thinking?: 0,
                     cache_ttl: 0,
                     initial_messages: 1,
                     validate_input: 1
    end
  end
end
