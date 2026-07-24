defmodule Glific.Jobs.Instrumentation do
  @moduledoc """
  Success / error counters for periodic Oban jobs.

  `instrument_oban: false` in `config/runtime.exs` disables AppSignal's built-in
  per-job metrics, so periodic workers (GCS, BigQuery, assistants, AI evaluations)
  opt in explicitly by wrapping their work in `track/3`. Each run emits a
  `job_run_count` counter tagged `job` / `status` / `organization_id`, turning a
  subsystem's success/error rate into a chartable, alertable metric rather than
  only an exception report.

  Execution *latency* is not recorded here — it comes from the central
  `oban_job_duration` distribution emitted by `Glific.Appsignal`'s
  `[:oban, :job, :stop]` handler, which already covers every queued worker.

  Modelled on `Glific.Flows.Webhooks.Instrumentation` (flow webhooks) and
  `Glific.Providers.Instrumentation` (BSP send/receive), which follow the same
  wrap-and-count shape for their domains.
  """

  @typedoc "Final status recorded on `job_run_count`, derived from the wrapped work's return value."
  @type status :: :success | :error | :discard

  @doc """
  Wrap a periodic job's work, record its outcome, and return the wrapped value
  unchanged so the caller's control flow (and Oban's return contract) is untouched.

  The return value is classified with the standard Oban worker conventions —
  `:ok` / `{:ok, _}` is `:success`, `{:discard, _}` is `:discard` (a deliberate
  permanent skip, not a failure to retry), and anything else is `:error`. A raised
  exception is recorded as `:error` and re-raised.
  """
  @spec track(String.t(), non_neg_integer() | nil, (-> result)) :: result when result: var
  def track(job, organization_id, fun) when is_function(fun, 0) do
    result = fun.()
    record(job, classify(result), organization_id)
    result
  rescue
    exception ->
      record(job, :error, organization_id)
      reraise exception, __STACKTRACE__
  end

  @spec classify(any()) :: status()
  defp classify(:ok), do: :success
  defp classify({:ok, _}), do: :success
  defp classify({:discard, _}), do: :discard
  defp classify(_result), do: :error

  @spec record(String.t(), status(), non_neg_integer() | nil) :: :ok
  defp record(job, status, organization_id) do
    Appsignal.increment_counter("job_run_count", 1, %{
      job: job,
      status: Atom.to_string(status),
      organization_id: org_tag(organization_id)
    })

    :ok
  rescue
    # Metrics are best-effort: record/3 runs on track/3's success-return path, so a
    # failure emitting them must never turn a healthy job into a failed one.
    _exception -> :ok
  end

  @spec org_tag(non_neg_integer() | nil) :: String.t()
  defp org_tag(nil), do: "unknown"
  defp org_tag(organization_id), do: to_string(organization_id)
end
