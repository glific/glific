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

  @doc false
  defmacro __using__(opts) do
    webhook_name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Glific.Flows.Webhooks.Behaviour

      @webhook_name unquote(webhook_name)

      @impl true
      def name, do: @webhook_name

      @impl true
      def mode, do: :async

      @impl true
      def wait_time_default, do: 60

      defoverridable wait_time_default: 0
    end
  end
end
