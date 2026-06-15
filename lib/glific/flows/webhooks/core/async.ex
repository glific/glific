defmodule Glific.Flows.Webhooks.Async do
  @moduledoc """
  `use` macro for asynchronous flow webhooks — Kaapi STT/TTS,
  unified-llm-call, unified-voice-llm-call. These park the flow context with
  `is_await_result: true` and are resumed by a callback to
  `flow_resume_controller`.

  Authors write `call/2`. They may also override `handle_resume/2` to shape
  the Kaapi callback payload (most webhooks rely on the default; voice LLM
  overrides it for `voice_post_process`). They may override
  `wait_time_default/0` if the default 60-second await window is wrong for
  that webhook.

  Failure reporting and latency telemetry are added by the Dispatcher (for
  execution) and by `Glific.Flows.Webhooks.Instrumentation` (for callback
  and timeout phases).
  """

  @doc """
  Injects the default async webhook implementation into the caller.

  Requires `:name` in `opts` and defines default `name/0`, `mode/0`,
  and `wait_time_default/0`.
  """
  defmacro __using__(opts) do
    webhook_name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Glific.Flows.Webhooks.Behaviour

      @webhook_name unquote(webhook_name)

      @doc "Returns the webhook name used in flow JSON URLs."
      @spec name() :: String.t()
      @impl true
      def name, do: @webhook_name

      @doc "Marks this webhook as asynchronous."
      @spec mode() :: :async
      @impl true
      def mode, do: :async

      @doc "Default timeout in seconds while awaiting callback resume."
      @spec wait_time_default() :: non_neg_integer()
      @impl true
      def wait_time_default, do: 60

      @doc """
      Observability/callback webhook name. Defaults to `name/0` (the flow-JSON node URL).
      Override in modules where the node URL differs from the AppSignal / Kaapi
      `request_metadata.webhook_name` string (e.g. UnifiedLlm, UnifiedVoiceLlm).
      """
      @spec webhook_name() :: String.t()
      @impl Glific.Flows.Webhooks.Behaviour
      def webhook_name, do: @webhook_name

      defoverridable wait_time_default: 0, webhook_name: 0
    end
  end
end
