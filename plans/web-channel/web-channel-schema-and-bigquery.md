# Web Channel — Schema Evolution & BigQuery Compatibility

How adding `messages.channel` (and, later, `flow_type` / `supported_channels`) reaches
organizations' BigQuery datasets, and how to roll it out so **no existing org's data warehouse or
dashboards break.** Grounded in a code investigation of `lib/glific/third_party/bigquery/`
(`bigquery.ex`, `bigquery_schema.ex`, `bigquery_worker.ex`, `bigquery_job.ex`).

**Headline:** none of the BigQuery modules are touched on this branch — the prototype's `channel`
work is Postgres-only. The BigQuery changes below are **net-new design work**, and there is a
sharp, silent failure mode if they're sequenced wrong.

---

## 1. How the sync actually works

- **Cron-triggered Oban worker, not DB triggers.** `MinuteWorker`'s `"bigquery"` branch
  (`minute_worker.ex:84`) fans out `BigQueryWorker.perform_periodic/1` per BigQuery-enabled org.
- **Legacy streaming inserts** (`tabledata.insertAll`), 100 rows/batch (`bigquery.ex:916`).
- **Cursor-based incremental:** inserts pull `id > cursor`; updates pull `updated_at > cursor`
  (`bigquery_worker.ex:211`/`:228`). Cursors live in the `bigquery_jobs` table.
- **A dedup DELETE pass** runs periodically because streaming double-writes updated rows.
- Reads come from a **replica**, org-scoped.

Synced tables relevant to us: `messages`, `flows`, `flow_contexts`, `flow_results`, `contacts` —
all synced. `messages` is MONTH-partitioned on `inserted_at`, clustered on
`[contact_phone, flow_id]`.

---

## 2. The crux: the schema is hand-maintained in two places, and order matters

The BigQuery schema is **not derived from Postgres.** It's a hardcoded Elixir field list
(`bigquery_schema.ex`, 3200+ lines, one fn per table). Adding a column that reaches BigQuery
requires editing **two independent places by hand**:

1. the **schema-fn** — e.g. `message_schema` (`bigquery_schema.ex:254`) — declaring the column;
2. the **row-builder** — e.g. `get_message_row/2` (`bigquery_worker.ex:1543`) — emitting the value.

The row-builder is an **explicit named-key map**, not `Map.from_struct`. This is the key safety
property:

> **The Postgres migration is completely inert for BigQuery until the row-builder emits the field.**

So the already-shipped `add_channel_to_messages` migration changes *nothing* about BigQuery today.
That gives us a clean lever to sequence the rollout safely.

---

## 3. The silent failure mode (why ordering is not optional)

There is an existing table-patch path — `alter_table/2` (`bigquery.ex:777`) issues a full-schema
PUT that BigQuery accepts as an additive column add **iff the new field is `NULLABLE`.** But:

- It runs **only** via `sync_schema_with_bigquery` → `do_refresh_the_schema`, whose triggers are:
  (a) an org **re-saving its BigQuery credential** (`partners.ex:1071`), (b) the ops/iex bulk path
  `Seeds.SeedsMigration.sync_schema_with_bigquery/1` (`seeds_migration.ex:425`), (c) a `NOT_FOUND`
  (missing-table) insert error.
- **The periodic data sync NEVER refreshes the schema.** So an existing org does **not** get a new
  column automatically — someone must explicitly patch it.
- `alter_tables` loops orgs in a **fire-and-forget `Task.async` whose result is never awaited or
  logged** (`bigquery.ex:447`) — a failed patch fails **silently**.

**The breaking case:** if the row-builder emits `channel` to an org whose BigQuery table doesn't
yet have the column, `insertAll` returns HTTP 200 with an `insertErrors` array (`no such field:
channel`). The insert body sets **no `ignoreUnknownValues`**, and the handler treats any
`insertErrors` as fatal — `raise` (`bigquery.ex:934`). With `max_attempts: 1`, the job dies and
**that org's message sync stalls.** It does **not** self-heal (the auto-refresh only fires on
`NOT_FOUND`, a different code path). Emit-before-patch = broken warehouse, silently, per org.

That NULLABLE-and-unemitted columns are safe is proven in-tree: `message_schema` already declares
`group_message_id`/`flow_broadcast_id` that the row-builder never emits — they sit NULL, no errors.

---

## 4. Non-breaking rollout for `messages.channel`

Existing Postgres rows are already `'whatsapp'` (migration default), so **no Postgres backfill is
needed.** The BigQuery side is a strict 4-step order:

1. **[done] Ship the Postgres migration.** Inert for BigQuery. *(But make it table-rewrite-safe
   first — see §6; that's a Postgres-availability issue, separate from BigQuery.)*
2. **Add `channel` as `NULLABLE STRING`** to `message_schema` (`bigquery_schema.ex:254`). Do **not**
   touch the row-builder yet. `NULLABLE` is mandatory — BigQuery rejects adding a `REQUIRED` column
   to an existing table, and `alter_tables` would swallow that failure silently.
3. **Bulk-patch every existing BigQuery-enabled org** via
   `Seeds.SeedsMigration.sync_schema_with_bigquery(org_ids)`. Because the patch is fire-and-forget,
   **verify** each org's table schema afterward (spot-check `information_schema.columns`) rather
   than trusting a return value.
4. **Only after step 3 completes for all orgs**, add `channel: row.channel` to `get_message_row/2`
   (`bigquery_worker.ex:~1547`) and deploy. Every table already has the column, so inserts succeed
   everywhere.

**Never collapse 2+4 ahead of 3.** That is precisely the emit-before-patch crash.

**Optional defense-in-depth:** add `ignoreUnknownValues: true` to the `insertAll` body
(`bigquery.ex:916`) so an un-patched org silently *drops* the field instead of crashing. It removes
the hard ordering dependency but permanently masks genuine schema drift — gate it deliberately, and
if adopted, treat it as a general hardening of the sync, not a web-channel special case.

---

## 5. `flow_type` / `supported_channels` — same recipe, one extra hazard

`flow_type` is a real column on `flows` but is **not currently synced to BigQuery** (the BQ `flows`
row-builder emits only id/name/uuid/keywords/status/revision/tag). Same 4-step order applies if we
want it in the warehouse.

**The extra wrinkle bears directly on the `flow_type`-enum-vs-`supported_channels`-array decision:**
the BigQuery `flows` table is **insert-only** — `flows` is in `ignore_updates_for_table/0`
(`bigquery.ex:175`), so a flow synced once is **never re-synced on update.**

- `flow_type` set at creation and never changed → fine.
- A **mutable `supported_channels`** array that an author edits later → the change would **never
  propagate to BigQuery.** The warehouse would hold the value as of first sync, forever.

This is a real strike against a mutable `supported_channels` unless we also remove `flows` from the
insert-only set (a broader change with its own dedup implications). It doesn't settle the decision,
but the tech design must weigh it: the "more flexible" array is *less* warehouse-friendly than the
enum, given the current sync.

`flow_contexts.channel` (also added in Postgres on this branch) is BQ-synced but, like the others,
has zero BigQuery impact until both schema-fn and row-builder are edited.

---

## 6. Postgres-side safety (independent of BigQuery)

Separate from the warehouse: the `add_channel_to_messages` migration adds `null: false, default:
"whatsapp"` to `messages`, a very large table — a **full table rewrite + lock** per Glific's
migration guide. Rework to the safe pattern: **nullable add → batched backfill → set default**
(the schema already defaults `channel` in the changeset, so reads are safe during the window).
Same consideration for `flow_contexts` if it's large.

---

## 7. Historical rows in BigQuery

The incremental sync only re-pulls rows with a new `id` or bumped `updated_at`. The migration does
**not** bump `updated_at`, so already-synced historical messages read `channel = NULL` in BigQuery.
Two options:

- **Recommended, cheapest:** document `COALESCE(channel, 'whatsapp')` for report authors. Existing
  dashboards that don't reference `channel` are unaffected regardless.
- **Full fidelity:** one-time per-dataset `UPDATE {dataset}.messages SET channel='whatsapp' WHERE
  channel IS NULL;` after step 3. Bounded DML, run per org dataset.

---

## 8. Recommendations for the tech design

1. **Adding channel columns to the warehouse is safe and additive — but only with the strict
   patch-before-emit order.** Bake the 4-step sequence (and the per-org verify) into the rollout
   runbook; it is the single most breakable operation in this whole feature.
2. **Treat the BigQuery schema/row-builder edits as first-class deliverables**, not an afterthought
   — the Postgres migration alone gives NULL columns and a false sense of "done."
3. **Weigh the insert-only `flows` constraint against `supported_channels` mutability.** If channels
   per flow must be editable post-creation *and* appear correctly in the warehouse, the enum is the
   safer model, or `flows` must leave the insert-only set.
4. **Default NULL → whatsapp semantics everywhere** (COALESCE), so no existing report breaks and no
   historical backfill is strictly required.
5. Consider `ignoreUnknownValues` as a broader sync-hardening, decided on its own merits.

Cross-references: file-by-file backend map → `web-channel-backend-breakdown.md`; the migration
rewrite-safety point also appears there (§1).
