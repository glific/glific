# Inbound → Flow → Reply: latency bottlenecks and redundancy audit

Scope: everything from Gupshup POSTing an inbound WhatsApp message to Glific, through the flow that
it triggers, up to the moment Glific issues the outbound HTTP request to Gupshup. **Gupshup's own
network/processing time is excluded.** Status callbacks (enqueued/sent/delivered/read) are included
because they hit the same tables, pool and locks as the hot path.

Method: static read of the code at `553e777` (2026-11-06). Query counts are derived from code, not
measured. Library internals (Oban Pro, Cachex, DBConnection, ExRated, Absinthe) are from the pinned
versions in `mix.lock` (oban 2.22.0, oban_pro 1.6.14, cachex 3.6.0, db_connection 2.7.0, absinthe
1.7.8) because `deps/` was not checked out — those claims are marked **[lib]**.
`priv/repo/structure.sql` is the July-2023 squashed baseline; schema claims were checked against the
121 migrations applied on top of it.

---

## 0. TL;DR — ranked bottlenecks

| # | Bottleneck | Where | Type | Impact |
|---|---|---|---|---|
| 1 | **Every message INSERT (in + out, and wa_messages) runs `UPDATE organizations SET last_communication_at`** in an AFTER INSERT trigger | `structure.sql:325-363` (`message_after_insert_callback`, still live), migration `20250520100142` | Per-org row lock | All concurrent message inserts of an org serialise on one row until each commits. Gets worse exactly when an org is busy. |
| 2 | **DB pool massively oversubscribed, no queue-time visibility, inbound job has no retry** | `config/runtime.exs:40` (20 conns), `config/config.exs:30-101` (~201 Oban slots/node), `message_worker.ex:12-14` (`max_attempts: 1`), `telemetry.ex:13-38` (no reporter), `runtime.exs:146` (`ecto_repos: []`) | SQL connection latency | Under load DBConnection drops checkouts after ~100 ms [lib]; a dropped checkout in `MessageWorker` permanently loses the flow processing for that message. Pool wait is not measured anywhere. |
| 3 | **Per-org concurrency cap of 10, `burst: false`, shared by replies, broadcasts and triggers** on both `gupshup_inbound` and `gupshup` | `config/config.exs:53-60, 94-101` | Queue latency | One org can run at most 10 inbound flow jobs and 10 sends cluster-wide. With multi-second jobs (4 s `Process.sleep`, sheets HTTP, long flows) the org's queue backs up; broadcasts at priority 0 sit in the same FIFO as conversational replies. |
| 4 | **Every outbound job is inserted as `scheduled`** (`scheduled_at: send_at` always passed) → waits for the Stager tick | `providers/gupshup/message.ex:324` | Queue latency | +0–1 s (≈0.5 s avg) on **every** reply. Snoozes add +1–2 s each. |
| 5 | **Flow-imposed spacing**: `send_at = now + max(context.delay, action.delay)`, `context.delay += 2s` after each send | `flows/contact_action.ex:22, 402, 424`; `flow_context.ex:318, 350` | Designed delay | 2nd message of a step +2 s, 3rd +4 s…; sub-flow resume +2 s. Largest *designed* latency. |
| 6 | **Write amplification: `updated_at` (and other changing columns) are indexed on `messages`, `contacts`, `flow_contexts`** → no UPDATE is ever HOT | `structure.sql:6303, 6394, 6835`; trigram GIN on `messages.body`/`flow_label` (`:6429, 6688`); new GIN trigram on `contacts.name` (`20261104100000`, 2 days old) | Write cost / WAL | Each contact update rewrites ~12 index entries (incl. a GIN) and each message update rewrites ~22 (incl. 2 GIN). Per round trip: contacts row updated 2–4×, flow_context row 3–7×, message rows 5× (insert + 4 updates). |
| 7 | **`Process.sleep(4000)` in default "wait for time"** and **synchronous Google Sheets write** inside the inbound job | `flows/action.ex:896-904`; `sheets.ex:560-593` | Blocks queue slot | Each holds one of the org's 10 inbound slots. |
| 8 | **Uncached `Contacts.get_contact_field_map` (3–6 queries) rebuilt on every variable parse** — incl. once per inbound webhook *for the org's own contact* | `contacts.ex:1164-1180`; callers below | Redundant reads | 2–4 rebuilds per inbound→reply (≈9–18 queries) even when text has no `@`. |
| 9 | **`flow_contexts` row UPDATEd once per node transition + per recent/results/wait change** | `flow_context.ex:412, 428, 503`; `wait.ex:120` | Redundant writes | 3 (new flow) to 7 (reply to wait node) non-HOT updates of the same row per inbound message. |
| 10 | **Locking maintenance on hot tables**: daily non-concurrent `REINDEX TABLE global.oban_jobs` (23:58 UTC); weekly `VACUUM FULL` on contacts, organizations, flow_results, oban_producers (Sat 21:00 UTC); hourly unbatched `DELETE FROM flow_contexts` (:02) | `erase.ex:142-147, 251-273`; `flow_context.ex:1073-1103` | Lock stalls | Blocks all job inserts/fetches (REINDEX) or every message insert (VACUUM FULL of contacts/organizations — the triggers write both). |
| 11 | **Org cache refill** (24 h TTL, never refreshed by `fetch`) runs ~25 queries + FunWithFlags writes while every caller for that org blocks in the Cachex courier | `partners.ex:589-672`, `caches.ex:63-82`, `misc/flags.ex:16-26` | Cache stall | Guaranteed at least daily per org per node; also on any org cache bust. |
| 12 | **Webhook does all work synchronously before replying 200** | `gupshup/controllers/message_controller.ex:28-35` | Request latency | DB slowness → slow webhook ACK → Gupshup retries → duplicate deliveries (deduped by unique index, but wasted work). |

Smaller but real: wasted session lookup in the message trigger (bug, §5.1), `CREATE EXTENSION IF NOT
EXISTS` per inserted row, ExAudit `versions` insert + transaction on every Ecto contact update,
per-subscriber Absinthe evaluation of ~6 publishes per message, contact row read 5× per send, status
callbacks doing UPDATE-then-SELECT, regex compiled per message, Hackney pool (50) shared with 120 s
LLM calls, info-level logging that can go synchronous under bursts.

---

## 1. End-to-end timeline

