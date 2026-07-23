defmodule Glific.Jobs.Instrumentation do
  @moduledoc """
  Success / error / latency instrumentation for periodic Oban jobs.

  `instrument_oban: false` in `config/runtime.exs` disables AppSignal's built-in
  per-job metrics, so periodic workers (GCS, BigQuery, assistants, AI evaluations)
  opt in explicitly by wrapping their work in `track/3`. Each run emits a
  `job_run_count` counter tagged `job` / `status` / `organization_id` and a
  `job_run_latency` distribution with the same tags, so a subsystem's health is a
  chartable, alertable metric rather than only an exception report.

  Modelled on `Glific.Flows.Webhooks.Instrumentation` (flow webhooks) and
  `Glific.Providers.Instrumentation` (BSP send/receive), which already follow this
  wrap-and-count shape for their respective domains.
  """

  @typedoc "Final status recorded on `job_run_count`, derived from the wrapped work's return value."
  @type status :: :success | :error | :discard

  @doc """
  Wrap a periodic job's work: time it, record the outcome, and return the wrapped
  value unchanged so the caller's control flow (and Oban's return contract) is
  untouched.

  The return value is classified with the standard Oban worker conventions —
  `:ok` / `{:ok, _}` is `:success`, `{:discard, _}` is `:discard` (a deliberate
  permanent skip, not a failure to retry), and anything else is `:error`. A
  raised exception is recorded as `:error` and re-raised.
  """
  @spec track(String.t(), non_neg_integer() | nil, (-> result)) :: result when result: var
  def track(job, organization_id, fun) when is_function(fun, 0) do
    start = System.monotonic_time()

    try do
      result = fun.()
      record(job, classify(result), organization_id, start)
      result
    rescue
      exception ->
        record(job, :error, organization_id, start)
        reraise exception, __STACKTRACE__
    end
  end

  @spec classify(any()) :: status()
  defp classify(:ok), do: :success
  defp classify({:ok, _}), do: :success
  defp classify({:discard, _}), do: :discard
  defp classify(_result), do: :error

  @spec record(String.t(), status(), non_neg_integer() | nil, integer()) :: :ok
  defp record(job, status, organization_id, start) do
    tags = %{job: job, status: Atom.to_string(status), organization_id: org_tag(organization_id)}

    Appsignal.increment_counter("job_run_count", 1, tags)
    Appsignal.add_distribution_value("job_run_latency", duration_ms(start), tags)

    :ok
  end

  @spec duration_ms(integer()) :: integer()
  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end

  @spec org_tag(non_neg_integer() | nil) :: String.t()
  defp org_tag(nil), do: "unknown"
  defp org_tag(organization_id), do: to_string(organization_id)
end
