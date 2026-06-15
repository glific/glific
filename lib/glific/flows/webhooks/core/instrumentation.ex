defmodule Glific.Flows.Webhooks.Instrumentation do
  @moduledoc """
  Centralised failure reporting and latency telemetry for flow webhooks.

  This is the single home for cross-cutting observability in the
  `Glific.Flows.Webhooks` subsystem. Every webhook dispatched through
  `Glific.Flows.Webhooks.Dispatcher` is wrapped by `around/3`, which:

    * Times the call and emits a `flow_webhook_latency` AppSignal distribution
      tagged with `webhook_name`, `mode`, and `outcome`.
    * Increments a `Glific.Metrics` counter for success/failure so per-webhook
      ratios are chartable.
    * Reports `%{success: false}` results and rescued exceptions via
      `Glific.log_exception/1` under the `flow_webhooks` namespace.

  Callback-time and timeout-time reporting (the other two facets of webhook
  failure) live in `report_callback_failure/2` and `report_timeout/1` here —
  same exception shapes, same `flow_webhooks` namespace.

  Exception types are `Glific.Flows.Webhooks.Errors.{SystemError, TimeoutError}`
  — independent from the legacy `Glific.Flows.Webhook.*` exception classes.
  """

  alias Glific.Flows.Webhooks.Errors
  alias Glific.Metrics

  require Logger

  @typedoc """
  Tags attached to the centralised AppSignal report. Keys are optional so each
  call site supplies what it has.
  """
  @type tags :: %{
          optional(:organization_id) => non_neg_integer() | nil,
          optional(:webhook_name) => String.t() | nil,
          optional(:flow_id) => non_neg_integer() | nil,
          optional(:contact_id) => non_neg_integer() | nil,
          optional(:webhook_log_id) => non_neg_integer() | nil,
          optional(:http_status) => integer() | nil,
          optional(:reason) => String.t() | nil,
          optional(:error_type) => String.t() | nil
        }

  @doc """
  Wrap a webhook invocation with failure reporting + latency telemetry.

  `module` is the webhook module (implements `Glific.Flows.Webhooks.Behaviour`);
  `ctx` carries `:organization_id` (and optional metadata for richer tags);
  `fun` is the zero-arity callback that actually invokes the webhook.

  Returns the result of `fun.()` unchanged. Exceptions are reported and then
  re-raised — callers downstream of the dispatcher see the same exceptions they
  would have seen without this wrapper.
  """
  @spec around(module(), map(), (-> any())) :: any()
  def around(module, ctx, fun) when is_atom(module) and is_map(ctx) and is_function(fun, 0) do
    webhook_name = module.name()
    mode = module.mode()
    start = System.monotonic_time()

    try do
      result = fun.()
      emit_latency(webhook_name, mode, start, :ok)
      track_metrics(webhook_name, result)
      maybe_report_webhook_failure(result, webhook_name, ctx)
      result
    rescue
      exception ->
        emit_latency(webhook_name, mode, start, :error)
        track_metrics(webhook_name, nil)
        report_webhook_failure(webhook_name, ctx, nil, Exception.message(exception))
        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Wrap an async webhook invocation with failure reporting + latency telemetry.

  Behaviour:
  - `{:wait, ctx, []}` — flow parked successfully. Emit async latency with outcome `:ok`.
    Do NOT increment success/failure metric here (the count happens at callback time in
    `FlowResumeController`, so we avoid double-counting).
  - `{:ok, ctx, [_failure_msg]}` — immediate failure (missing creds, body error, enqueue
    error). Emit async latency with outcome `:error`, increment failure metric, report a
    `SystemError` via `Glific.log_exception/1`.
  - rescue — emit latency `:error`, increment failure, report `SystemError`, reraise.

  AppSignal metric tags use `module.webhook_name()` (the observability name) rather than
  `module.name()` (the node URL) so metrics are consistent with Kaapi callback payloads.
  """
  @spec around_async(module(), map(), (-> {:wait | :ok, any(), list()})) ::
          {:wait | :ok, any(), list()}
  def around_async(module, ctx, fun)
      when is_atom(module) and is_map(ctx) and is_function(fun, 0) do
    webhook_name = resolve_webhook_name(module)
    start = System.monotonic_time()

    try do
      result = fun.()

      case result do
        {:wait, _context, _msgs} ->
          emit_latency(webhook_name, :async, start, :ok)

        {:ok, _context, _msgs} ->
          emit_latency(webhook_name, :async, start, :error)
          track_metrics(webhook_name, nil)
          report_webhook_failure(webhook_name, ctx, nil, "Async webhook immediate failure")
      end

      result
    rescue
      exception ->
        emit_latency(webhook_name, :async, start, :error)
        track_metrics(webhook_name, nil)
        report_webhook_failure(webhook_name, ctx, nil, Exception.message(exception))
        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Reports a failure raised while an async webhook's *deferred* Kaapi request is
  dispatched from `Glific.ThirdParty.Kaapi.SttTtsWorker`.

  STT/TTS nodes park the flow at dispatch time (`around_async/3` returns `{:wait, …}`
  before the real Kaapi call runs in the Oban worker), so the worker's Kaapi failure
  falls outside `around_async/3`. This function restores SystemError reporting + the
  per-webhook failure metric for that path. Success is intentionally NOT counted here —
  it is counted at callback time in `FlowResumeController` to avoid double counting.
  """
  @spec report_async_failure(String.t(), map()) :: :ok
  def report_async_failure(webhook_name, tags) when is_binary(webhook_name) and is_map(tags) do
    track_metrics(webhook_name, nil)

    %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: Map.put(tags, :webhook_name, webhook_name)
    )
  end

  @doc """
  Callback-time failure report (the Kaapi callback arrived but `success` was
  not `true`). Preserves the same tag keys so AppSignal filtering is unchanged.
  """
  @spec report_callback_failure(map(), map()) :: :ok
  def report_callback_failure(%{"success" => success} = result, response)
      when success != true do
    reason =
      result["reason"] || result["error"] || response["message"] || "Kaapi callback failure"

    %Errors.SystemError{message: "Webhook callback failure"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: %{
        organization_id: response["organization_id"],
        webhook_name: response["webhook_name"],
        flow_id: response["flow_id"],
        contact_id: response["contact_id"],
        webhook_log_id: response["webhook_log_id"],
        error_type: result["error_type"],
        reason: reason
      }
    )
  end

  def report_callback_failure(_result, _response), do: :ok

  @doc """
  Timeout-time failure report (an async webhook's await window expired
  without a callback). Builds a `TimeoutError` so AppSignal keeps timeouts in
  their own incident bucket.
  """
  @spec report_timeout(map()) :: :ok
  def report_timeout(tags) when is_map(tags) do
    webhook_name = Map.get(tags, :webhook_name) || "unknown"

    %Errors.TimeoutError{message: "Webhook timeout from #{webhook_name}"}
    |> Glific.log_exception(namespace: "flow_webhooks", tags: tags)
  end

  # --- private ----------------------------------------------------------------

  @spec maybe_report_webhook_failure(any(), String.t(), map()) :: :ok
  defp maybe_report_webhook_failure(%{success: false} = result, webhook_name, ctx) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, ctx, status, reason)
  end

  # nil / non-map results route to the flow's Failure category. Treat them as
  # failures here too so the centralised reporter mirrors legacy behaviour.
  defp maybe_report_webhook_failure(result, webhook_name, ctx)
       when is_nil(result) or not is_map(result) do
    reason = if is_binary(result), do: result, else: inspect(result)
    report_webhook_failure(webhook_name, ctx, nil, reason)
  end

  defp maybe_report_webhook_failure(_result, _webhook_name, _ctx), do: :ok

  @spec extract_status_and_reason(map()) :: {integer() | nil, String.t() | nil}
  defp extract_status_and_reason(result) do
    case result do
      %{http_status: status, reason: reason} when is_integer(status) and is_binary(reason) ->
        {status, reason}

      %{http_status: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_integer(status) ->
        {status, nil}

      %{asr_response_text: status} when is_binary(status) ->
        {nil, status}

      %{reason: status} when is_binary(status) ->
        {nil, status}

      %{error: error} when is_binary(error) ->
        {nil, error}

      other ->
        {nil, inspect(other)}
    end
  end

  @spec report_webhook_failure(String.t(), map(), integer() | nil, String.t() | nil) :: :ok
  defp report_webhook_failure(webhook_name, ctx, http_status, reason) do
    %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: %{
        organization_id: Map.get(ctx, :organization_id),
        webhook_name: webhook_name,
        http_status: http_status,
        reason: reason
      }
    )
  end

  @spec track_metrics(String.t(), any()) :: :ok
  defp track_metrics(webhook_name, %{success: true}) do
    Metrics.increment(metric_event_name(webhook_name, "Success"))
  end

  defp track_metrics(webhook_name, _) do
    Metrics.increment(metric_event_name(webhook_name, "Failure"))
  end

  @spec metric_event_name(String.t(), String.t()) :: String.t()
  defp metric_event_name(webhook_name, outcome) do
    title =
      webhook_name
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)

    "#{title} API #{outcome}"
  end

  # Safely resolves the observability webhook name for a module. For async modules
  # this is module.webhook_name() (which may differ from module.name() for the unified
  # LLM nodes). Falls back to module.name() for modules that don't export webhook_name/0
  # (e.g. sync modules called through around/3).
  # Code.ensure_loaded? is required: function_exported?/3 returns false for a module
  # that hasn't been loaded yet, which would silently fall back to name/0 and tag
  # metrics with the node URL instead of the observability webhook_name.
  @spec resolve_webhook_name(module()) :: String.t()
  defp resolve_webhook_name(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :webhook_name, 0) do
      module.webhook_name()
    else
      module.name()
    end
  end

  @spec emit_latency(String.t(), :sync | :async, integer(), :ok | :error) :: :ok
  defp emit_latency(webhook_name, mode, start_monotonic, outcome) do
    duration_ms =
      System.monotonic_time()
      |> Kernel.-(start_monotonic)
      |> System.convert_time_unit(:native, :millisecond)

    Appsignal.add_distribution_value("flow_webhook_latency", duration_ms, %{
      webhook_name: webhook_name,
      mode: Atom.to_string(mode),
      outcome: Atom.to_string(outcome)
    })

    :ok
  end
end