```
Gupshup POST /gupshup  ──►  [A] Endpoint plugs + Shunt (org resolution)           ~CPU, cache
                       ──►  [B] MessageController → Communications.Message.receive_message
                              contact upsert · session status · message INSERT (+triggers)
                              · preload · Absinthe publish · Oban.insert(MessageWorker)
                       ◄──  200 OK                                                (sync, in request)
[C] Oban gupshup_inbound pickup  (notify → Smart engine fetch, per-org limit 10)  queue latency
[D] MessageWorker.perform → ConsumerTagger → ConsumerFlow → FlowContext / Nodes / Actions
       └─ send_msg action ──► [E] Messages.create_and_send_message
                                 field map · INSERT message (+triggers) · preloads
                                 · Oban.insert(Gupshup.Worker, scheduled_at=send_at) · publish
       └─ update_recent / set_node / wait (flow_contexts UPDATEs)
[F] Stager tick (scheduled → available, ≤1 s) + send_at spacing (+2 s per extra message)
[G] Oban gupshup pickup (per-org limit 10) → Gupshup.Worker.perform
       org cache · ExRated (snooze +1–2 s if over bsp_limit) ──► HTTP to Gupshup (excluded)
[H] Post-response UPDATE messages + publish; later status callbacks (sync, in request)
```

Latency budget components, in order of typical magnitude:

| Component | Typical | Worst case |
|---|---|---|
| Flow-designed spacing (F) | 0 s for 1st message; +2 s per subsequent | grows linearly with messages per step |
| Stager wait for scheduled jobs (F) | ~0.5 s avg | 1 s per pass; +1–2 s per ExRated snooze |
| Inbound job pickup (C) | few ms (notify path) [lib] | unbounded when org's 10 slots busy; ~1 s if notifier unhealthy |
| Outbound job pickup (G) | few ms after staging | unbounded when org's 10 slots busy |
| Flow job DB work (D+E) | ~35–45 sequential statements (§4) | + pool wait (×N), + cache rebuilds, + 4 s sleep, + sheets HTTP |
| Webhook request DB work (B) | ~8 app statements + ~8 trigger statements | + org-row lock wait + pool wait |

---

## 2. Stage A — HTTP edge and org resolution (`lib/glific_web/endpoint.ex`, `router.ex:144-154`)

Per request (every inbound message **and** every status callback):

