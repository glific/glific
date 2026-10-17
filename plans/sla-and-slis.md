# Platform SLAs, SLIs and pipeline latency metrics

## Why

Two goals:

1. **Show users we are fine** — a published availability commitment and a public status page.
2. **Measure platform stability** — catch "message processing is slow" early. The Q3 incidents
   were slowdowns, not outages: the API stayed up while work queued. No availability metric
   catches that, so latency must be a first-class SLI.

## Industry baseline

| Provider | Commitment | Measured as | Remedy |
|---|---|---|---|
| Twilio | 99.95% / month (99.99% Enterprise) | API availability, unavailable minutes | 10% credit |
| Bird (MessageBird) | 99.95% SMS API, 99.9% voice/dashboard | % of 5-min windows unavailable; third-party (carrier/Meta) excluded | ~10% credit, discretionary |
| Gupshup | 99.9% (marketing); formal SLA via sales | not public | not public |
| Wati / Infobip | 99.9% (marketing) | not public | not public |
| 360dialog | 98–99% by plan | own platform only, Meta excluded | plan-dependent |
| Meta Cloud API | ~99.9% (quoted by BSPs) | minutes unable to send/receive | none |

Nobody commits to processing or delivery latency, and all exclude upstream (Meta, carriers).
Glific sits downstream of Gupshup and Meta, so any external number must exclude their outages.

## Terminology

- **SLI** — a ratio of good events to valid events, measured automatically.
- **SLO** — internal target for an SLI over a window (e.g. 99% over 28 days).
- **SLA** — the subset of SLOs we publish, set looser than the internal SLO.
- **Error budget** — `1 − SLO`; a slowdown and an outage spend the same budget.

## Measurement model

