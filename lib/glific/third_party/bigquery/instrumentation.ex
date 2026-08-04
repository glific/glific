defmodule Glific.BigQuery.Instrumentation do
  @moduledoc """
  Per-table success / failure counters for the BigQuery sync (issue #5381).

  The sync fans out into one Oban job per (table, action) pair across 18+ schemas, and
  `BigQueryWorker` runs with `max_attempts: 1` — a single failure is final and is never
  retried. Without a `table` tag one broken table is invisible behind seventeen healthy
  ones, so every counter here carries the table it belongs to.

  Emits one metric:

    * `bigquery_sync_count` — one increment per sync job, tagged `table`, `action`,
      `status` and `organization_id`.

  A single counter tagged with `status` rather than separate `.success` / `.failure`
  metrics matches every other counter in the codebase (`job_run_count`,
  `provider_send_count`, `provider_action_count`) and lets an alert express a
  failure *ratio*, not just an absolute count.

  ## Why the outcome is recorded inside the response handler

  `BigQuery.handle_insert_query_response/3` swallows three classes of failure — it
  reacts to them and returns normally rather than raising:

    * `NOT_FOUND` — triggers a schema re-sync
    * `PERMISSION_DENIED` — **disables the org's BigQuery credential**
    * `TIMEOUT` — logged only

  So wrapping `perform/1` alone would count all three as success and report green while
  syncing is broken — including the case where credentials have just been switched off.
  `record/4` is therefore called from the response handler, where the outcome is actually
  known, with these statuses:

    | status              | meaning                                          |
    | ------------------- | ------------------------------------------------ |
    | `success`           | BigQuery accepted the rows, or the dedup ran     |
    | `error`             | dedup failed, or its credentials were unusable   |
    | `schema_not_found`  | table/dataset missing, schema re-sync triggered   |
    | `permission_denied` | credential rejected and now disabled             |
    | `timeout`           | request timed out                                |
    | `exception`         | anything that raised out of the job              |

  The raising branches deliberately do **not** record here — they propagate to
  `BigQueryWorker.perform/1`, whose rescue records `exception`. That keeps it to exactly
  one increment per job, so a "> N consecutive failures" alert is not skewed by
  double counting.

  Anything other than `success` is a failure for alerting purposes.
  """

  @typedoc "Outcome recorded on `bigquery_sync_count`."
  @type status ::
          :success | :error | :schema_not_found | :permission_denied | :timeout | :exception

  @doc """
  Records one sync outcome for a table.
  """
  @spec record(String.t(), status(), String.t() | atom() | nil, non_neg_integer()) :: :ok
  def record(table, status, action, organization_id) do
    Appsignal.increment_counter("bigquery_sync_count", 1, %{
      table: to_tag(table),
      action: to_tag(action),
      status: Atom.to_string(status),
      organization_id: org_tag(organization_id)
    })

    :ok
  rescue
    # Metrics are best-effort: emitting one must never turn a healthy sync into a failed
    # one, and record/4 sits on the success path too.
    _exception -> :ok
  end

  @doc """
  Runs `fun`, recording `exception` for `table` if it raises, then re-raising.
  """
  @spec track(
          String.t() | atom(),
          String.t() | atom() | nil,
          non_neg_integer() | nil,
          (-> result)
        ) ::
          result
        when result: var
  def track(table, action, organization_id, fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      record(table, :exception, action, organization_id)
      reraise exception, __STACKTRACE__
  end

  # nil is reachable: bigquery.ex reads the action with Keyword.get/2, which returns nil if a
  # caller forgets to forward it. Tagging "unknown" beats crashing the sync over a metric.
  @spec to_tag(String.t() | atom() | nil) :: String.t()
  defp to_tag(nil), do: "unknown"
  defp to_tag(value) when is_atom(value), do: Atom.to_string(value)
  defp to_tag(value), do: to_string(value)

  @spec org_tag(non_neg_integer()) :: String.t()
  defp org_tag(organization_id), do: to_string(organization_id)
end
