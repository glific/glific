defmodule Glific.BigQuery.Instrumentation do
  @moduledoc """
  Per-table success / failure counters for the BigQuery sync (issue #5381).

  The sync fans out into one Oban job per (table, action) pair across 18+ schemas, and
  `BigQueryWorker` runs with `max_attempts: 1` — a single failure is final and is never
  retried. Without a `table` tag one broken table is invisible behind seventeen healthy
  ones, so every counter here carries the table it belongs to.

  Emits one metric:

    * `bigquery_sync_count` — one increment per sync job, tagged `table`, `action`,
      `status` (`success` or `failed`) and `organization_id`. A `failed` also carries a
      `reason` tag naming the failure.

  Two statuses keep the failure ratio a single query (`status:failed` over all), while
  `reason` breaks the failures down without multiplying the status values an alert has
  to know about.

  ## Why the outcome is recorded inside the response handler

  `BigQuery.handle_insert_response/3` swallows these failures — it reacts to them and
  returns normally rather than raising:

    * `insertErrors` — BigQuery rejected individual rows, logged only
    * `NOT_FOUND` — triggers a schema re-sync
    * `PERMISSION_DENIED` — **disables the org's BigQuery credential**
    * `TIMEOUT` — logged only

  So wrapping `perform/1` alone would count all of them as success and report green while
  syncing is broken — including the case where credentials have just been switched off.
  `record/4` is therefore called from the response handler, where the outcome is actually
  known. The reasons are:

    | reason                    | meaning                                         |
    | ------------------------- | ----------------------------------------------- |
    | `credentials_unavailable` | no usable BigQuery credentials, nothing was sent |
    | `query_failed`            | the dedup query returned an error               |
    | `row_errors`              | BigQuery rejected rows in the insert response   |
    | `schema_not_found`        | table/dataset missing, schema re-sync triggered |
    | `permission_denied`       | credential rejected and now disabled            |
    | `timeout`                 | request timed out                               |
    | `exception`               | anything that raised out of the job             |

  Anything that raises out of a job is not recorded where it raises — it propagates to
  `BigQueryWorker.perform/1`, whose rescue records `{:failed, :exception}`. That keeps it
  to one increment per failure, so a "> N consecutive failures" alert is not skewed by
  double counting.
  """

  @typedoc "Why a sync job failed, recorded as the `reason` tag."
  @type reason ::
          :credentials_unavailable
          | :query_failed
          | :row_errors
          | :schema_not_found
          | :permission_denied
          | :timeout
          | :exception

  @typedoc "Outcome recorded on `bigquery_sync_count`."
  @type outcome :: :success | {:failed, reason()}

  @doc """
  Records one sync outcome for a table.
  """
  @spec record(String.t(), outcome(), String.t() | atom(), non_neg_integer()) :: :ok
  def record(table, outcome, action, organization_id) do
    tags =
      %{
        table: to_string(table),
        action: to_string(action),
        organization_id: to_string(organization_id)
      }
      |> Map.merge(outcome_tags(outcome))

    Appsignal.increment_counter("bigquery_sync_count", 1, tags)

    :ok
  rescue
    # Metrics are best-effort: emitting one must never turn a healthy sync into a failed
    # one, and record/4 sits on the success path too.
    _exception -> :ok
  end

  @spec outcome_tags(outcome()) :: map()
  defp outcome_tags(:success), do: %{status: "success"}
  defp outcome_tags({:failed, reason}), do: %{status: "failed", reason: to_string(reason)}

  @doc """
  Runs `fun`, recording `{:failed, :exception}` for `table` if it raises, then re-raising.
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
      record(table, {:failed, :exception}, action, organization_id)
      reraise exception, __STACKTRACE__
  end
end