| Step | File:line | Cost |
|---|---|---|
| `Plug.RequestId`, `RemoteIp`, `Plug.Telemetry`, `RequestLogger` | endpoint.ex:62-68 | CPU; Phoenix info log line |
| `IPBlocklist` | plugs/ip_blocklist.ex | `persistent_term` memoised; cheap |
| `RateLimitPlug, :unrouted` | rate_limit_plug.ex:42-46 | `Phoenix.Router.route_info` lookup per request (CPU); matched → no ExRated |
| `Plug.Parsers` JSON | endpoint.ex:78-93 | JSON decode |
| `SubdomainPlug` → `Tenants.organization_handler` → `OrganizationIndex.fetch` | subdomain_plug.ex:27-33, tenants.ex:71-77, organization_index.ex:90-95 | `Cachex.get` of the **whole shortcode→id map** per request (copy O(#orgs)); no DB |
| `BSPWebhookIPFilter` | plugs/bsp_webhook_ip_filter.ex:68-127 | parses every allowlist CIDR string on every request (no memoisation, unlike `IPBlocklist`) — minor CPU |
| `Gupshup.Plugs.Shunt.build_context` → `Partners.organization(org_id)` + `put_current_user(root_user)` | shunt.ex:19-24, 77-82 | Cachex fetch + **copy of the full `%Organization{}`** (credentials, services, languages, root user…). On miss → §9.1 refill stall. No DB on hit. |

No DB queries in stage A when caches are warm. AppSignal ignores the `gupshup_webhooks` namespace
(shunt.ex:85, runtime.exs:139-150), so **this request path is not traced in APM**; only the
`Instrumentation.track_receive` counter exists.

---

## 3. Stage B — webhook handler: `Communications.Message.receive_message` (synchronous, before 200)

Call chain: `MessageController.text/2` (message_controller.ex:28-35) →
`Communications.Message.receive_message/2` (communications/message.ex:304-315) →
`do_receive_message` (:318-347) → `receive_text` (:350-355) → `handle_inbound_create_result` (:408-412)
→ `publish_data` (:494-503) → `process_message` (:536-541).

### 3.1 Query ledger — inbound text from an existing contact

| # | File:line | Statement | R/W | Txn | Notes |
|---|---|---|---|---|---|
| B1 | contacts.ex:1341-1355 (`fetch_whatsapp_contact`) | `SELECT c.*, i.id IS NOT NULL FROM contacts c LEFT JOIN contact_identities i … WHERE c.phone=? AND org=?` | R | – | unique `(phone, organization_id)` index. If the identity row is missing → `move_whatsapp_identity_to_phone`: BEGIN; `SELECT … FOR NO KEY UPDATE`; identity insert/update; COMMIT (contact_identities.ex:88-93) — rare after backfill. |
| (B1') | contacts.ex:675-683 | name/contact_type changed → `update_contact` → **BEGIN; UPDATE contacts; INSERT versions; COMMIT** (ExAudit) | W | yes | only when WhatsApp profile name changes. New contact instead: `insert_with_identity` = BEGIN; INSERT contacts; INSERT contact_identities; INSERT versions; COMMIT (contacts.ex:304-314). |
| – | contacts.ex:1136-1144 | `contact_blocked?` | – | – | in-memory (`Clients.plugins()` is a module attribute) |
| B2 | communications/message.ex:319 → contacts.ex:1116-1120 → 383-430 | `set_session_status(:session)` → if `bsp_status` changes: **BEGIN; UPDATE contacts; INSERT versions; UPDATE contact_identities; COMMIT** | W | yes | `bsp_status` is a WhatsApp identity field (contact_identity.ex:30-38) → `persist_update` takes the transactional branch. No-op (no query) when already `:session`/`:session_and_hsm`. Because the `contact_status` cron flips expired sessions back every minute (contacts.ex:1068-1100), this fires on **the first message of every conversation**. `has_permission?` is skipped for the root user (contacts.ex:203-205). |
| – | communications/message.ex:596-603 | `Partners.organization_contact_id` | – | – | Cachex copy of the org struct |
| B3–B5 | messages.ex:180-186 → **422-431** | `parse_message_vars` → `get_contact_field_map(attrs.receiver_id)` → `get_contact!` + preload `:language`, `:groups` (parallel, separate checkouts) | R ×3 | – | **Redundant and semantically wrong for inbound**: `receiver_id` is the **org's own contact**, so every inbound webhook loads the org contact + its groups and then substitutes `@contact.*` in the *beneficiary's* text with the org's values. Should be skipped for `flow: :inbound`. |
| B6 | messages.ex:188-193 | `INSERT INTO messages … RETURNING message_number, session_uuid, context_message_id` (`timeout: 45_000`) | W | implicit | fires both triggers (§5.1) → +~8 statements inside the same statement-transaction, incl. **UPDATE organizations** (per-org lock), **UPDATE contacts** (non-HOT), **UPDATE contact_identities**, wasted session SELECT, self-UPDATE of the new message. 22 indexes incl. 2 GIN trigram. FK checks take `FOR KEY SHARE` on contacts (sender, receiver = org contact), organizations. |
| B7 | communications/message.ex:496 | `Repo.preload([:context_message, :contact])` | R ×1–2 | – | **re-reads the contact row** already in hand from B1; `context_message` only when replying to a message |
| – | communications/message.ex:497-501 → communications.ex:38-52 | `Absinthe.Subscription.publish(:received_message)` (+ `:received_simulator_message` for simulator) | – | – | resolution runs in Absinthe proxy processes and consumes pool connections (§9.3) |
| B8 | communications/message.ex:536-541 → message_worker.ex:28-34 | `Oban.insert(MessageWorker)` → INSERT `global.oban_jobs` (`available`) + insert notification | W | – | 2 GIN indexes on oban_jobs (args, meta) |
| – | message_controller.ex:16-24 | `Instrumentation.track_receive` → `send_resp(200)` | – | – | AppSignal counter |

**Total for a returning contact, text message:** ~7 app statements (B1, B3–B5, B6, B7, B8) + ~8
trigger-side statements, +4 (transaction) when the session status flips. Media adds a transaction
with `messages_media` dedup SELECT + INSERT (communications/message.ex:361-378, messages.ex:876-893).
Location adds an INSERT into `locations`.

Variants: `receive_whatsapp_form_response` wraps form-response insert + message insert in a
transaction (:434-462). V3 (Meta-format) callbacks only carry statuses and form responses
(`v3/dispatcher.ex`), so inbound text always uses the V2 path above.

### 3.2 Stage-B observations

* **Everything is synchronous in the request.** Any pool wait or `organizations` row-lock wait in B6
  extends Gupshup's webhook response time. Gupshup retries at-least-once; duplicates are rejected by
  `messages_bsp_message_id_organization_id_index` and counted (`duplicate_inbound_message`), but
  only after B1–B5 have run again.
* The contact row is read twice (B1, B7) and written up to twice (B2 via Ecto, B6 via trigger) in
  the same request; the identity row is written up to twice (B2, B6 trigger).
* Logging: `Logger.info("Received message …")` plus two `"Publishing: …"` lines per message
  (communications/message.ex:305, communications.ex:40-42).

---

## 4. Stages C/D — inbound queue pickup and flow execution

### 4.1 Queue `gupshup_inbound` (config/config.exs:94-101)

* `local_limit: 30` per node, `global_limit: [allowed: 10, burst: false, partition: [args: :organization_id]]`.
  Engine `Oban.Pro.Engines.Smart` (config.exs:131), Postgres notifier (default), `stage_interval`
  default 1 s, `dispatch_cooldown` default 5 ms [lib].
* Pickup: insert notification → each node's producer debounces 5 ms → Smart-engine fetch transaction
  coordinates per-partition counts through `global.oban_producers` (UNLOGGED) and
  `SELECT … FOR UPDATE SKIP LOCKED` [lib]. Several queries per fetch, on the same 20-connection pool.
* **Per-org saturation is the main queue latency risk.** Throughput ≈ 10 / (avg job duration). A flow
  that sleeps 4 s, writes to Sheets, or chains sub-flows (the worker's own comment measures an
  11 s 4-flow chain, message_worker.ex:58-63) cuts an org to ~1–2 messages/s. `burst: false` means
  idle capacity is never borrowed.
* `max_attempts: 1` and `timeout: 1 min` (message_worker.ex:12-14, 66): a pool drop, a cache-fallback
  error, or a timeout loses that message's flow processing with no retry.
* Metric to check: `oban_job_latency` (queue_time) from Glific's own Oban telemetry handler
  (appsignal.ex:25-52, application.ex:107-128). AppSignal's built-in Oban instrumentation is off
  (`instrument_oban: false`, runtime.exs:148).

### 4.2 `MessageWorker.perform` preamble (message_worker.ex:40-64, 70-80)

| File:line | Work | DB |
|---|---|---|
| :44 | `Repo.put_process_state` → `Partners.organization` (copy) | cache |
| :45 | `Node.reset_node_map` | – |
| :47-48 | `Repo.get!(Message, id)` — **re-reads the row the webhook just inserted** | 1 R |
| :49, 55-59 | `load_state`: `Taggers.get_tag_maps` (**loaded, never used** — consumer_tagger.ex:20-33), `Flows.flow_keywords_map` (whole org keyword map copied from ETS), `Partners.organization(org).regx_flow` (org struct copied again) | cache ×3 |
| :75 | `Repo.preload([:location, :media, :whatsapp_form_response, contact: [:language]])` — `location` is `has_one` so **always queries**; `contact` + `language` re-read (third read of the contact for this message). Sibling preloads run in parallel tasks with separate checkouts | 3 R |

### 4.3 ConsumerFlow decision (consumer_flow.ex:33-125)

* `FlowContext.active_context` (flow_context.ex:860-898): `SELECT … FROM flow_contexts WHERE contact_id=?
  AND channel=? AND node_uuid IS NOT NULL AND completed_at IS NULL AND is_background_flow=false
  ORDER BY id DESC LIMIT 1`, then `Repo.preload([:contact, :flow])` (2 more, parallel) when a context
  exists — the contact is already loaded and the flow row is only used for `ignore_keywords`/`keywords`,
  which the cached flow has. Uses `flow_contexts_contact_id_index` + filter + sort; a partial index
  `(contact_id, id DESC) WHERE completed_at IS NULL` would make it a top-1 index read.
* No context and no keyword: `match_with_regex?` runs **`Regex.compile` of the org regex on every
  message** (consumer_flow.ex:305-314), then `Periodic.run_flows` re-reads `flow_keywords_map`
  (periodic.ex:41) and, per configured periodic flow, `Flows.flow_activated` does `Repo.all` of full
  flow_context rows just to test non-emptiness (flows.ex:608-620) — should be `exists?`.

### 4.4 Query ledger (a) — new keyword-triggered flow
Scenario: contact not in a flow sends a keyword; flow = `send_msg "Hello @contact.name"` → wait node
with timeout. Cache warm, no active profile.

| # | File:line | Statement | R/W |
|---|---|---|---|
| 1 | message_worker.ex:48 | SELECT messages by PK | R |
| 2-4 | message_worker.ex:75 | preload locations / contacts / languages | R×3 |
| 5 | flow_context.ex:889-891 | active_context SELECT (returns nil) | R |
| 6 | flow_context.ex:630-639 | `mark_flows_complete` `UPDATE flow_contexts … WHERE contact_id=? AND completed_at IS NULL …` (runs even when nothing matches) | W |
| 7 | contacts.ex:1395-1399 → 236-241 | `capture_history` → `get_contact!` (re-read contact) | R |
| 8 | contacts.ex:1415-1417 | INSERT contact_histories `contact_flow_ended_all` (+2 triggers: window DELETE over the contact's history, profile UPDATE) — **written even if 0 flows ended** | W |
| 9 | flow_context.ex:166-170 | INSERT flow_contexts (+trigger: UPDATE same row's profile_id) | W |
| 10-11 | flow_context.ex:743 | `seed_context` preload `[:flow, :contact]` — both were passed in as arguments | R×2 |
| 12 | flow_context.ex:428 | UPDATE flow_contexts results (`flow_keyword`) | W |
| 13-14 | flow_result.ex:79-84 | SELECT flow_results by flow_context_id, then INSERT (+trigger UPDATE) — should be one upsert | R+W |
| 15 | flow_context.ex:822 | INSERT contact_histories `contact_flow_started` (+2 triggers) | W |
| 16-18 | contact_action.ex:148 → contacts.ex:1164-1168 | `get_contact_field_map`: contact + language + groups | R×3 |
| → | contact_action.ex:408 | **handoff to `Messages.create_and_send_message`** (§5) | |
| 19 | flow_context.ex:412-413 | UPDATE flow_contexts `recent_outbound` | W |
| 20 | flow_context.ex:503 | UPDATE flow_contexts `node_uuid` (set_node on exit) | W |
| 21 | wait.ex:120-124 | UPDATE flow_contexts `wakeup_at` | W |

**≈21 statements (12 R / 9 W) + ≥6 trigger statements**, before the outbound send. Each extra
`send_msg` node adds ~5 (field map 3 + recent_outbound + set_node). Active profile adds 3 per field map.

### 4.5 Query ledger (b) — reply to a wait-for-response node
Scenario: router with `result_name`, → `set_contact_field` → `send_msg` → wait node.

| # | File:line | Statement | R/W |
|---|---|---|---|
| 1-4 | message_worker.ex:48, 75 | message + location + contact + language | R×4 |
| 5 | flow_context.ex:891 | active_context | R |
| 6-7 | flow_context.ex:892 | preload contact (**dup**) + flow (**unused, cached flow overwrites it**) | R×2 |
| 8 | consumer_flow.ex:188-190 → messages.ex:232 | `UPDATE messages SET flow_id` — non-HOT across 22 indexes, to set a value known when processing started | W |
| 9 | router.ex:238 → flow_context.ex:412 | UPDATE fc `recent_inbound` | W |
| 10 | flow_context.ex:428 | UPDATE fc `results` | W |
| 11-12 | flow_result.ex:80-82 | SELECT + UPDATE flow_results | R+W |
| 13 | exit.ex:106 → flow_context.ex:503 | UPDATE fc `node_uuid` | W |
| 14-16 | contact_field.ex:237 → contacts.ex:1164-1168 | field map (contact, language, groups) | R×3 |
| 17-18 | contacts.ex:383-430 | **BEGIN; UPDATE contacts (fields jsonb); INSERT versions; COMMIT** (ExAudit) | W×2 |
| 19 | contact_field.ex:292-302 | SELECT contacts_fields by shortcode (if label ≠ registered name: UPDATE contacts_fields + **org-wide `UPDATE contacts SET fields = jsonb_set(...)`**, contact_field.ex:336-457, inside the inbound job) | R |
| 20 | contact_field.ex:82-95 | INSERT contact_histories (+2 triggers) | W |
| 21 | exit.ex:106 | UPDATE fc `node_uuid` | W |
| 22-24 | contact_action.ex:148 | field map again (**dup of 14-16**) | R×3 |
| → | contact_action.ex:408 | **handoff to `Messages.create_and_send_message`** | |
| 25 | flow_context.ex:412 | UPDATE fc `recent_outbound` | W |
| 26 | exit.ex:106 | UPDATE fc `node_uuid` | W |
| 27 | wait.ex:120 | UPDATE fc `wakeup_at` | W |

**≈27 statements (14 R / 13 W) + one ExAudit transaction**: the same `flow_contexts` row is updated
**7×**, `contacts` read **4×**, `languages` 3×, field map built 2×.

### 4.6 In-process blockers inside the flow job

* `Process.sleep(4_000)` when a wait-for-time/result action has the default `wait_time == -1`
  (action.ex:896-904). Holds the org's inbound slot idle for 4 s.
* Google Sheets WRITE (`link_google_sheet`) does a synchronous HTTP append (sheets.ex:560-593), and
  may first fetch a Goth OAuth token. Webhooks, Dialogflow and GPT/Kaapi are **enqueued to Oban**
  (no inline HTTP, no transaction held across HTTP), but each adds INSERT webhook_logs + INSERT oban_jobs.
* EEx / safe-expression evaluation per `set_contact_field`, `set_run_result`, split-by-expression;
  each also does a `FunWithFlags.enabled?(:safe_expressions)` ETS read (glific.ex:275-377).
* `Regex.compile` per message for org regex and for every `has_pattern` case (case.ex:240-255).
* `Jason.decode` of the webhook body template on every execution (webhooks/request.ex:53-73).
* Flow cache: every `get_cached_flow` hit copies the whole flow term (raw `definition` + processed
  nodes + `uuid_map`) out of ETS into the job heap; the flow is stored once per keyword, uuid and id key
  (flows.ex:534-562).

---

## 5. Stage E — creating the outbound message (still inside the flow job)

Chain: `ContactAction.do_send_message` (contact_action.ex:374-410) → `Messages.create_and_send_message`
(messages.ex:281-293) → `check_for_hsm_message` (:342-353) → `do_send_message` (:357-377) →
`create_message` (:180-193) → `Communications.Message.send_message` (communications/message.ex:60-94)
→ `Gupshup.Message.send_text` → `create_oban_job` (providers/gupshup/message.ex:310-326) →
`publish_message` (communications/message.ex:120-129).

### 5.1 The two `messages` triggers (run on every INSERT, inbound and outbound)

**BEFORE INSERT `message_before_insert_callback`** (current body: migration
`20261028100100_mirror_last_message_at_to_whatsapp_identity.exs`):
1. `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"` — catalog lookup and a NOTICE sent to the client on **every row**.
2. `SELECT last_message_number, active_profile_id, phone FROM contacts WHERE org=? AND id=?`
   (read-then-write without `FOR UPDATE`: two concurrent messages for one contact can compute the same `message_number`).
3. Inbound with `context_id`: `SELECT id FROM messages WHERE bsp_message_id = ?` (index OK).
4. `UPDATE contacts SET last_communication_at, last_message_at, last_message_number, is_org_read,
   is_org_replied, is_contact_replied, updated_at` — changes 3 indexed columns → **non-HOT**, new
   entries in all ~12 contacts indexes, including the GIN trigram on `name` added in
   `20261104100000` (verify whether insert latency moved on 2026-11-04).
5. Inbound non-web: `UPDATE contact_identities SET last_message_at, updated_at`.

**AFTER INSERT `message_after_insert_callback`** (structure.sql:325-363, never redefined):
1. `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"` again.
2. **`UPDATE organizations SET last_communication_at = now WHERE id = NEW.organization_id`** — the
   per-org hot row. The row lock is held until the inserting transaction commits, so every message
   insert in the org (webhook B6, flow sends, broadcasts, triggers, WA groups via the
   `wa_message_after_insert_trigger`) queues behind the previous one. It also bloats `organizations`
   (which is presumably why it is `VACUUM FULL`ed weekly).
3. Inbound only: `SELECT session_limit FROM organizations`; `SELECT session_uuid FROM messages WHERE
   contact_id=? AND org=? AND flow='inbound' AND id<>NEW.id ORDER BY id DESC LIMIT 1`; then
   `UPDATE messages SET session_uuid = … WHERE id = NEW.id` (a second heap tuple per inbound message).
   **Bug:** `var_message_at` is declared but never assigned (structure.sql:332, 343), so `current_diff`
   is NULL, the "reuse session" branch is never taken, the `messages` SELECT is wasted, and every
   inbound message gets a fresh `session_uuid`.

Plus FK checks: 15 FKs on `messages`; every outbound insert in an org takes `FOR KEY SHARE` on the
same org-contact row (sender) and org row → MultiXact churn on already-hot rows.

### 5.2 Query ledger — one outbound text message from a flow

| # | File:line | Statement | R/W |
|---|---|---|---|
| (1-3) | contact_action.ex:148 | field map in the flow (counted in §4 ledgers) | R×3 |
| E1 | messages.ex:282 → contacts.ex:247-252 | `Contacts.get_contact` (contact read again) | R |
| E2-E4 | messages.ex:425 | `parse_message_vars` → **`get_contact_field_map` again** — re-parses a body the flow already parsed | R×3 |
| E5 | messages.ex:189-192 | INSERT messages (+ before/after triggers: contacts SELECT + UPDATE, organizations UPDATE, 2× CREATE EXTENSION, FK share locks) | W (+4) |
| E6-E7 | communications/message.ex:61 | `Repo.preload([:receiver, :sender, :media])` → contact again + **org contact** (only used for `sender.phone`, a per-org constant, gupshup/message.ex:253) | R×2 |
| – | communications.ex:14, 23; gupshup/message.ex:250 | `Partners.organization` ×3 (ETS copies) | cache |
| E8 | worker.ex:33-37 | `FunWithFlags.enabled?(:high_trigger_tps_enabled)` (ETS, 900 s TTL; DB on miss) | cache |
| E9 | gupshup/message.ex:324-325 | `Oban.insert` with `scheduled_at: message.send_at` → state **`scheduled`**; args carry the full message map **and** the JSON payload (body twice) into GIN-indexed `args` | W |
| E10 | communications/message.ex:496 | `publish_data` → `Repo.preload([:context_message, :contact])` → **5th read of the contact** | R |
| – | communications.ex:45-49 | `Absinthe.Subscription.publish(:sent_message)` | – |
| E11 | contact_action.ex:423 → flow_context.ex:412 | UPDATE fc `recent_outbound` (counted in §4 ledgers) | W |

**≈14 statements + 4 trigger statements per text message** (20 with an active profile). Templates read
the contact 6–7× and build the field map twice more (messages.ex:528-664). Each label on the action
adds another field map (contact_action.ex:342-350); each attachment another (contact_action.ex:270).

---

## 6. Stages F/G — outbound queue and worker up to the HTTP call

* **Every job is born `scheduled`.** `Oban.Job.new` sets `state: "scheduled"` whenever `scheduled_at`
  is given [lib], even when it equals now (gupshup/message.ex:324). It becomes `available` only on
  the next Stager tick (default 1 s, not overridden in config.exs:133-149) → **+0–1 s on every reply**,
  and no insert notification wakes producers.
* **Designed spacing:** first message `send_at = now`, then `+2 s`, `+4 s` … within one flow step
  (contact_action.ex:402, 424). Sub-flow resume adds 2 s (flow_context.ex:318, 350).
* **Queue `gupshup`** (config.exs:53-60): `local_limit: 20`, global 10 per org, `burst: false`.
  Flow replies, broadcasts (`BroadcastWorker` every minute per org, up to 100–300 contacts/min,
  broadcast.ex:318-339) and triggers all run at `priority: 0` in the same per-org FIFO → head-of-line
  blocking of conversational replies behind a campaign. `gupshup_high_tps` (plain 10/node) replaces it
  for orgs with the flag.
* **`Gupshup.Worker.perform`** (worker.ex:52-86): `Partners.organization` (copy; note
  `put_process_state` is not called), `ExRated.check_rate(shortcode, 1000, bsp_limit)` — node-local, so
  the effective cluster limit is nodes × `bsp_limit`; over the limit → `Process.sleep(50)` **while
  holding one of the org's 10 slots**, then `{:snooze, 1}` → back to `scheduled` → next Stager tick:
  **+1–2 s per snooze, repeatable** (bsp_worker.ex:68-75). If `bsp_limit` is nil the check never trips.
* `ApiClient.send_message` reads the API key from the cached org (no token HTTP on the V2 path), then
  Tesla → Hackney `:glific_default_pool` (**50 sockets shared** with OpenAI/Translate 120 s calls,
  Dialogflow, flow webhooks, GCS downloads — config.exs:153-158, application.ex:63-67). A pool checkout
  wait here is Glific-side latency that looks like Gupshup latency. `Tesla.Middleware.Logger` logs every
  call at info (api_client.ex:13).

---

## 7. Stage H — post-response and status callbacks (competing load)

* After HTTP: `handle_success_response` (communications/message.ex:136-151) Poison-encodes/decodes the
  job-arg map into a struct and `UPDATE messages SET bsp_message_id, bsp_status, status, flow, sent_at,
  updated_at` — non-HOT across 22 indexes (the unique `bsp_message_id` index and `updated_at` change);
  `flow` comes back as a string so Ecto always sees a change. Then publish `:update_message_status`.
* Each status callback (`sent`, `delivered`, `read`) runs synchronously in the webhook request
  (message_event_controller.ex:58-70 → communications/message.ex:210-236):
  `UPDATE messages SET bsp_status, updated_at WHERE bsp_message_id=? AND bsp_status<>?` (non-HOT,
  22 indexes) **then `Repo.fetch_by` of the same row** to publish it (could be `RETURNING`).
  `enqueued` normally matches 0 rows. No lifecycle ordering: a late `delivered` after `read` moves
  status backwards and costs another UPDATE + SELECT + publish. A `sent` that lands before the
  post-send UPDATE commits matches 0 rows and is lost.
* `failed` with 1002 → `number_does_not_exist` → ExAudit contact update; 471/1003 →
  `suspend_organization` (UPDATE organizations + cache refresh) + synchronous email in the request.
* **Per outbound message: the message row is written 5× (insert + 4 non-HOT updates), ~7 extra
  statements and ~4 subscription publishes come from callbacks alone.**

---

## 8. Totals for one inbound → one reply (text, warm caches, no profile)

| Stage | App statements | Trigger statements | Notes |
|---|---|---|---|
| B webhook | ~7 (+4 on session flip) | ~8 | sync in request |
| C/D flow job, reply-to-wait path | ~27 (+2 ExAudit) | ~4 | 7 updates of one fc row |
| E outbound create | ~11 (beyond those counted in D) | ~4 | contact read 5× |
| G worker + post-send | 1 + Oban job-table writes | – | message row update |
| H callbacks (sent/delivered/read) | ~7 | – | 3 more message row rewrites |
| **Total** | **≈55–60** | **≈16** | plus ~4 Oban job writes (insert, stage, fetch, ack, prune) per job ×2 jobs |

Row-level heat per round trip: `organizations` row updated **2×** (in + out), `contacts` row updated
**3–4×** (session flip, inbound trigger, field write, outbound trigger), `contact_identities` 2–3×,
`flow_contexts` row 7×, `messages` rows 1+1(session_uuid)+1(flow_id) for inbound and 1+4 for outbound.

---

## 9. Cross-cutting infrastructure

### 9.1 SQL connections and query overhead

* `Glific.Repo`: `pool_size` = `POOL_SIZE` default **20** (runtime.exs:40); `queue_target`/`queue_interval`
  not set → 50 ms / 1000 ms [lib]; query `timeout` 15 s default; `prepare: :named`;
  **`plan_cache_mode: force_custom_plan`** (runtime.exs:43-44) → Postgres re-plans *every* execution of
  every hot-path query (presumably deliberate against generic-plan regressions with skewed org sizes;
  costs planner CPU on each of the ~60 statements per round trip).
* `Glific.RepoReplica`: `READ_REPLICA_DATABASE_URL` **defaults to the primary URL** (runtime.exs:46) → if
  unset, a second 20-connection pool on the primary that carries Stats/BigQuery/GCS scans. The hot path
  uses only `Glific.Repo`.
* Competitors for the 20 primary connections per node: ~201 Oban slots (config.exs:30-101; sum of local
  limits), Oban producers/plugins/Smart-engine fetch transactions, every HTTP request (webhooks +
  GraphQL), Absinthe subscription resolution, Cachex fallbacks (org refill ~25 queries),
  OrganizationIndex refresh (60 s), telemetry poller GROUP BY over oban_jobs (60 s, appsignal.ex:144-213),
  Metrics flushers. Ecto parallel preloads (message_worker.ex:75, flow_context.ex:743/892,
  contacts.ex:1168) take 2–3 simultaneous checkouts per call site.
* When saturated, DBConnection drops queued checkouts after ~100 ms [lib] →
  `glific.repo.db_connection_error` counter (appsignal.ex:121-124, 241-266) — the **only** pool signal.
  `glific.repo.query.queue_time` is declared in `GlificWeb.Telemetry.metrics/0` (telemetry.ex:33-38) but
  no reporter is started, and AppSignal Ecto instrumentation is disabled (`ecto_repos: []`).
* `Repo.prepare_query` adds one `where organization_id = ?` and a soft-delete filter on organizations
  (repo_helpers.ex:378-414) — no extra queries, negligible.
* **ExAudit** (`use ExAudit.Repo`, repo.ex:10; tracked schemas config.exs:227-239 include `Contact` and
  `Flow`): every Ecto insert/update/delete of a Contact diffs the struct (CPU ∝ size of `fields` jsonb)
  and inserts into `versions` inside a transaction. Raw SQL / `update_all` (including the message
  triggers) are not audited.

### 9.2 Indexes and write amplification

* `messages`: ~22 indexes incl. **GIN trigram on `body`** (structure.sql:6688) and on `flow_label`
  (:6429), plus `updated_at` (:6835). Insert cost dominated by the body trigram GIN (pending-list flushes
  cause periodic spikes); every UPDATE is non-HOT.
* `contacts`: ~12 indexes incl. `updated_at` (:6303), `last_communication_at` (:6247), `last_message_at`
  (:6254) — all changed by the trigger — plus the new GIN trigram on `name` (migration 20261104100000).
* `flow_contexts`: ~12 indexes incl. `updated_at` (:6394) → each of the 3–7 per-message updates is non-HOT.
* `flow_contexts` and `flow_results` INSERT triggers immediately UPDATE the new row's `profile_id`
  (structure.sql:7234, 7241). `contact_histories` INSERT triggers run a window DELETE over the contact's
  history (:7185) — the `(contact_id, updated_at)` index that would support it was dropped in
  20230818012026, so each history insert sorts that contact's history.
* `global.oban_jobs`: GIN on `args` and `meta` (:6121, 6128); outbound job args embed the message map +
  payload (body twice). DynamicPruner deletes completed jobs after 5 minutes (config.exs:135) → constant
  insert/update/delete churn.
* No partitioning and no RLS anywhere; `messages` is one heap.

### 9.3 Live-update subscriptions

`Communications.publish_data` → `Absinthe.Subscription.publish` with topic = org id
(communications.ex:38-52). Per round trip: `received_message`, `sent_message`, `update_message_status`
×(post-send + sent + delivered + read) ≈ **6 publishes**, plus simulator duplicates.
`Schema.config_fun` returns only `topic` and sets no `context_id` (schema.ex:321-329), so Absinthe
evaluates the document **per subscribed socket** rather than once per org [lib]. Message fields
`contact/sender/receiver/media/tags/location/user/context_message/whatsapp_form_response` resolve via
`dataloader(Repo, use_parent: true)` and `send_by` preloads `[:flow_object, :user]`
(message_types.ex:44-123): anything the frontend selects that isn't preloaded on the published struct
costs a query **per open staff tab per publish**. This runs in Absinthe proxy processes, not on the
request/job process, but it draws from the same 20-connection pool. (The exact cost depends on the
frontend's subscription selection set — worth checking.)

### 9.4 Caches

* Cachex `:glific_cache` started with no options (application.ex:42-46): unbounded, no stats.
* `Caches.fetch` (caches.ex:63-82) does not refresh TTL → org (24 h), flows (24 h), keyword map (24 h)
  each rebuild at least daily per node. A miss runs the fallback through the Cachex courier: **all
  concurrent callers for that key block** until it finishes [lib].
* Org refill (`fill_cache`, partners.ex:589-631): root user, credentials, bsp/contact preloads, languages,
  ~20 flag reads, then `Flags.init` **writes** FunWithFlags rows and broadcasts cache busts
  (flags.ex:16-26, 491-529). During it, the webhook (Shunt), `MessageWorker`, `Gupshup.Worker` and
  `put_process_state` for that org all wait.
* Flow miss (flows.ex:545-565): full `definition` jsonb decode, `Flow.process`, plus one
  `SessionTemplate` query per templated action (templating.ex:71).
* `Caches.get` is 3 ops (`exists?`, `refresh` write, `get`) (caches.ex:45-55).
* Whole-struct ETS copies on every hit: org struct ~6× per outbound message and ~4× per inbound job;
  flow term per `get_cached_flow`; keyword map twice on the no-context path.
* FunWithFlags: ETS cache 900 s TTL, DB-backed (`global.fun_with_flags_toggles`). Flags written by
  `Flags.init` and the 5-minute out-of-office cron are evicted frequently. No clustering → other nodes
  see changes only at TTL.
* Everything (Cachex, OrganizationIndex, ExRated, PubSub) is **node-local**: there is no libcluster.

### 9.5 Maintenance and background load on the same DB

| When (UTC) | Job | Effect on hot path |
|---|---|---|
| daily 23:58 | `REINDEX TABLE global.oban_jobs` (erase.ex:142-147) — non-concurrent | blocks all job inserts (webhook B8, E9), fetches and acks for its duration |
| Sat 21:00 | `VACUUM (FULL, ANALYZE)` on contacts, organizations, flow_results, contacts_groups, contact_histories, oban_producers, … (erase.ex:251-273) | ACCESS EXCLUSIVE: every message insert blocks while `contacts` or `organizations` is rewritten (both written by the triggers); Smart-engine fetch blocks on `oban_producers` |
| hourly :02 | unbatched `DELETE FROM flow_contexts` older than 3 d / 14 d (flow_context.ex:1073-1103) | WAL/IO burst, index maintenance on ~12 indexes |
| every min | `contact_status`: bulk session-status flip with row locks on contacts + identities (contacts.ex:1068-1100) | contends with message-trigger updates of the same contacts; causes B2 transaction on next message |
| every min | `triggers_and_broadcast`, `wakeup_flows`, `gcs`; every 2 min `bigquery` | broadcast sends compete for the org's 10 `gupshup` slots; wakeup jobs N+1 (wakeup_worker.ex:31-42) |
| hourly :00 | Stats aggregates (replica — or primary if replica unset) | |
| Fri 21:00 / 21:30 | message purge (2M rows), versions purge (5M rows) | |

### 9.6 Logging and process overhead

Prod logs at `:info` (config/prod.exs:4): Phoenix request lines, "Received message", two
"Publishing: …" lines per message, Tesla middleware on every Gupshup call, "Loading organization cache",
flow seed/reset lines. The default `logger_std_h` handler switches to synchronous mode when its queue
exceeds 10 messages [lib], at which point every logging process blocks on stdout — a hidden burst
latency. No overload tuning is configured.

---

## 10. Redundancy catalogue (consolidated)

| # | Redundancy | Evidence | Fix direction |
|---|---|---|---|
| R1 | **Inbound `create_message` builds the field map for the org's own contact and substitutes `@contact` vars into beneficiary text** | messages.ex:422-431 called from receive path; `receiver_id` = org contact (communications/message.ex:600) | skip `parse_message_vars` for `flow: :inbound` (also a correctness fix) |
| R2 | Contact row read 2× in the webhook, ~4× in the flow job, 5× per outbound send | §3.1 B1/B7; §4.5 #3/#6/#14/#22; §5.2 E1/E2/E6/E10 | pass the loaded struct through; drop redundant preloads |
| R3 | `get_contact_field_map` (3–6 queries, uncached) rebuilt per variable parse: each send_msg, again in `create_message`, per label, per attachment, per set_contact_field, 2× per set_run_result, webhook body + headers | contacts.ex:1164-1180; contact_action.ex:148, 270, 346; messages.ex:425; action.ex:845, 850 | memoise per job (invalidate on contact write); skip when the string has no `@` |
| R4 | `flow_contexts` row updated per node + per recent/results/wait | flow_context.ex:412, 428, 503; wait.ex:120 | accumulate in struct, persist once per `step_forward`/`init_context` |
| R5 | flow_results get-then-write after a separate fc results UPDATE | flow_result.ex:79-84 | `INSERT … ON CONFLICT (flow_context_id) DO UPDATE` |
| R6 | `mark_flows_complete` reads contact + inserts history even when 0 rows changed | flow_context.ex:630-650 | skip when `update_all` returns 0 |
| R7 | flows row read from DB (active_context, seed_context preloads) although cached flow overwrites it | flow_context.ex:743, 892, 916 | don't preload `:flow` |
| R8 | `MessageWorker` re-reads the message just inserted and always queries `locations` | message_worker.ex:48, 75 | pass needed fields in args / preload location only for `type: :location` |
| R9 | `UPDATE messages SET flow_id` per continuing message (non-HOT, 22 indexes) | consumer_flow.ex:188-190 | fold into an existing write or drop the indexed column change |
| R10 | Message trigger: session SELECT always wasted (bug) + self-UPDATE + 2× `CREATE EXTENSION` per row | structure.sql:325-363; migration 20261028100100 | fix `var_message_at` or drop session logic; remove `CREATE EXTENSION` from triggers |
| R11 | `organizations.last_communication_at` updated per message | structure.sql:337; 20250520100142 | throttle (`WHERE last_communication_at < now() - interval '1 min'`) or move out of the trigger |
| R12 | Status callback: UPDATE then SELECT of the same row | communications/message.ex:228-234, 289 | `update_all(..., select: m)` / `RETURNING` |
| R13 | Post-send UPDATE writes unchanged `flow` (Poison round-trip string vs atom); `enqueued` callback repeats a 0-row UPDATE | communications/message.ex:137-147 | cast properly / drop the field |
| R14 | Org-contact row fetched on every send just for `sender.phone` | communications/message.ex:61; gupshup/message.ex:253 | read from the cached org |
| R15 | `Partners.organization` struct copied ~6× per outbound, ~4× per inbound job | worker.ex:53, api_client.ex:41, communications.ex:14/23, gupshup/message.ex:250, consumer_flow.ex:25 | fetch once per process; store lean projection |
| R16 | Tag maps loaded per job, unused | consumer_tagger.ex:20-33 | remove |
| R17 | `flow_keywords_map` read twice on no-context path; regex compiled per message | consumer_flow.ex:24, 305-314; periodic.ex:41; case.ex:240-255 | reuse state; precompile at cache build |
| R18 | Two `contact_histories` inserts per flow start, each firing 2 triggers incl. an unindexed window sort | flow_context.ex:642, 822; structure.sql:7185 | combine; restore `(contact_id, updated_at)` index |
| R19 | Oban job args duplicate body; jobs born `scheduled` | gupshup/message.ex:287-325 | pass `scheduled_at` only when in the future; slim args |
| R20 | ~6 subscription publishes per round trip, each resolved per subscriber | communications.ex:38-52; schema.ex:321-329 | set `context_id` per org/role so documents dedupe; preload what's selected |

---

## 11. What to measure in production to confirm

1. **Queue latency**: `oban_job_latency` for `gupshup_inbound` and `gupshup`, broken down by org
   (appsignal.ex:25-52). Expect ~0.5 s floor on `gupshup` from the Stager.
2. **Pool wait**: attach a handler to `[:glific, :repo, :query]` reporting `queue_time` to AppSignal
   (currently declared, never reported); watch `glific.repo.db_connection_error`.
3. **Hot-row locks**: `SELECT … FROM pg_stat_activity WHERE wait_event_type = 'Lock'` and
   `pg_locks` on `organizations` during a busy org's peak; `log_lock_waits = on` with
   `deadlock_timeout` ~100 ms.
4. **Write amplification**: `pg_stat_user_tables.n_tup_hot_upd / n_tup_upd` for messages, contacts,
   flow_contexts, organizations (expect ≈0 for the first three); `pg_stat_statements` top by total time
   (the trigger statements show up as separate entries with `track = all`).
5. **Contacts insert regression**: compare message-insert latency before/after the 2026-11-04 deploy of
   `contacts_name_trgm_index`.
6. **Org cache refills**: count of `"Loading organization cache"` log lines per org per day.
7. Confirm env: `POOL_SIZE`, `READ_REPLICA_DATABASE_URL`, `HACKNEY_POOL_SIZE`, node count; whether
   the `oban_notify` trigger still exists (`\d global.oban_jobs`).

---

## 12. Suggested order of fixes (cheap → structural)

Quick, low-risk:
1. Skip `parse_message_vars` for inbound messages (R1) — removes 3 queries from every webhook and fixes
   wrong substitution.
2. Pass `scheduled_at` only when `send_at` is in the future (R19) — removes the ~0.5 s Stager wait on the
   first reply of every step.
3. Throttle/remove the `organizations` UPDATE in `message_after_insert_callback`; remove `CREATE
   EXTENSION` from both triggers; fix or remove the dead session lookup (R10, R11).
4. Use `RETURNING` in status updates and add lifecycle ordering (R12).
5. Skip history + contact read in `mark_flows_complete` when nothing changed (R6); upsert flow_results (R5).
6. Report pool `queue_time`; set `queue_target` deliberately; give `MessageWorker` ≥2 attempts with
   idempotency on `message_id`.
7. Make maintenance non-blocking: `REINDEX … CONCURRENTLY`, replace `VACUUM FULL` on hot tables with
   plain `VACUUM`/`pg_repack`, batch the hourly flow_contexts delete.

Medium:
8. Memoise the contact field map per job (R3) and stop re-reading contact/flow rows (R2, R7, R8).
9. Batch flow_context writes to once per step (R4).
10. Separate conversational replies from broadcasts/triggers in Oban (own queue or higher priority) and
    revisit `burst: false` / per-org limit 10 for `gupshup_inbound`.
11. Replace the default-wait `Process.sleep(4000)` with a scheduled wakeup; move Sheets writes to Oban.
12. Dedicated Hackney pool for Gupshup sends.

Structural:
13. Drop or replace the `updated_at` btree indexes on `messages`/`contacts`/`flow_contexts` (or use a
    BRIN) so routine updates can be HOT; review whether the `messages.body` and `contacts.name` trigram
    GIN indexes justify their write cost (or set `fastupdate`/`gin_pending_list_limit` deliberately).
14. Set Absinthe `context_id` so subscription documents dedupe across sockets of an org.
15. Refresh org/flow caches proactively (warmers or TTL refresh on hit) instead of a daily blocking
    rebuild.

---

## Appendix — source research notes

Detailed per-area ledgers with more line references were produced during this audit (flow engine,
outbound path, infrastructure). Key file anchors:

* Inbound webhook: `lib/glific_web/providers/gupshup/plugs/shunt.ex`,
  `controllers/message_controller.ex`, `lib/glific/communications/message.ex:304-603`,
  `lib/glific/contacts.ex:293-430, 648-685, 1116-1144, 1164-1180, 1341-1375`, `lib/glific/messages.ex:180-236, 281-431`.
* Processor/flows: `lib/glific/processor/message_worker.ex`, `consumer_flow.ex`, `consumer_tagger.ex`,
  `lib/glific/flows/flow_context.ex`, `action.ex`, `contact_action.ex`, `contact_field.ex`, `router.ex`,
  `exit.ex`, `wait.ex`, `flow_result.ex`, `flows.ex:534-620, 934-951`.
* Outbound: `lib/glific/providers/gupshup/message.ex`, `worker.ex`, `api_client.ex`,
  `lib/glific/providers/bsp_worker.ex`, `communications/message.ex:60-299`,
  `glific_web/providers/gupshup/controllers/message_event_controller.ex`.
* Infra: `config/config.exs:15-243`, `config/runtime.exs:35-60, 139-150`, `lib/glific/application.ex`,
  `lib/glific/repo.ex`, `repo_helpers.ex:335-450`, `caches.ex`, `partners.ex:589-672`,
  `partners/organization_index.ex`, `erase.ex:94-301`, `priv/repo/structure.sql:302-366, 6121-6842, 7150-7248`,
  migrations `20261028100100`, `20250520100142`, `20261104100000`, `20251016171923`.
