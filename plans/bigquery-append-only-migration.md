# BigQuery Append-Only Migration Plan

Removes the `remove_duplicates` job entirely by migrating the large tables to an append-only
`*_raw` table plus a same-named view that reconstructs the current schema and semantics, then
evaluates moving the Postgres → BigQuery sync out of the Elixir app.

Tables in migration order: `messages`, `messages_media`, `contacts`, `flow_contexts`.

## Goals

1. **Delete the dedup job.** `DELETE`-based reconciliation is the wrong primitive for a
   warehouse. Nothing in BigQuery should be mutated by the sync path.
2. **No user-visible change.** `<dataset>.messages` keeps its name, its column list, its column
   order and its "one row per `id`, latest version" semantics. Existing dashboards, the
   `contacts_messages` view and the `flat_fields` procedure keep working untouched.
3. **Keep the full change history.** The raw table retains every version of every row — today
   the dedup job throws that away.
4. **Move merge logic out of the app.** Whatever reconciliation remains runs in BigQuery
   (scheduled query), not in `bigquery.ex`.

---

## Part 1 — Why `remove_duplicates` does not work

The job is `BigQuery.make_job_to_remove_duplicate/2` (`lib/glific/third_party/bigquery/bigquery.ex:1056`),
enqueued daily per table by `BigQueryWorker.periodic_updates/1`
(`lib/glific/third_party/bigquery/bigquery_worker.ex:103`), and it fails for five independent
reasons. Each is worth naming because they also constrain the fix.

### 1.1 It reports success for jobs that never ran

```elixir
GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_query(conn, project_id,
  body: %{query: sql, useLegacySql: false, timeoutMs: 120_000}
)
|> handle_duplicate_removal_job_error(table, credentials, organization_id)
```

`jobs.query` with `timeoutMs` does **not** error when the query outruns the timeout — it
returns HTTP 200 with `jobComplete: false` and a job reference to poll. That lands in the
`{:ok, _response}` clause at `bigquery.ex:1107`, which logs *"Duplicate entries have been
removed"* and records `Instrumentation.record(table, :success, :remove_duplicates, org_id)`.

On any org whose `messages` table is large enough for the DELETE to exceed two minutes — which
is every org this job actually matters for — **the metric is green and the DML never
completed**. This alone explains "the job is not working" while `bigquery_sync_count` shows no
failures.

### 1.2 The rows it targets are in the streaming buffer

Rows are written with `tabledata.insertAll` (`bigquery.ex:950`). Rows written through the
legacy streaming API cannot be touched by `UPDATE`/`DELETE`/`MERGE` — attempts fail with
*"UPDATE or DELETE statement over table would affect rows in the streaming buffer, which is not
supported"*, and rows can sit in that buffer for up to 90 minutes.

The `WHERE updated_at < now - INTERVAL 3 HOUR` guard was meant to dodge this, but `updated_at`
is the **source Postgres timestamp**, not the BigQuery arrival time. A message whose
`updated_at` is 5 hours old but which was synced 60 seconds ago passes the filter while still
being unmodifiable. `bq_inserted_at` — the column that *does* record arrival time
(`bigquery_worker.ex:1566`) — is never used by the dedup query.

### 1.3 The 90-day partition window silently excludes real duplicates

```elixir
defp partition_filter(table, timezone) when table in @partitioned_tables,
  do: "AND inserted_at >= DATETIME(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY), '#{tz}')"
```

Any row older than 90 days that gets re-synced — a delivery-status update on an old message, a
`flow_context` revived by `wakeup_flows`, a contact whose fields change — produces a duplicate
the dedup query can never see. Those duplicates are permanent.

### 1.4 Most orgs' tables are not partitioned at all

`maybe_add_partitioning/2` is only reached from `create_table/2`, and inserts against existing
tables short-circuit with `ALREADY_EXISTS` (documented at `bigquery.ex:19-22`). Every org
onboarded before #5169 has an **unpartitioned** `messages` table, so the DELETE full-scans it
on every run — feeding straight back into 1.1.

### 1.5 Cost and quota

