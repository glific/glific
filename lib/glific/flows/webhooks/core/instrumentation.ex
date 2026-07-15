defmodule Glific.Flows.Webhooks.Instrumentation do
  @moduledoc """
  Centralised failure reporting and latency telemetry for flow webhooks. Every webhook dispatched
  through `Dispatcher` is wrapped by `around/3`, which times the call, counts the outcome
  (`flow_webhook_count`) and reports failures. Sync nodes self-classify via
  `{:error, ErrorType.t(), msg}` (routed by `ErrorReporter`). Async nodes self-classify their
  dispatch failure via an `error_type` on the `%{success: false}` ack; their later callback
  failure (an opaque provider string) is classified by the node's own `classify/1`, funnelled
  here through `around_callback/4` — this module stays provider-agnostic. Both route through
  `ErrorReporter`. The resume/timeout paths report `Errors.{SystemError, TimeoutError}` under
  `flow_webhooks`.
  """

  alias Glific.Flows.Webhooks.{ErrorReporter, Errors, ErrorType}
  alias Glific.SafeLog

  require Logger

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

  @doc "Wrap a webhook `call/2` with failure reporting + latency telemetry; re-raises exceptions."
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

        # A raised sync webhook is a failure and must increment the count; async counts at callback.
        if mode == :sync, do: track_webhook_count(webhook_name, "failure")

        # A raised exception is unjudgeable — tag it "exception" (system) so it carries an error_type.
        report_webhook_failure(webhook_name, ctx, nil, Exception.message(exception), "exception")
        reraise exception, __STACKTRACE__
    end
  end

  @spec record_outcome(:sync | :async, any(), String.t(), integer(), map()) :: :ok
  # A snooze is neither success nor failure — the Oban job reschedules, so record nothing.
  defp record_outcome(_mode, {:snooze, _seconds}, _webhook_name, _start, _ctx), do: :ok

  # Sync: the call IS the work, so count here (async counts at callback time — no double-count).
  defp record_outcome(:sync, result, webhook_name, start, ctx) do
    track_latency(webhook_name, :sync, start, :ok)
    track_webhook_count(webhook_name, sync_count_status(result))
    report_typed_failure(result, webhook_name, ctx)
  end

  # Async: an accepted dispatch (`{:ok, ack}`) means the request is in flight; latency + success
  # count land at callback time (recording them here would pollute the same metric). Only a
  # dispatch failure, which never reaches the callback, is recorded now — via the same typed path
  # as sync, since async nodes now return the same `{:ok, _} | {:error, type, msg}` contract.
  defp record_outcome(:async, {:ok, _ack}, _webhook_name, _start, _ctx), do: :ok

  defp record_outcome(:async, result, webhook_name, start, ctx) do
    track_latency(webhook_name, :async, start, :error)
    report_typed_failure(result, webhook_name, ctx)
  end

  # Success only for `{:ok, _}` or `%{success: true}`; every other shape routes to Failure.
  @spec sync_count_status(any()) :: String.t()
  defp sync_count_status({:ok, _value}), do: "success"
  defp sync_count_status(%{success: true}), do: "success"
  defp sync_count_status(_result), do: "failure"

  # A typed `{:error, ErrorType.t(), msg}` is routed by ErrorReporter; any untyped failure shape
  # failed to name itself and fails safe to `:unknown` (→ system). Non-failures emit no incident.
  @spec report_typed_failure(any(), String.t(), map()) :: :ok
  defp report_typed_failure({:error, error_type, message}, webhook_name, ctx)
       when is_atom(error_type) and is_binary(message) do
    ErrorReporter.report(error_type, message, failure_tags(webhook_name, ctx))
  end

  defp report_typed_failure({:error, message}, webhook_name, ctx) when is_binary(message) do
    ErrorReporter.report(:unknown, message, failure_tags(webhook_name, ctx))
  end

  defp report_typed_failure(result, webhook_name, ctx) when is_binary(result) or is_nil(result) do
    reason = if is_binary(result), do: result, else: SafeLog.safe_inspect(result)
    ErrorReporter.report(:unknown, reason, failure_tags(webhook_name, ctx))
  end

  defp report_typed_failure(%{success: false} = result, webhook_name, ctx) do
    reason =
      case result do
        %{reason: reason} when is_binary(reason) -> reason
        %{"reason" => reason} when is_binary(reason) -> reason
        other -> SafeLog.safe_inspect(other)
      end

    ErrorReporter.report(:unknown, reason, failure_tags(webhook_name, ctx))
  end

  # A 3-tuple that violates the typed contract (non-atom type / non-binary message) still routed
  # the flow to Failure — report it as :unknown so it isn't counted-but-invisible to on-call.
  defp report_typed_failure({:error, _error_type, _message} = result, webhook_name, ctx) do
    ErrorReporter.report(:unknown, SafeLog.safe_inspect(result), failure_tags(webhook_name, ctx))
  end

  defp report_typed_failure(_non_failure, _webhook_name, _ctx), do: :ok

  @spec failure_tags(String.t(), map()) :: map()
  defp failure_tags(webhook_name, ctx) do
    Map.put(ctx_tags(ctx), :webhook_name, webhook_name)
  end

  # The flow-context ids carried on `ctx` (built by the Dispatcher) so every pre-callback failure
  # report — sync, async-dispatch, crash — tags contact/flow/webhook_log for debugging.
  @spec ctx_tags(map()) :: map()
  defp ctx_tags(ctx) do
    %{
      organization_id: Map.get(ctx, :organization_id),
      flow_id: Map.get(ctx, :flow_id),
      contact_id: Map.get(ctx, :contact_id),
      webhook_log_id: Map.get(ctx, :webhook_log_id)
    }
  end

  # An async callback failure is an opaque provider string, so the node's `classify/1` infers the
  # ErrorType (the node can't self-classify here) and `ErrorReporter` routes it like the sync path.
  @doc "Report an async callback that arrived with `success` not true, classified by the node."
  @spec report_callback_failure(module() | nil, map(), map()) :: :ok
  def report_callback_failure(_module, %{"success" => true}, _response), do: :ok

  # Any other map is a failure — including one missing the `success` key, which must not be
  # silently swallowed (the flow already branched to Failure on it).
  def report_callback_failure(module, result, response) when is_map(result) do
    reason =
      result["reason"] || result["error"] || response["message"] ||
        "#{response["webhook_name"] || "Webhook"} callback failure"

    result
    |> classify_callback(module)
    |> ErrorReporter.report(reason, callback_tags(result, response))
  end

  def report_callback_failure(_module, _result, _response), do: :ok

  # Delegate classification to the node (it may override `classify/1`). A callback that arrived
  # without a resolvable webhook module has no node to consult, so it fails safe to system —
  # keeping this module free of any provider-specific classifier.
  @spec classify_callback(map(), module() | nil) :: ErrorType.t()
  defp classify_callback(result, module) when is_atom(module) and not is_nil(module),
    do: module.classify(result)

  defp classify_callback(_result, _module), do: :unknown

  # Keep the raw Kaapi `error_type` and `http_status` (the classification driver) as tags alongside
  # the classified bucket `ErrorReporter` adds, so incidents stay debuggable.
  @spec callback_tags(map(), map()) :: map()
  defp callback_tags(result, response) do
    %{
      organization_id: response["organization_id"],
      webhook_name: response["webhook_name"],
      flow_id: response["flow_id"],
      contact_id: response["contact_id"],
      webhook_log_id: response["webhook_log_id"],
      http_status: result["http_status"],
      kaapi_error_type: result["error_type"]
    }
  end

  @doc "Report an async webhook whose await window expired without a callback."
  @spec report_timeout(map()) :: :ok
  def report_timeout(tags) when is_map(tags) do
    webhook_name = Map.get(tags, :webhook_name) || "unknown"

    %Errors.TimeoutError{message: "Webhook timeout from #{webhook_name}"}
    |> Glific.log_exception(namespace: "flow_webhooks", tags: tags)
  end

  @doc "Report a callback that validated but could not resume the parked flow."
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
        reason: SafeLog.safe_inspect(reason)
      }
    )
  end

  @doc "Report a webhook failure surfaced outside the dispatcher's automatic path."
  @spec report_failure(String.t(), tags()) :: :ok
  def report_failure(webhook_name, tags) when is_binary(webhook_name) and is_map(tags) do
    %Errors.SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Glific.log_exception(
      namespace: "flow_webhooks",
      tags: Map.put(tags, :webhook_name, webhook_name)
    )
  end

  @doc """
  Run an async webhook's `callback/3` inside callback-phase instrumentation: executes `fun`
  (the node's callback — post-processing for voice, pass-through otherwise), records count +
  latency, classifies/reports a failure, and returns whatever the callback shaped. This is the
  single callback-phase entry point (`Dispatcher.callback` calls it), mirroring `around/3` for
  the dispatch phase.
  """
  @spec around_callback(module() | nil, map(), map(), (-> map())) :: map()
  def around_callback(module, result, response, fun)
      when (is_atom(module) or is_nil(module)) and is_function(fun, 0) do
    # Mirror `around/3`: a raising callback (e.g. voice post-processing) must still record its
    # count/latency/failure before the exception propagates, or callback telemetry is lost.
    shaped = fun.()
    record_callback_outcome(module, result, response)
    shaped
  rescue
    exception ->
      record_callback_outcome(module, Map.put(result, "success", false), response)
      reraise exception, __STACKTRACE__
  end

  # Callback-phase telemetry for an async webhook (count, latency, failure classification).
  @spec record_callback_outcome(module() | nil, map(), map()) :: :ok
  defp record_callback_outcome(module, result, response) do
    status = if result["success"], do: "success", else: "failure"
    track_webhook_count(response["webhook_name"], status)
    track_kaapi_latency(response, status)
    report_callback_failure(module, result, response)
  end

  @doc "Increment the success/failure counter for a flow-webhook node outcome."
  @spec track_webhook_count(String.t() | nil, String.t()) :: :ok
  def track_webhook_count(webhook_name, status) do
    Appsignal.increment_counter("flow_webhook_count", 1, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  @doc "Record a flow-webhook node execution latency as an AppSignal distribution."
  @spec track_webhook_latency(String.t() | nil, String.t(), number()) :: :ok
  def track_webhook_latency(webhook_name, status, duration_ms) do
    Appsignal.add_distribution_value("flow_webhook_latency", duration_ms, %{
      webhook_name: webhook_name || "unknown",
      status: status
    })

    :ok
  end

  # --- private ----------------------------------------------------------------

  # Async callback latency (request dispatch -> callback arrival), from the request timestamp.
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

  @spec report_webhook_failure(
          String.t(),
          map(),
          integer() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: :ok
  defp report_webhook_failure(webhook_name, ctx, http_status, reason, error_type) do
    report_failure(
      webhook_name,
      Map.merge(ctx_tags(ctx), %{http_status: http_status, reason: reason, error_type: error_type})
    )
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
