defmodule Glific.Flows.Webhooks.Instrumentation do
  @moduledoc """
  Centralised failure reporting and latency telemetry for flow webhooks.

  This is the single home of `with_failure_reporting`. Every webhook dispatched
  through `Glific.Flows.Webhooks.Dispatcher` is wrapped by `around/3`, which:

    * Times the call and emits a `flow_webhook_latency` AppSignal distribution
      tagged with `webhook_name`, `mode`, and `outcome`.
    * Reports `%{success: false}` results and rescued exceptions to AppSignal
      via `Glific.Flows.Webhook.report_to_appsignal/2` (the project's single
      AppSignal sink). The exception module stays `Glific.Flows.Webhook.SystemError`
      so AppSignal grouping does not change.

  Callback-time and timeout-time reporting (the other two facets of webhook
  failure) live in `report_callback_failure/2` and `report_timeout/1` here —
  same `report_to_appsignal/2` sink, same exception module shapes that the
  controller and `FlowContext` use today.
  """

  alias Glific.Flows.Webhook
  alias Glific.Flows.Webhook.SystemError
  alias Glific.Metrics

  require Logger

  @typedoc """
  Tags attached to the centralised AppSignal report. Mirrors what
  `Webhook.report_to_appsignal/2` already accepts; keys are optional so each
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
  re-raised — callers downstream of the dispatcher (the Oban worker,
  `Webhook.handle/3`) see the same exceptions they would have seen with the
  old inline `with_failure_reporting/3`.
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
  Callback-time failure report (the Kaapi callback arrived but `success` was
  not `true`). Replaces the inline `maybe_report_callback_failure/2` in
  `flow_resume_controller`; preserves the same exception module
  (`SystemError`), the same `message`, and the same tag keys so AppSignal
  grouping is unchanged.
  """
  @spec report_callback_failure(map(), map()) :: :ok
  def report_callback_failure(%{"success" => success} = result, response)
      when success != true do
    reason =
      result["reason"] || result["error"] || response["message"] || "Kaapi callback failure"

    %SystemError{message: "Webhook callback failure"}
    |> Webhook.report_to_appsignal(%{
      organization_id: response["organization_id"],
      webhook_name: response["webhook_name"],
      flow_id: response["flow_id"],
      contact_id: response["contact_id"],
      webhook_log_id: response["webhook_log_id"],
      error_type: result["error_type"],
      reason: reason
    })
  end

  def report_callback_failure(_result, _response), do: :ok

  @doc """
  Timeout-time failure report (an async webhook's await window expired
  without a callback). Used by `FlowContext` when waking a stuck context.
  Builds a `TimeoutError` (not `SystemError`) so AppSignal keeps timeouts in
  their own incident bucket — matches today's behaviour.
  """
  @spec report_timeout(map()) :: :ok
  def report_timeout(tags) when is_map(tags) do
    webhook_name = Map.get(tags, :webhook_name) || "unknown"

    %Webhook.TimeoutError{message: "Webhook timeout from #{webhook_name}"}
    |> Webhook.report_to_appsignal(tags)
  end

  # --- private ----------------------------------------------------------------

  @spec maybe_report_webhook_failure(any(), String.t(), map()) :: :ok
  defp maybe_report_webhook_failure(%{success: false} = result, webhook_name, ctx) do
    {status, reason} = extract_status_and_reason(result)
    report_webhook_failure(webhook_name, ctx, status, reason)
  end

  # nil / non-map results route to the flow's Failure category (see
  # Glific.Flows.Webhook.handle/3, which keys off is_map). Treat them as
  # failures here too so the centralised reporter mirrors what the old
  # CommonWebhook.with_failure_reporting did.
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
    %SystemError{message: "Webhook system_error from #{webhook_name}"}
    |> Webhook.report_to_appsignal(%{
      organization_id: Map.get(ctx, :organization_id),
      webhook_name: webhook_name,
      http_status: http_status,
      reason: reason
    })
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