Each DELETE rewrites every partition it touches, and BigQuery caps concurrent mutating DML per
table. Fanning ~25 tables × N orgs of large DELETEs into one daily window is the most expensive
and most quota-fragile thing the pipeline does, and every failure is fire-and-forget
(`bigquery.ex:1115-1117` deliberately swallows it).

**Conclusion:** this is not a bug to fix. Append-only removes the need for the job.

---

## Part 2 — Target architecture

For each migrated table `T`:

| Object | Kind | Role |
|---|---|---|
| `T_raw` | table, append-only | every version of every row, never mutated, never deleted |
| `T` | view | current schema + "latest row per `id`" semantics, for all consumers |
| `T_legacy` | table | the pre-migration `T`, renamed; read-only, dropped after the bake period |

### 2.1 `T_raw` layout

Same column list as `T` today, plus one new column:

```sql
bq_sequence_id  INTEGER   -- monotonic within (id), assigned by the writer
```

Partitioning and clustering change to match the append-only access pattern:

```
PARTITION BY DATE(bq_inserted_at)          -- arrival time, monotonic, never backdated
CLUSTER BY id                              -- the dedup key; ordering by id makes the
                                           -- latest-row scan a clustered range read
```

Partitioning on `bq_inserted_at` rather than `inserted_at` is the key change. `inserted_at` is
the source creation time, so an old row re-synced today lands in a year-old partition —
exactly the case that broke §1.3. `bq_inserted_at` is assigned at write time and is
monotonically increasing, so today's writes always land in today's partition and the merge
job's scan window is bounded and correct.

Set a partition expiration on `T_raw`? **No.** The user requirement is "never deleted". Storage
is long-term-priced after 90 days (~50% off) and the raw tables compress well; the change
history is the point.

### 2.2 The `T` view

The literal request — *a materialized view with the same name and schema* — is not achievable
in BigQuery, and this is the one place the plan deviates from the brief. BigQuery materialized
views support only a restricted SQL subset: aggregations with `GROUP BY` are supported, but
**analytic/window functions (`ROW_NUMBER()`, `QUALIFY`) and self-joins are not**. "Latest row
per key" cannot be expressed as a materialized view. Three workable shapes, in increasing
order of cost-efficiency and complexity:

**Option A — logical view with `QUALIFY`** (correct, zero maintenance, scans raw on every read)

```sql
CREATE OR REPLACE VIEW `<dataset>.messages` AS
SELECT * EXCEPT (bq_sequence_id)
FROM `<dataset>.messages_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY id
  ORDER BY updated_at DESC, bq_inserted_at DESC, bq_sequence_id DESC
) = 1;
```

**Option B — materialized view of the watermark + logical view join** (incremental, no scheduling)

```sql
CREATE MATERIALIZED VIEW `<dataset>.messages_mv_latest` AS
SELECT id, MAX(bq_sequence_id) AS bq_sequence_id
FROM `<dataset>.messages_raw`
GROUP BY id;

CREATE OR REPLACE VIEW `<dataset>.messages` AS
SELECT r.* EXCEPT (bq_sequence_id)
FROM `<dataset>.messages_raw` r
JOIN `<dataset>.messages_mv_latest` m USING (id, bq_sequence_id);
```

`MAX(...) ... GROUP BY` is inside the supported MV subset, and an append-only base table is the
best case for BigQuery's incremental MV refresh — it only reads new partitions. This is the
closest legal equivalent to what was asked for.

**Option C — scheduled `MERGE` into a snapshot + view over it** (cheapest reads at scale)

```sql
-- hourly BigQuery scheduled query
MERGE `<dataset>.messages_current` t
USING (
  SELECT * EXCEPT (bq_sequence_id)
  FROM `<dataset>.messages_raw`
  WHERE bq_inserted_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY bq_sequence_id DESC) = 1
) s
ON t.id = s.id
WHEN MATCHED AND s.bq_sequence_id > t.bq_sequence_id THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ROW;

