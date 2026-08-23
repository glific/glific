defmodule Glific.AI.Telemetry do
  @moduledoc """
  Wires the AI runtime's observability into the application: an OpenTelemetry GenAI span per
  model call (exported to Langfuse when configured) plus AppSignal metrics from `req_llm`'s
  native `:telemetry` events. Called once from `Glific.Application.start/2`.

  The two layers are attached independently, on purpose.

  **AppSignal metrics always attach.** They report counts, durations and token totals next to
  the rest of Glific's telemetry, cost nothing to run, and send no content anywhere new. Gating
  them on Langfuse credentials would mean LLM health is invisible on every deployment that
  hasn't signed up for a third-party tracing vendor — which is the opposite of the point.

  **Tracing is optional.** The OpenTelemetry bridge attaches only when
  `config :glific, :ai_telemetry, enabled: true` (the default is `false`, see
  `config/config.exs`) and the OpenTelemetry SDK is available — no crash and no noisy log
  otherwise. `config/runtime.exs` flips it on only once both `LANGFUSE_PUBLIC_KEY` and
  `LANGFUSE_SECRET_KEY` are present, so a dev box with no Langfuse credentials behaves exactly
  as it does without this module.

  See `Glific.AI.Telemetry.OTelAdapter` for the redaction allow-list applied to every span
  attribute before export, and `Glific.AI.Telemetry.Context` for how caller identity reaches a
  span from a `:telemetry` handler that has no argument to carry it.
  """

  alias Glific.AI.Telemetry.Handlers
  alias Glific.AI.Telemetry.OTelAdapter

  @handler_id "glific-ai"
  @prune_ttl_ms :timer.minutes(5)

  @doc """
  Attaches the AppSignal telemetry handlers always, and the OpenTelemetry bridge when tracing
  is enabled and the OpenTelemetry SDK is available.
  """
  @spec attach() :: :ok
  def attach do
    Handlers.attach()
    if tracing_enabled?(), do: attach_bridge(), else: :ok
  end

  @spec tracing_enabled?() :: boolean()
  defp tracing_enabled? do
    :glific
    |> Application.get_env(:ai_telemetry, [])
    |> Keyword.get(:enabled, false)
  end

  @spec attach_bridge() :: :ok
  defp attach_bridge do
    # `content: :none` is passed explicitly even though it is the bridge's own default — the
    # explicit argument is what makes the privacy posture visible at this call site, which is
    # what a reviewer checks.
    ReqLLM.OpenTelemetry.attach(@handler_id,
      adapter: OTelAdapter,
      content: :none,
      langfuse: true
    )

    :ok
  end

  @doc """
  Prunes in-flight OpenTelemetry span entries older than the stale-span TTL.

  Meant to be driven by a `:telemetry_poller` measurement (see `Glific.Application`) so a
  process that dies mid-request doesn't leak its span entry in the bridge's ETS table forever.
  """
  @spec prune_stale_spans() :: non_neg_integer()
  def prune_stale_spans, do: ReqLLM.OpenTelemetry.prune_stale_spans(@handler_id, @prune_ttl_ms)
end