- **Request-based** SLIs from real traffic (good = not 5xx and not timed out; 4xx is the
  client's problem and excluded).
- **Synthetic probes** (AppSignal Uptime Monitoring) to catch total outages where no traffic
  reaches the app.
- **Incidents** are the communication layer and the place exclusions are recorded — never the
  source of the number.
- Everything is aggregated per minute (AppSignal's resolution). A minute is **bad** for an
  availability SLI when its error ratio exceeds 5% or the synthetic probe failed.

## Exclusions (apply to every external SLA)

- Meta / WhatsApp Cloud API and Gupshup outages (tracked via the dependency SLIs below so the
  exclusion is evidenced, not asserted).
- NGO-owned webhooks, LLM/AI providers, Google (BigQuery/GCS/Sheets), Dialogflow.
- Planned maintenance announced ≥ 48h ahead.
- Deliberate throttling: per-org BSP rate limit (`bsp_limit`), broadcast pacing
  (`broadcast_contact_count`), Meta tier limits.

## External SLA (published)

| SLA | Target | Composed of |
|---|---|---|
| **Platform availability** | **99.9% / calendar month** (~43 min) | API availability SLI, webhook-ingest SLI, synthetic probes |
| **Message processing** | publish only after 2 months of baseline; proposed **99% of inbound messages processed within 10s** | inbound processing SLI |

Start by publishing availability only. Latency goes public once we know we meet it.

## SLI catalogue

### A. API (user-facing)

| SLI | Good event | Source | Internal SLO |
|---|---|---|---|
| A1 GraphQL availability | `/api` request not 5xx, not raised | `[:absinthe, :execute, :operation, :stop]` + `[:phoenix, :endpoint, :stop]` | 99.95% |
| A2 GraphQL latency (key ops) | op completes < threshold | same, tagged `operation` | 99% < threshold |
| A3 REST auth | `/api/v1/session*`, `/users/log_in` not 5xx | `[:phoenix, :endpoint, :stop]` | 99.95% |
| A4 Flow editor save | `/flow-editor/revisions` not 5xx, < 3s | `[:phoenix, :endpoint, :stop]` | 99.9% |
| A5 Synthetic | probe returns 200 | AppSignal Uptime on frontend + new `/health` (DB ping) | 99.9% |

Key GraphQL operations tracked individually in A2 (allow-list to bound tag cardinality;
everything else rolls up as `other`):

| Operation | Latency threshold |
|---|---|
| `createFlow`, `updateFlow`, `publishFlow` | 3s |
| `createTrigger`, `updateTrigger` | 2s |
| `startContactFlow`, `startGroupFlow` | 2s |
| `createAndSendMessage`, `sendHsmMessage`, `createAndSendMessageToGroup` | 2s |
| `contacts`, `conversations`, `search` (reads) | 1s |

GraphQL returns 200 with an `errors` array for resolver errors such as "not found" — those are
user errors and stay good. Only exceptions / 5xx count as bad.

### B. Messaging pipeline

| SLI | Good event | Start → end | Internal SLO |
|---|---|---|---|
| B1 Webhook ingest (Gupshup) | BSP webhook not 5xx and answered < 2s | request in → response out | 99.95% |
| B2 **Inbound processing** | message tagged + flow step run within 10s | `message.inserted_at` → `MessageWorker.perform` returns | 99% < 10s |
| B3 **Outbound session send** | non-HSM message accepted by Gupshup within 5s | `message.inserted_at` → `sent_at` (`handle_success_response`) | 99% < 5s |
| B4 Outbound HSM send | HSM accepted within 60s, throttling excluded | same, `is_hsm: true` | 95% < 60s |
| B5 Flow wakeup lateness | context woken within 90s of `wakeup_at` | `flow_context.wakeup_at` → `wakeup_one` start | 99% < 90s |
| B6 Trigger start lateness | trigger fires within 2 min of `next_trigger_at` | `next_trigger_at` → `do_execute_trigger` | 99% < 2 min |

Notes:

- B2 starts at `inserted_at`, not at enqueue, so it covers the webhook, insert and queue wait.
- B3/B4 must be end-to-end: `Providers.BSPWorker.default_send_rate_handler/0` snoozes
  rate-limited jobs (`{:snooze, 1}`), and Oban's `queue_time` resets on every snooze, so
  `oban_job_latency` under-reports outbound delay.
- B5: the minute cron already allows up to 60s of lateness by design, hence 90s.
- B6: `Triggers.execute_triggers/2` shifts `now` forward 1 minute, so triggers can fire up to
  60s early; record the signed value, SLO on lateness only.

### C. Dependencies (for exclusions, not our SLA)

| SLI | Source |
|---|---|
| C1 Gupshup send API error rate / latency | existing `tesla_request_error_count`, `tesla_request_response` (`provider: gupshup`) |
| C2 Gupshup inbound liveness | existing `gupshup_seconds_since_last_inbound` |
| C3 Meta status | Meta WhatsApp status page, recorded on our incidents |

## Internal latency metrics for the critical queues

Queues in scope: `gupshup`, `gupshup_high_tps`, `gupshup_inbound`, `flow_wakeup`.

### What exists and why it is not enough

`Glific.Appsignal.handle_event/4` (`[:oban, :job, :stop]`) emits `oban_job_latency` (queue wait)
and `oban_job_duration`, but:

1. **Tagged with `organization_id`** — AppSignal cannot merge percentiles across tag values, so
   there is no platform-wide p95 per queue.
2. **Sampled** by `APPSIGNAL_SAMPLING_RATE` — fine for percentiles, wrong for SLO counts.
3. **Per attempt** — snoozes reset `scheduled_at`, hiding throttling delay on outbound.
4. **`oban_queue_size` is a once-a-minute gauge** — AppSignal keeps only the last value per
   minute, so sub-minute bursts (e.g. the `flow_wakeup` burst at the top of each minute) read 0.

### New metrics

All unsampled for the four queues; tags kept to low cardinality.

| Metric | Type | Tags | Emitted from |
|---|---|---|---|
| `oban_queue_wait_seconds` | distribution | `queue` | `[:oban, :job, :stop]` + `[:oban, :job, :exception]`, `measurement.queue_time` |
| `oban_job_run_seconds` | distribution | `queue`, `state` (`success`/`failure`/`snoozed`) | same, `measurement.duration` |
| `oban_queue_oldest_available_seconds` | gauge | `queue` | telemetry poller (60s): `now − min(scheduled_at)` where `state = 'available'` |
| `inbound_processing_seconds` | distribution | `outcome` | `Processor.MessageWorker.perform/1`: `now − message.inserted_at` |
| `outbound_send_seconds` | distribution | `type` (`hsm`/`session`), `queue` | `Communications.Message.handle_success_response/2`: `sent_at − inserted_at` |
| `flow_wakeup_lateness_seconds` | distribution | — | `FlowContext.wakeup_one/2`: `now − wakeup_at` |
| `trigger_start_lateness_seconds` | distribution | — | `Triggers.do_execute_trigger`: `now − next_trigger_at` |
| `slo_event_count` | counter | `sli`, `result` (`good`/`bad`) | alongside each distribution above, using the SLO threshold |

`oban_queue_oldest_available_seconds` is the backlog signal to alert on: it rises during a
slowdown regardless of when in the minute the gauge is sampled, unlike queue size.

`slo_event_count` exists because AppSignal stores per-minute percentiles, and a month of p95
graphs cannot be turned back into "% of messages under 10s". Good/total from this counter is
the monthly SLA figure.

Per-org drill-down stays on the existing org-tagged `oban_job_latency`.

## Database connection pool metrics

Every job and request needs a DB connection, so a saturated Ecto pool shows up as latency in
every queue at once while CPU and the DB itself can look healthy.

There are two separate limits, and they fail differently:

- **Server-side**: production uses ~130 connections against Postgres `max_connections` = 600,
  so the database has plenty of headroom.
- **Client-side (per node)**: each node's Ecto pool is capped at `POOL_SIZE`
  (`config/runtime.exs`), while the Oban queues in `config/config.exs` allow up to
  **201 concurrent jobs per node** (sum of `limit`/`local_limit`), plus web requests and Oban's
  own queries. Most jobs spend time off the DB (HTTP calls), so this is not automatically a
  problem, but when the pool is exhausted, work waits in the pool queue on the node even though
  the server could accept more connections.

So the likely bottleneck is the per-node pool, not Postgres — and with ~470 spare server
connections, raising `POOL_SIZE` is a cheap fix *if* the metrics below show pool waits.

Ecto's `[:glific, :repo, :query]` event (already attached, handled by
`Glific.Appsignal.handle_event/4`) carries `queue_time`: time spent waiting to check out a
connection. It is absent when the query reuses an already checked-out connection (inside a
transaction), so `nil` is skipped.

| Metric | Type | Tags | Source |
|---|---|---|---|
| `db_pool_queue_ms` | distribution, sampled at `APPSIGNAL_SAMPLING_RATE` (very high volume) | `repo` | `measurement.queue_time` |
| `db_pool_queue_slow_count` | counter, unsampled | `repo` | `queue_time` > 50ms |
| `db_connection_count` | gauge | `state` (`active`, `idle`, `idle in transaction`) | telemetry poller (60s): `pg_stat_activity` for the app's role — cluster-wide view across nodes |
| `db_connection_utilization_percent` | gauge | — | same poller: total connections ÷ `max_connections` (600) |
| `glific.repo.db_connection_error` | counter (exists) | `repo`, `reason` | checkout timeouts / dropped connections |

Reading them together:

| Pattern | Meaning |
|---|---|
| `db_pool_queue_ms` p95 high, server utilization low (~130/600) | per-node pool too small — raise `POOL_SIZE`; headroom exists |
| `db_pool_queue_ms` p95 high, server utilization near 600 | server-side limit — needs a pooler (PgBouncer) or fewer connections per node, not a bigger pool |
| `db_pool_queue_ms` high, many `idle in transaction` | connections held during slow non-DB work inside transactions |
| `db_pool_queue_ms` low, `oban_queue_wait_seconds` high | bottleneck is queue limits, not the DB pool |
| `db_connection_error` rising | pool exhausted past `queue_target`/`queue_interval`; requests failing |

### Initial alert thresholds (calibrate after 2 weeks of data)

| Signal | Warning (5 min) | Critical (5 min) |
|---|---|---|
| `inbound_processing_seconds` p95 | > 5s | > 30s |
| `oban_queue_oldest_available_seconds{gupshup_inbound}` | > 30s | > 120s |
| `outbound_send_seconds{type: session}` p95 | > 5s | > 30s |
| `oban_queue_oldest_available_seconds{gupshup, gupshup_high_tps}` | > 120s | > 600s |
| `flow_wakeup_lateness_seconds` p95 | > 90s | > 300s |
| `gupshup_seconds_since_last_inbound` | > 600s | > 900s |
| GraphQL 5xx ratio | > 1% | > 5% |
| `db_pool_queue_ms` p95 (`repo`) | > 50ms | > 500ms |
| `glific.repo.db_connection_error` | > 0 | > 10 / min |
| `db_connection_utilization_percent` | > 60% (360) | > 80% (480) |
| `MinuteWorker` heartbeat check-in | missed 2 min | missed 5 min |

## AppSignal setup

1. **Dashboards** — "Messaging pipeline" (B2–B6 + queue wait/oldest per queue) and
   "API" (A1–A4, per-operation latency).
2. **Triggers** — the alert table above, routed to Discord/on-call.
3. **Uptime monitors** — frontend, GraphQL `/api` (introspection-free POST), new `/health`.
4. **Public status page** — built from the uptime monitors; incidents posted there.
5. **Check-ins** — `Appsignal.CheckIn.heartbeat` in `Jobs.MinuteWorker` so a stalled cron is
   noticed even when latency metrics simply go silent.
6. **Webhook visibility** — `gupshup_webhooks` is in `ignore_namespaces` (cost). Keep it
   ignored; B1 comes from a `[:phoenix, :endpoint, :stop]` handler emitting a counter and
   distribution for BSP paths only.

## Monthly SLA report

- Availability = 1 − (bad minutes ÷ minutes in month), bad minute per the measurement model,
  minus minutes covered by an excluded incident.
- Processing = `slo_event_count{sli: inbound_processing, result: good}` ÷ total.
- Pulled via the AppSignal API into a small report; incidents and their exclusion reason come
  from the status page.

## Rollout

1. No code: dashboards + alerts on existing metrics; uptime monitors; status page.
2. Code PR 1: queue-level unsampled `oban_queue_wait_seconds` / `oban_job_run_seconds`,
   `oban_queue_oldest_available_seconds`, DB pool metrics, `MinuteWorker` heartbeat, `/health`.
3. Code PR 2: end-to-end distributions (B2–B6) + `slo_event_count`.
4. Code PR 3: API SLIs (Absinthe + Phoenix endpoint handlers, BSP webhook ingest).
5. After 2 months: fix targets from baseline, publish availability SLA; decide on publishing
   message processing.

## Open questions

- Gupshup's webhook timeout and retry policy (sets B1's threshold).
- AppSignal plan: confirm uptime monitors and public status page are included.
- Whether NGOs need per-org SLA reporting (would need org-tagged SLO counters, at higher cost).