CREATE OR REPLACE VIEW `<dataset>.messages` AS SELECT * FROM `<dataset>.messages_current`;
```

The MERGE touches only the recent partitions, runs against a table nothing streams into
(`messages_current` is written by load/DML only, so no streaming-buffer conflict), and the raw
history is never mutated. This is the "merge logic lives in the warehouse, not in the app"
outcome.

**Recommendation:** Option B for all four tables as the default, with Option C reserved for
`messages` on the largest orgs if MV refresh cost turns out to be material. Option A is the
fallback if MV creation is rejected for a schema we haven't anticipated. The writer code is
identical in all three cases — only the BigQuery-side DDL differs — so this choice can be made
per-org after measurement rather than up front.

### 2.3 Ordering correctness

Picking "latest" needs a total order per `id`. Two gaps today:

- `contacts` and `flow_contexts` format timestamps with `BigQuery.format_date/2`, which is
  **second granularity** (`{YYYY}-{0M}-{0D} {h24}:{m}:{s}`). Two updates in the same second are
  unorderable. `messages` and `messages_media` already use
  `format_date_with_millisecond/2`.
- `bq_inserted_at` is also assigned per-row at build time, so a single chunk of 100 rows can
  share a timestamp.

Fix both: switch `contacts` and `flow_contexts` to `format_date_with_millisecond/2`, and add
`bq_sequence_id` — a strictly increasing integer assigned by the writer
(`System.unique_integer([:monotonic, :positive])` is not durable across restarts; use
`DateTime.to_unix(:microsecond)` at row-build time, which is monotonic enough for this and
survives restarts). The view orders by `(updated_at DESC, bq_inserted_at DESC,
bq_sequence_id DESC)` so any one of them being coarse is covered by the next.

---

## Part 3 — Code changes

All under `lib/glific/third_party/bigquery/`.

### 3.1 `bigquery.ex`

| Change | Detail |
|---|---|
| Delete `make_job_to_remove_duplicate/2` | plus `generate_duplicate_removal_query/3`, `partition_filter/2`, `handle_duplicate_removal_job_error/4`, `format_datetime/2`, `@partition_window_days` |
| Add `@append_only_tables` | `~w(messages messages_media contacts flow_contexts)`, the migration cohort |
| Add `raw_table/1` | `"messages" -> "messages_raw"` for cohort members, identity otherwise — the single place that decides where a write lands |
| Change `create_tables/4` | for cohort members create `T_raw` (partitioned on `DATE(bq_inserted_at)`, clustered by `id`) and then `T` as a view; non-cohort tables unchanged |
| Add `create_view/2` and `create_materialized_view/2` | mirroring `create_table/2`; reuse `Schema.<table>_schema/0` to generate the explicit column list so the view's column order matches today's table exactly |
| Change `alter_tables/4` | schema evolution now targets `T_raw` and then re-issues `CREATE OR REPLACE VIEW T` so a new column appears in both |
| `maybe_add_partitioning/2` | for cohort tables partition on `bq_inserted_at` (DAY); leave the `@partitioned_tables` behaviour for everything else |

Explicit column lists in the view (rather than `SELECT * EXCEPT(...)`) matter: `SELECT *` would
reorder columns if a field is added to the middle of a `Schema` function, and some BI tools bind
by position.

### 3.2 `bigquery_worker.ex`

| Change | Detail |
|---|---|
| Delete the `"remove_duplicates" => true` clause of `perform/1` | `bigquery_worker.ex:184-202` |
| Delete `init_removal_job/2` | `bigquery_worker.ex:170` |
| Reduce `periodic_updates/1` to `:ok` | or delete it and its `MinuteWorker` call at `minute_worker.ex:143` |
| Remove `:remove_duplicates` from the Oban `unique` keys | `bigquery_worker.ex:27` |
| Route writes through `BigQuery.raw_table/1` | in `make_job/4` (`bigquery_worker.ex:1683`), so `queue_table_data/3` stays untouched |
| Add `bq_sequence_id` to `bq_fields/1` | `bigquery_worker.ex:1563` |
| Switch `contacts` and `flow_contexts` to `format_date_with_millisecond/2` | `queue_table_data/3` clauses at lines 973 and 1319 |

Note `queue_message_media_data/3` is also called from the GCS worker — routing at `make_job/4`
rather than inside each `queue_table_data/3` clause keeps that path correct for free.

### 3.3 `bigquery_schema.ex`

Add the `bq_sequence_id` field (`INTEGER`, `NULLABLE`) to `message_schema/0`,
`messages_media_schema/0`, `contact_schema/0`, `flow_context_schema/0`. It exists only in
`T_raw`; the view drops it, so the user-visible schema is unchanged.

### 3.4 `instrumentation.ex`

Drop `:remove_duplicates` from the documented action set and the moduledoc status table. Add
one new status for the migration itself so a botched cutover is visible:
`:view_creation_failed`.

Separately, fix §1.1 for the load path too: `handle_insert_query_response/3` should treat a
`jobComplete: false` response as a non-success. That bug class is what hid the dedup failure and
will hide the next one.

### 3.5 Feature flag and cutover state

Per-org, per-table cutover state belongs in `bigquery_jobs`, which already exists per
`(organization_id, table)`:

```elixir
# priv/repo/migrations/<ts>_add_bigquery_jobs_write_target.exs
alter table(:bigquery_jobs) do
  add :write_target, :string,
    default: "table",
    null: false,
    comment: "Where the sync writes: 'table' (legacy) or 'raw' (append-only, read via a view)"
