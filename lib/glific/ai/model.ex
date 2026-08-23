defmodule Glific.AI.Model do
  @moduledoc """
  Behaviour for a single model call: the seam between the agent runtime and whichever library
  actually talks to a provider.

  `Glific.AI.Model` and `Glific.AI.Model.Result` are, with `Glific.AI.Codec`, the only modules
  permitted to reference `ReqLLM.*`. Everything above this layer — skills, tools, the runtime
  that drives a run through its steps — speaks `Glific.AI.Model.Result` and the shared
  `ReqLLM.Context`/`ReqLLM.Message` vocabulary already established by `Glific.AI.Codec`, never
  a provider SDK type or a provider response shape directly.

  Two implementations exist:

    * `Glific.AI.Model.ReqLLM` — wraps `ReqLLM.Generation`, the real provider calls.
    * `Glific.AI.Model.Stub` — deterministic, scriptable, makes no network call. Every test above
      this layer uses it; see `test/CLAUDE.md`.

  `chat/2` and `object/3` delegate to whichever adapter `config :glific, :ai_model_adapter`
  names, defaulting to `Glific.AI.Model.ReqLLM`. Swap it for `Glific.AI.Model.Stub` in
  `config/test.exs`, the same way `upload_adapter` is swapped for Kaapi uploads.
  """

  alias Glific.AI.Model.Result
  alias Glific.AI.Skill
  alias ReqLLM.Context

  @doc "Sends `context` to the model and returns its reply as a `Glific.AI.Model.Result`."
  @callback chat(context :: Context.t(), opts :: keyword()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc "Sends `context` to the model and returns structured output validated against `schema`."
  @callback object(context :: Context.t(), schema :: Skill.output_schema(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc "Delegates to the configured adapter's `chat/2`."
  @spec chat(Context.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def chat(%Context{} = context, opts \\ []), do: adapter().chat(context, opts)

  @doc "Delegates to the configured adapter's `object/3`."
  @spec object(Context.t(), Skill.output_schema(), keyword()) :: {:ok, map()} | {:error, term()}
  def object(%Context{} = context, schema, opts \\ []),
    do: adapter().object(context, schema, opts)

  @spec adapter() :: module()
  defp adapter, do: Application.get_env(:glific, :ai_model_adapter, Glific.AI.Model.ReqLLM)
end
