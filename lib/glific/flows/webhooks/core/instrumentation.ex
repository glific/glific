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
      record_outcome(mode, result, webhook_name, start, ctx)
      result
    rescue
      exception ->
        track_latency(webhook_name, mode, start, :error)
        track_status(webhook_name, nil)
        report_webhook_failure(webhook_name, ctx, nil, Exception.message(exception))
        reraise exception, __STACKTRACE__
    end
  end

  # Sync webhooks: the call IS the work, so record latency + metric + any failure now.
  @spec record_outcome(:sync | :async, any(), String.t(), integer(), map()) :: :ok
  defp record_outcome(:sync, result, webhook_name, start, ctx) do
    track_latency(webhook_name, :sync, start, :ok)
    track_status(webhook_name, result)
    maybe_report_failure(result, webhook_name, ctx)
  end

  # Async webhooks: a successful ack means the Kaapi request is in flight. The real
  # round-trip latency and the success count are recorded at callback time
  # (FlowResumeController), so record nothing here — recording an ack-time latency would
  # pollute the same `flow_webhook_latency` metric the callback fills. Only a dispatch
  # failure, which never reaches the callback, is recorded now.
  defp record_outcome(:async, %{success: true}, _webhook_name, _start, _ctx), do: :ok

  defp record_outcome(:async, result, webhook_name, start, ctx) do
    track_latency(webhook_name, :async, start, :error)
    track_status(webhook_name, result)
    maybe_report_failure(result, webhook_name, ctx)
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

  @doc """
  Resume-time failure report (the Kaapi callback arrived and validated, but
  `FlowContext.resume_contact_flow/4` could not resume the parked flow — e.g.
  the awaiting context was already gone). Same `flow_webhooks` namespace and
  tag shape as the callback/timeout reporters.
  """
  @spec report_resume_failure(map(), any()) :: :ok
  def report_resume_failure(response, reason) do
    %Errors.SystemError{message: "Webhook resume failure"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: %{
        organization_id: response["organization_id"],
        webhook_name: response["webhook_name"],
        flow_id: response["flow_id"],
        contact_id: response["contact_id"],
        webhook_log_id: response["webhook_log_id"],
        reason: inspect(reason)
      }
    )
  end

  @doc """
  Report a webhook failure surfaced outside the dispatcher's automatic path —
  e.g. an implementation module detecting a callback that succeeded at the HTTP
  layer but returned an unusable body. Same `flow_webhooks` namespace and tag
  shape as the callback/timeout/resume reporters; `:webhook_name` is filled in
  from the first argument.
  """
  @spec report_failure(String.t(), tags()) :: :ok
  def report_failure(webhook_name, tags) when is_binary(webhook_name) and is_map(tags) do
    %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: Map.put(tags, :webhook_name, webhook_name)
    )
  end

  @doc """
  Record the callback-phase telemetry for an async webhook: success/failure
  count, end-to-end latency, and (on failure) a `flow_webhooks` report. This is
  the callback-time counterpart of the execution-phase `around/3`.
  """
  @spec record_callback_outcome(map(), map()) :: :ok
  def record_callback_outcome(result, response) do
    status = if result["success"], do: "success", else: "failure"
    track_webhook_count(response["webhook_name"], status)
    track_kaapi_latency(response, status)
    report_callback_failure(result, response)
  end

  @doc """
  Increment a counter for a flow-webhook node outcome so success/failure ratios
  can be computed per webhook node. `status` is "success" or "failure". Shared by
  the sync, callback and timeout paths.
  """
  @spec track_webhook_count(String.t() | nil, String.t()) :: :ok
  def track_webhook_count(webhook_name, status) do
    Appsignal.increment_counter("flow_webhook_count", 1, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  @doc """
  Records end-to-end latency for a webhook node execution as an AppSignal
  distribution (so p50/p95/p99 can be charted). Generic across all node types.
  """
  @spec track_webhook_latency(String.t() | nil, String.t(), number()) :: :ok
  def track_webhook_latency(webhook_name, status, duration_ms) do
    Appsignal.add_distribution_value("flow_webhook_latency", duration_ms, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  # --- private ----------------------------------------------------------------

  # Latency for an async webhook callback (request dispatch -> callback arrival),
  # derived from the request timestamp embedded in the callback metadata.
  @spec track_kaapi_latency(map(), String.t()) :: :ok
  defp track_kaapi_latency(%{"timestamp" => timestamp} = response, status)
       when is_integer(timestamp) do
    now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    duration_ms = (now - timestamp) / 1_000

    case response["call_type"] do
      nil ->
        :ok

      call_type ->
        Appsignal.add_distribution_value("kaapi_llm_latency", duration_ms, %{
          call_type: call_type
        })
    end

    track_webhook_latency(response["webhook_name"], status, duration_ms)
  end

  defp track_kaapi_latency(_response, _status), do: :ok

  @spec maybe_report_failure(any(), String.t(), map()) :: :ok
  defp maybe_report_failure(%{success: false} = result, webhook_name, ctx) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, ctx, status, reason)
  end

  # nil / non-map results route to the flow's Failure category. Treat them as
  # failures here too so the centralised reporter mirrors legacy behaviour.
  defp maybe_report_failure(result, webhook_name, ctx)
       when is_nil(result) or not is_map(result) do
    reason = if is_binary(result), do: result, else: Glific.SafeLog.safe_inspect(result)
    report_webhook_failure(webhook_name, ctx, nil, reason)
  end

  defp maybe_report_failure(_result, _webhook_name, _ctx), do: :ok

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
        {nil, Glific.SafeLog.safe_inspect(other)}
    end
  end

  @spec report_webhook_failure(String.t(), map(), integer() | nil, String.t() | nil) :: :ok
  defp report_webhook_failure(webhook_name, ctx, http_status, reason) do
    report_failure(webhook_name, %{
      organization_id: Map.get(ctx, :organization_id),
      http_status: http_status,
      reason: reason
    })
  end

  @spec track_status(String.t(), any()) :: :ok
  defp track_status(webhook_name, %{success: true}) do
    Metrics.increment(metric_event_name(webhook_name, "Success"))
  end

  defp track_status(webhook_name, _) do
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

  @spec track_latency(String.t(), :sync | :async, integer(), :ok | :error) :: :ok
  defp track_latency(webhook_name, mode, start_monotonic, outcome) do
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