end
```

`raw_table/1` becomes `raw_table/2` taking the job row, so a single org+table can be flipped,
observed, and flipped back without a deploy. This is preferable to a `FunWithFlags` flag because
the cutover is per-table, not per-org, and the state must be readable from the same row the
writer already loads.

---

## Part 4 — Cutover runbook (per org, per table)

Ordered `messages_media` → `flow_contexts` → `contacts` → `messages`: smallest blast radius
first, and `messages` last because `contacts_messages` depends on it.

```
1. Deploy the code. No behavioural change: write_target is still "table" everywhere.

2. Create the raw table (idempotent, per org):
     Glific.Scripts.BigQueryMigration.prepare(org_id, "messages")
   - creates messages_raw partitioned on DATE(bq_inserted_at), clustered by id
   - copies the existing table in:  bq cp <ds>.messages <ds>.messages_raw
     (a copy job is free and does not scan)
   - backfills bq_sequence_id for the copied rows from bq_inserted_at

3. Flip the writer:
     Jobs.update_bigquery_job(org_id, "messages", %{write_target: "raw"})
   New rows now land in messages_raw. The legacy table stops growing.

4. Wait one cron tick (2 min) plus the streaming-buffer flush, then verify:
     SELECT COUNT(*) FROM <ds>.messages_raw          -- >= legacy count
     SELECT COUNT(DISTINCT id) FROM <ds>.messages_raw
     -- must equal SELECT COUNT(DISTINCT id) FROM <ds>.messages

