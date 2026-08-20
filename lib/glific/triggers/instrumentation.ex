defmodule Glific.Triggers.Instrumentation do
  @moduledoc """
  Start-vs-scheduled drift and completion-time SLA metrics for trigger execution (issue #5382).

  Triggers are the one scheduled surface where "it ran" is not the interesting question —
  "it ran *on time*" is. `Glific.Triggers.execute_triggers/2` is driven from the
  every-minute `triggers_and_broadcast` crontab entry, so a trigger due at 09:00 that fires
  at 09:20 is a silent, invisible failure today: the flow starts, nothing errors, and the
  contact simply got their message twenty minutes late. `instrument_oban: false` in
  `config/runtime.exs` means none of this is captured automatically.

  Emits four metrics, all tagged `organization_id`:

    * `trigger_start_drift_seconds` — distribution of `started_at - scheduled_at`, i.e. how
      far behind its `next_trigger_at` a trigger actually fired. Also tagged `frequency`,
      since an hourly trigger and a monthly one have very different drift expectations.
    * `trigger_start_drift_exceeded` — counter, incremented when that drift crosses
      the configured threshold. Alerting on a counter rather than a distribution
      percentile keeps the alert rule readable and matches `gupshup_inbound_stale`.
    * `trigger_execution_duration_milliseconds` — distribution of elapsed time for the whole
      execution (next-fire recomputation plus flow start), tagged `status`.
    * `trigger_execution_slow` — counter, incremented when that elapsed time crosses the
      configured budget.

  A breach is reported to AppSignal as a *counter*, not via `Glific.log_error/1`: a single
  backlog makes every due trigger drift at once, and hundreds of simultaneous AppSignal error
  reports would bury the one signal the alert is built on. The accompanying `Logger.warning`
  carries the trigger id, which the tags deliberately do not (too high cardinality).

  ## Thresholds

  Both thresholds are read from application config so ops can tune them from the observed
  distributions without a code change (see `config/runtime.exs`):

    * `:trigger_start_drift_seconds` — how late a trigger may start, default 300
    * `:trigger_duration_seconds` — how long one execution may take, default 60

  Both defaults are provisional; the issue leaves the real numbers open pending a look at
  the emitted distributions.

  ## Why drift is measured against the pre-update trigger

  `Glific.Triggers.do_execute_trigger/1` calls `update_next/1`, which overwrites
  `next_trigger_at` with the *next* firing time. `track_execution/2` therefore takes the
  trigger struct as it was before that update, and reads `scheduled_at` immediately — after
  `update_next/1` the scheduled time this run was measuring against is gone.

  Modelled on `Glific.Jobs.Instrumentation` (periodic job outcomes) and
  `Glific.BigQuery.Instrumentation` (per-table sync outcomes), which follow the same
  wrap-and-record shape for their domains.
  """

  require Logger

  alias Glific.Triggers.Trigger

  @default_start_drift_seconds 300
  @default_duration_seconds 60

  @typedoc "Outcome tagged on `trigger_execution_duration_milliseconds`."
  @type status :: :success | :exception

  @doc """
  Wrap one trigger's execution: record its start drift, then its elapsed time and outcome.

  Returns the wrapped value unchanged, and re-raises after recording an `exception`, so the
  caller's control flow is untouched.
  """
  @spec track_execution(Trigger.t(), (-> result)) :: result when result: var
  def track_execution(%Trigger{} = trigger, fun) when is_function(fun, 0) do
    started_at = DateTime.utc_now()
    start_time = System.monotonic_time()

    record_start_drift(trigger, started_at)

    try do
      result = fun.()
      record_completion(trigger, :success, start_time)
      result
    rescue
      exception ->
        record_completion(trigger, :exception, start_time)
        reraise exception, __STACKTRACE__
    end
  end

  @spec record_start_drift(Trigger.t(), DateTime.t()) :: :ok
  defp record_start_drift(%Trigger{next_trigger_at: nil}, _started_at), do: :ok

  defp record_start_drift(trigger, started_at) do
    # execute_triggers/2 looks one minute ahead, so a trigger can legitimately start before
    # it was due; only lateness is drift.
    drift = max(DateTime.diff(started_at, trigger.next_trigger_at), 0)

    Appsignal.add_distribution_value("trigger_start_drift_seconds", drift, %{
      organization_id: org_tag(trigger.organization_id),
      frequency: frequency_tag(trigger.frequency)
    })

    maybe_flag_drift(trigger, drift)
  rescue
    # Metrics are best-effort: a failure emitting one must never stop the trigger from running.
    _exception -> :ok
  end

  @spec maybe_flag_drift(Trigger.t(), non_neg_integer()) :: :ok
  defp maybe_flag_drift(trigger, drift) do
    threshold = threshold(:trigger_start_drift_seconds, @default_start_drift_seconds)

    if drift > threshold do
      Appsignal.increment_counter("trigger_start_drift_exceeded", 1, %{
        organization_id: org_tag(trigger.organization_id),
        frequency: frequency_tag(trigger.frequency)
      })

      Logger.warning(
        "Trigger start drift: trigger #{trigger.id} of org_id #{trigger.organization_id} started #{drift}s after its scheduled time (threshold #{threshold}s)"
      )
    end

    :ok
  end

  @spec record_completion(Trigger.t(), status(), integer()) :: :ok
  defp record_completion(trigger, status, start_time) do
    elapsed =
      System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    Appsignal.add_distribution_value("trigger_execution_duration_milliseconds", elapsed, %{
      organization_id: org_tag(trigger.organization_id),
      status: Atom.to_string(status)
    })

    maybe_flag_slow_execution(trigger, elapsed)
  rescue
    # Metrics are best-effort: record_completion/3 sits on the success path, so a failure
    # emitting one must never turn a healthy trigger into a failed one.
    _exception -> :ok
  end

  @spec maybe_flag_slow_execution(Trigger.t(), non_neg_integer()) :: :ok
  defp maybe_flag_slow_execution(trigger, elapsed) do
    budget = threshold(:trigger_duration_seconds, @default_duration_seconds) * 1000

    if elapsed > budget do
      Appsignal.increment_counter("trigger_execution_slow", 1, %{
        organization_id: org_tag(trigger.organization_id),
        frequency: frequency_tag(trigger.frequency)
      })

      Logger.warning(
        "Trigger execution slow: trigger #{trigger.id} of org_id #{trigger.organization_id} took #{elapsed}ms (budget #{budget}ms)"
      )
    end

    :ok
  end

  @spec threshold(atom(), pos_integer()) :: pos_integer()
  defp threshold(key, default) do
    :glific
    |> Application.get_env(key, default)
    |> Glific.parse_maybe_integer!()
  end

  @spec frequency_tag(list() | nil) :: String.t()
  defp frequency_tag([frequency | _rest]) when is_binary(frequency), do: frequency
  defp frequency_tag(_frequency), do: "unknown"

  @spec org_tag(non_neg_integer() | nil) :: String.t()
  defp org_tag(nil), do: "unknown"
  defp org_tag(organization_id), do: to_string(organization_id)
end
