defmodule Glific.Flows.Webhooks.Instrumentation do
  @moduledoc """
  Centralised failure reporting and latency telemetry for flow webhooks. Every webhook dispatched
  through `Dispatcher` is wrapped by `around/3`, which times the call, counts the outcome
  (`flow_webhook_count`) and reports failures. Sync nodes self-classify via
  `{:error, ErrorType.t(), msg}` (routed by `ErrorReporter`); the async/callback/resume/timeout
  paths report `Errors.{SystemError, TimeoutError}` under `flow_webhooks`.
  """

  alias Glific.Flows.Webhooks.{ErrorReporter, Errors}
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
    report_sync_failure(result, webhook_name, ctx)
  end

  # Async: a successful ack means the request is in flight; latency + success count land at
  # callback time (recording them here would pollute the same metric). Only a dispatch failure,
  # which never reaches the callback, is recorded now.
  defp record_outcome(:async, %{success: true}, _webhook_name, _start, _ctx), do: :ok

  defp record_outcome(:async, result, webhook_name, start, ctx) do
    track_latency(webhook_name, :async, start, :error)
    maybe_report_failure(result, webhook_name, ctx)
  end

  # Success only for `{:ok, _}` or `%{success: true}`; every other shape routes to Failure.
  @spec sync_count_status(any()) :: String.t()
  defp sync_count_status({:ok, _value}), do: "success"
  defp sync_count_status(%{success: true}), do: "success"
  defp sync_count_status(_result), do: "failure"

  # A typed `{:error, ErrorType.t(), msg}` is routed by ErrorReporter; any untyped failure shape
  # failed to name itself and fails safe to `:unknown` (→ system). Non-failures emit no incident.
  @spec report_sync_failure(any(), String.t(), map()) :: :ok
  defp report_sync_failure({:error, error_type, message}, webhook_name, ctx)
       when is_atom(error_type) and is_binary(message) do
    ErrorReporter.report(error_type, message, failure_tags(webhook_name, ctx))
  end

  defp report_sync_failure({:error, message}, webhook_name, ctx) when is_binary(message) do
    ErrorReporter.report(:unknown, message, failure_tags(webhook_name, ctx))
  end

  defp report_sync_failure(result, webhook_name, ctx) when is_binary(result) or is_nil(result) do
    reason = if is_binary(result), do: result, else: SafeLog.safe_inspect(result)
    ErrorReporter.report(:unknown, reason, failure_tags(webhook_name, ctx))
  end

  defp report_sync_failure(%{success: false} = result, webhook_name, ctx) do
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
  defp report_sync_failure({:error, _error_type, _message} = result, webhook_name, ctx) do
    ErrorReporter.report(:unknown, SafeLog.safe_inspect(result), failure_tags(webhook_name, ctx))
  end

  defp report_sync_failure(_non_failure, _webhook_name, _ctx), do: :ok

  @spec failure_tags(String.t(), map()) :: map()
  defp failure_tags(webhook_name, ctx) do
    %{webhook_name: webhook_name, organization_id: Map.get(ctx, :organization_id)}
  end

  @doc "Report a Kaapi callback that arrived with `success` not true."
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

  @doc "Record callback-phase telemetry for an async webhook (count, latency, failure)."
  @spec record_callback_outcome(map(), map()) :: :ok
  def record_callback_outcome(result, response) do
    status = if result["success"], do: "success", else: "failure"
    track_webhook_count(response["webhook_name"], status)
    track_kaapi_latency(response, status)
    report_callback_failure(result, response)
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

  # --- voice-node component/total latency -----------------------

  @mb 1_000_000
  @voice_component_metric "voice_component_latency"
  @voice_total_metric "voice_node_latency"

  @doc """
  Bucket an audio byte size into the coarse file-size ranges used for voice-node latency
  baselining: `"0-1MB"`, `"1-5MB"`, `"5-10MB"`, `"10-20MB"`, `"20MB+"`. A
  nil/unknown size (e.g. the media download failed before we could size it) buckets as
  `"unknown"` so it never silently lands in `"0-1MB"`.
  """
  @spec size_bucket(non_neg_integer() | nil) :: String.t()
  def size_bucket(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes < @mb -> "0-1MB"
      bytes < 5 * @mb -> "1-5MB"
      bytes < 10 * @mb -> "5-10MB"
      bytes < 20 * @mb -> "10-20MB"
      true -> "20MB+"
    end
  end

  def size_bucket(_bytes), do: "unknown"

  @doc """
  Record a single voice-pipeline component latency (`"stt"` | `"filesearch"` | `"tts"`) as an
  AppSignal distribution, tagged with the webhook name, component, file-size bucket and outcome
  so each stage can be p95'd per size bucket independently.
  """
  @spec track_voice_component(String.t(), String.t(), number(), keyword()) :: :ok
  def track_voice_component(webhook_name, component, duration_ms, opts \\ []) do
    Appsignal.add_distribution_value(@voice_component_metric, duration_ms, %{
      webhook_name: webhook_name,
      component: component,
      size_bucket: Keyword.get(opts, :size_bucket, "unknown"),
      status: Keyword.get(opts, :status, "success")
    })

    :ok
  end

  @doc """
  Record the per-component (`filesearch`, `tts`) and total latencies for a voice-filesearch
  callback, tagged by file-size bucket. STT latency is recorded separately in the worker (where
  the audio is downloaded and sized). `tts_ms` is measured locally around post-processing; the
  Kaapi filesearch round-trip is derived from the dispatch/arrival wall-clock stamps that
  round-trip through the signed `request_metadata`. The total is the sum of the three stages —
  avoiding the cross-node wall-clock skew of an end-to-end `now - start` span for the STT/TTS
  portions (only the unavoidable filesearch round-trip crosses nodes). Called from the voice
  resume path.
  """
  @spec record_voice_latencies(map(), number(), String.t()) :: :ok
  def record_voice_latencies(response, tts_ms, status) do
    webhook_name = response["webhook_name"] || "voice-filesearch-gpt"
    size_bucket = response["audio_size_bucket"] || "unknown"
    opts = [size_bucket: size_bucket, status: status]

    filesearch_ms = voice_filesearch_ms(response)

    if is_number(filesearch_ms),
      do: track_voice_component(webhook_name, "filesearch", filesearch_ms, opts)

    track_voice_component(webhook_name, "tts", tts_ms, opts)

    stt_ms = response["stt_latency_ms"] || 0
    total_ms = stt_ms + (filesearch_ms || 0) + tts_ms

    Appsignal.add_distribution_value(@voice_total_metric, total_ms, %{
      webhook_name: webhook_name,
      size_bucket: size_bucket,
      status: status
    })

    :ok
  end

  # Kaapi filesearch round-trip = callback arrival - dispatch, both wall-clock microsecond
  # stamps that round-trip through the signed request_metadata. Cross-node (worker -> web), so
  # subject to clock skew; nil when either stamp is absent (e.g. a text/older callback).
  @spec voice_filesearch_ms(map()) :: number() | nil
  defp voice_filesearch_ms(%{
         "kaapi_dispatch_ts" => dispatch,
         "callback_received_ts" => arrival
       })
       when is_integer(dispatch) and is_integer(arrival) and arrival >= dispatch do
    (arrival - dispatch) / 1_000
  end

  defp voice_filesearch_ms(_response), do: nil

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

  # Async dispatch-failure (immediate `%{success: false}` / nil ack, before any callback).
  @spec maybe_report_failure(any(), String.t(), map()) :: :ok
  defp maybe_report_failure(%{success: false} = result, webhook_name, ctx) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, ctx, status, reason)
  end

  defp maybe_report_failure(result, webhook_name, ctx)
       when is_nil(result) or not is_map(result) do
    reason = if is_binary(result), do: result, else: SafeLog.safe_inspect(result)
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
        {nil, SafeLog.safe_inspect(other)}
    end
  end

  @spec report_webhook_failure(
          String.t(),
          map(),
          integer() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: :ok
  defp report_webhook_failure(webhook_name, ctx, http_status, reason, error_type \\ nil) do
    report_failure(webhook_name, %{
      organization_id: Map.get(ctx, :organization_id),
      http_status: http_status,
      reason: reason,
      error_type: error_type
    })
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