5. Swap (the only step with user-visible risk — run it off-peak in the org's timezone):
     ALTER TABLE `<ds>.messages` RENAME TO `messages_legacy`;
     CREATE MATERIALIZED VIEW `<ds>.messages_mv_latest` AS ...;
     CREATE VIEW `<ds>.messages` AS ...;

6. Verify parity against the frozen legacy table:
     -- row counts match
     SELECT (SELECT COUNT(*) FROM `<ds>.messages`)
          - (SELECT COUNT(DISTINCT id) FROM `<ds>.messages_legacy`);   -- expect 0
     -- no column drift
     SELECT column_name, ordinal_position, data_type
     FROM `<ds>.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'messages'
     -- diff against the same query on messages_legacy
     -- spot-check a sampled id resolves to the same row in both

7. Bake for 14 days, then DROP TABLE `<ds>.messages_legacy`.
```

**Honest caveat on step 5:** BigQuery has no atomic table→view swap and DDL is not
transactional, so there is a sub-second window between the `RENAME` and the `CREATE VIEW` where
`<dataset>.messages` does not exist. A dashboard query issued in that window errors. There is no
way to eliminate it; mitigate by scripting the two statements as one multi-statement request
and running it off-peak per org. The alternative — pointing dashboards at a differently named
view — was rejected because it breaks the "no change for the user" requirement.

**Rollback at any point before step 7** is `write_target: "table"` plus, if step 5 has run,
`DROP VIEW messages; ALTER TABLE messages_legacy RENAME TO messages`. Rows written to
`messages_raw` in the interim are re-synced by resetting the `bigquery_jobs` watermark.

---

## Part 5 — Moving the sync out of the app

### 5.1 The constraint that decides this

`BigQuery.decode_bigquery_credential/3` (`bigquery.ex:249`) shows the tenancy model:

```elixir
{:ok, %{conn: conn, project_id: project_id, dataset_id: org_contact.phone}}
```

`project_id` comes from **the org's own service-account JSON** and `dataset_id` is the org's
contact phone. Each NGO owns its own GCP project. One shared Postgres database fans out to N
customer-owned BigQuery projects, with N sets of credentials.

Every off-the-shelf CDC tool models a pipeline as *one source → one destination*, and none of
them can filter CDC rows by a column value — table include/exclude only. So a Datastream stream
or Airbyte connection pointed at org A's project would carry **every org's rows**. That is not a
cost problem, it is a **cross-tenant data leak**. This, not the tool selection, is the actual
blocker, and it holds for PeerDB, Datastream, Airbyte and Fivetran alike.

### 5.2 Options evaluated

| Option | Self-hosted | Per-org isolation | Verdict |
|---|---|---|---|
| **PeerDB** | yes | ✗ no row filter on CDC | **Ruled out on a second ground: the BigQuery destination connector is deprecated and no longer maintained.** The maintained paths are Postgres→ClickHouse and Postgres→Postgres. |
| **Google Datastream** | no (managed GCP) | ✗ no row filter | Native BigQuery destination with an explicit *append-only* write mode that matches this plan's target exactly — but one stream per org replicates all orgs' rows into each org's project. Viable **only** after a tenancy change (§5.4). |
| **Airbyte OSS** | yes | ✗ for CDC; ✓ if replicating per-org Postgres views, but that abandons CDC for cursor-based batch — i.e. what Glific already does, in another runtime | Not worth the operational cost. |
| **Sequin** (Elixir, Docker) | yes | ✓ routing/transform functions written in Elixir can route by `organization_id` | Closest fit *architecturally* — WAL-based, append-only by nature, Elixir-native. But it has **no BigQuery sink**; the path is Sequin → GCP Pub/Sub → Pub/Sub BigQuery subscription, needing one topic + subscription per (org, table). See §5.3. |
| **Keep Elixir, change the write API** | n/a | ✓ already correct | **Recommended.** See §5.3. |

### 5.3 Recommendation: keep the loader in Elixir, replace `insertAll` with load jobs

The thing that is actually wrong with the current sync is not that it is written in Elixir — it
is that it uses `tabledata.insertAll`. That single choice causes the streaming buffer lock
(§1.2), costs $0.05/GB, and gives no exactly-once guarantee.

Replace it with **BigQuery load jobs**: serialise the chunk as newline-delimited JSON and submit
`jobs.insert` with `writeDisposition: WRITE_APPEND` and `sourceFormat: NEWLINE_DELIMITED_JSON`,
uploading the body as multipart media (`GoogleApi.BigQuery.V2.Api.Jobs.bigquery_jobs_insert_simple/5`
in `google_api_big_query ~> 0.47` — **verify this arity against the vendored dep before
committing to it**; the fallback is a hand-rolled Tesla multipart request to
`/upload/bigquery/v2/projects/{id}/jobs`).

What this buys:

- **Load jobs are free.** No per-GB ingestion charge at all.
- **No streaming buffer.** Loaded rows are immediately queryable *and* immediately mutable, so
  the Option C scheduled MERGE works without a 90-minute wait.
- **Atomic per chunk.** A load job either commits all rows or none, so a partial-chunk failure
  no longer leaves half a batch behind for the (now deleted) dedup to clean up.
- **It preserves the per-org credential model exactly** — the same `conn` from
  `fetch_bigquery_credentials/1`, no new infrastructure, no new service to operate.

Trade-off: load jobs are quota'd (1,500 per table per day, 100k per project per day) and are
not real-time — a job takes seconds to minutes. At the current cadence (one load per table per
2-minute tick = 720/day/table) this fits, but it is within a factor of 2 of the ceiling, so
`@per_min_limit` batching must not be made more granular. If sub-minute freshness is later
required, the correct next step is the **Storage Write API** (gRPC, exactly-once via offsets,
DML-compatible) — which has no maintained Elixir client and would need generated protobuf
stubs. That is a separate, larger project and should not block this one.

### 5.4 If the tenancy model changes

Should Glific move to schema-per-tenant or database-per-tenant in Postgres, the calculus flips
and **Datastream becomes the right answer**: a per-tenant source scope makes per-org streams
safe, its BigQuery append-only write mode is precisely this plan's target shape, and it is fully
managed inside the GCP account each org already owns.

There is one further mismatch to plan for in that case. Glific's BigQuery tables are **not**
mirrors of Postgres tables — `get_message_row/2` (`bigquery_worker.ex:1603`) denormalises across
contacts, users, flows, tags, media, groups and templates to produce `contact_phone`,
`flow_name`, `tags_label`, `media_url` and friends. A CDC tool replicates raw tables and knows
nothing about that. Adopting one means rebuilding every denormalisation as a BigQuery view or
Dataform model over the replicated raw tables. That work is substantial, but it composes
cleanly with this plan — the raw+view split established here is the same shape a CDC pipeline
would land in, so Part 2 is a prerequisite either way rather than throwaway work.

---

## Part 6 — Tests

| File | Change |
|---|---|
| `test/glific/bigquery_test.exs` | Delete `"make_job_to_remove_duplicate/2 should delete duplicate messages"` (:114) and `"...should raise info log"` (:137). Delete the `remove_duplicates: true` job assertions at :85 and :94. |
| `test/glific/bigquery_instrumentation_test.exs` | Delete the `describe "make_job_to_remove_duplicate/2"` block (:127-158). |
| `test/glific/bigquery_test.exs` (new) | `create_tables/4` issues a `messages_raw` insert with `timePartitioning.field == "bq_inserted_at"` and `clustering.fields == ["id"]`, followed by a view insert for `messages`. |
| `test/glific/bigquery_test.exs` (new) | `raw_table/2` returns `"messages_raw"` when `write_target == "raw"` and `"messages"` otherwise; non-cohort tables always return themselves. |
| `test/glific/bigquery_test.exs` (new) | `bq_fields/1` emits a `bq_sequence_id` that strictly increases across two calls. |
| `test/glific/bigquery_test.exs` (new) | A `jobs.query`/load response with `jobComplete: false` records a non-success status (the §1.1 regression guard). |
| `test/glific/bigquery_test.exs` (new) | `contacts` and `flow_contexts` rows carry millisecond-precision `updated_at`. |

All BigQuery HTTP is already mocked via `Tesla.Mock` in these files; the new cases follow the
same setup.

---

## Part 7 — Sequencing

| Step | Scope | Reversible |
|---|---|---|
| 1 | Migration: `bigquery_jobs.write_target` | yes |
| 2 | `bq_sequence_id` in schema + `bq_fields/1`; millisecond timestamps for `contacts`/`flow_contexts` | yes |
| 3 | `raw_table/2` + routing in `make_job/4`; `create_view/2`, `create_materialized_view/2`, raw-table creation in `create_tables/4` | yes — dormant until a `write_target` flips |
| 4 | `Glific.Scripts.BigQueryMigration` (prepare / flip / swap / verify / rollback per org+table) | yes |
| 5 | Cutover one internal org, all four tables, per the Part 4 runbook | yes |
| 6 | Cutover remaining orgs in batches, `messages` last | yes |
| 7 | **Delete** `make_job_to_remove_duplicate/2`, `init_removal_job/2`, `periodic_updates/1` and the `MinuteWorker` call | — |
| 8 | Replace `insertAll` with load jobs (§5.3), behind the same per-table flag | yes |
| 9 | Drop `*_legacy` tables after the 14-day bake | — |

Step 7 is deliberately after the cutover, not before: while any org still has
`write_target: "table"`, its table still accumulates duplicates and still needs the dedup, however
poorly it runs.
