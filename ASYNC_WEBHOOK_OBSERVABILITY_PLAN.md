# Async Webhook Observability — Implementation Plan

> Scope (this phase): observability for **three async Kaapi webhooks only** —
> `speech_to_text`, `text_to_speech`, `unified-llm-call`. No flow-behaviour
> change. Follows the *as-built* sync pattern on `webhook/observability`
> (single `Glific.Flows.Webhook.SystemError`, reported via
> `with_failure_reporting` → `Appsignal.send_error/3` with `flow_webhooks`
> namespace + `Span.set_sample_data` tags).

## The three failure surfaces

An async webhook has two network hops, so failures land in two layers:

```
 Glific ──(A) outbound dispatch──▶ Kaapi      (kicks off the async job)
 Glific ◀──(B) callback POST──────  Kaapi      (delivers the result, /webhook/flow_resume)
```

The flow goes into a **1-minute wait** after hop A. If hop B doesn't arrive in
time, the minute cron wakes the flow and it moves on.

### What the user asked to cover

1. **Kaapi HTTP error codes (4xx / 5xx)** on the outbound dispatch.
2. **HTTP 200 but a logical failure in the body**, e.g.
   `{"success": false, "message": "Unexpected error occurred"}`.
3. **Late callbacks** — a callback that arrives *after* the 1-minute timeout.
   The flow has already moved on; we still want the response data recorded and
   the lateness marked, for future analysis.

## Current behaviour (what's broken / missing)

| Path | Code today | Gap |
|---|---|---|
| Outbound transport error (timeout/nxdomain) | `parse_kaapi_response` (`api_client.ex:343`) just returns `{:error, atom}` + a metric — **no AppSignal**. `Kaapi.handle_kaapi_error/4`'s `{:error, reason}` clause (`kaapi.ex:415`) is the only place that calls `Glific.log_exception` | reported, but via `Kaapi.Error` not `Webhook.SystemError` → needs consolidating + de-duping |
| Outbound HTTP 4xx/5xx | `parse_kaapi_response` → `{:error, %{status, body}}` (metric only, no AppSignal); STT/TTS `handle_kaapi_error` 4xx/5xx clauses (`kaapi.ex:402,407`) build `%{success: false, error_type}` with **no `log_exception`**; `unified-llm-call` `do_unified_llm_call` → `%{success: false, reason}` | **raw HTTP status is dropped** and **nothing is reported to AppSignal** |
| Outbound HTTP 200 + `success:false` body | `parse_kaapi_response` 2xx clause returns `{:ok, body}` unconditionally; callers do `Map.merge(%{success: true}, body)` | **silently treated as success** — flow waits for a callback that will never come |
| Callback with `success:false` | `flow_resume_with_results` maps it to a Failure message | not reported to AppSignal |
| Late callback | `update_log` still writes `response_json`; `resume_contact_flow` is effectively a no-op | no marker that the callback was late — not queryable |

Note the `Map.merge(%{success: true}, body)` bug: `body` has the **string** key
`"success"`, the merge adds the **atom** `:success`, so the result carries both
`success: true` (atom) and `"success" => false` (string). Downstream pattern
matches the atom → failure is masked.

## Failure → record mapping

The classification we will record on every async call:

| Kaapi response | Layer | `http_status` tag | `error_type` | webhook_log `status_code` | AppSignal `SystemError`? |
|---|---|---|---|---|---|
| Transport error (timeout, nxdomain, refused) | outbound | `nil` | `timeout` / `transport_error` | 400 | **yes** |
| HTTP 400–499 | outbound | 4xx | `invalid_request` (or Kaapi-specific) | 4xx | **yes** |
| HTTP 500–599 | outbound | 5xx | `service_unavailable` | 5xx | **yes** |
| HTTP 2xx, body `success:false` | outbound | 200 | `kaapi_logical_failure` | 200 (+ `error` set) | **yes** |
| HTTP 2xx, body OK | outbound | 200 | — | `nil` (await callback) | no |
| Callback `success:false` | callback | from body | from `error_type` in body | per body | **yes** |
| Callback `success:true`, on time | callback | — | — | 200 | no |
| Callback arrives **late** (after timeout) | callback | — | `late_callback` | per body, **+ `timed_out_at` set** | no — metric + warning log only |

Rationale: hops A and B are real failures the team must fix → loud
`SystemError`. A late callback is *not* a failure (Kaapi answered, just slowly)
→ tracked quietly as data, not alerted.

## Design

### 1. Surface the HTTP status (concern 1)

- `Glific.ThirdParty.Kaapi.handle_kaapi_error/4` — add `http_status: status` to
  the failure maps for the `%{status: status, body: body}` clauses (4xx, 5xx,
  and the catch-all). Transport-error clause keeps `http_status: nil`.
- `Glific.Clients.CommonWebhook.do_unified_llm_call/4` — the
  `{:error, %{status: status, body: body}}` branch must include
  `http_status: status` (currently discarded).

### 2. Detect HTTP 200 + logical failure (concern 2)

Do **not** change `ApiClient.parse_kaapi_response` — it's shared by many
non-webhook endpoints (assistants, configs); flipping 2xx→error globally is
risky. Instead add a **scoped, local** body check.

Add a helper (in `CommonWebhook`, alongside `with_failure_reporting`):

```elixir
# A 2xx body that explicitly says success:false is a logical failure.
defp normalize_kaapi_body(body) when is_map(body) do
  case body do
    %{"success" => false} -> {:failure, body["message"] || body["error"] || "Kaapi logical failure"}
    %{success: false}     -> {:failure, body[:message] || body[:error] || "Kaapi logical failure"}
    _                     -> {:ok, body}
  end
end
```

Apply it right after `{:ok, body} <- ApiClient.call_llm(...)`:
- in `CommonWebhook.do_unified_llm_call/4`
- in `Glific.ThirdParty.Kaapi.speech_to_text/5` and `text_to_speech/5`

On `{:failure, reason}` return a proper
`%{success: false, http_status: 200, error_type: "kaapi_logical_failure", reason: reason}`
**instead of** `Map.merge(%{success: true}, body)` — this also fixes the
atom/string key-collision bug.

### 3. Report failures to AppSignal (concerns 1 & 2)

Reuse the as-built sync mechanism. Extend `CommonWebhook.with_failure_reporting`
to wrap the three async `webhook/3` clauses: `"speech_to_text"`,
`"text_to_speech"`, `"unified-llm-call"`. Any `%{success: false, ...}` they
return is reported as `SystemError` in the `flow_webhooks` namespace.

Because the wrapper has `fields` in scope, enrich the AppSignal tags:
`organization_id`, `flow_id`, `contact_id`, `webhook_name`, `webhook_log_id`,
`http_status`, `error_type`, `reason`, and `failure_layer: "outbound"`.

`extract_status_and_reason/1` already reads `%{http_status: s}`; extend it to
also pick up `error_type`.

`SttTtsWorker` needs **no new reporting code** — it dispatches STT/TTS through
`CommonWebhook.webhook/3`, so the wrapper covers it. Its existing
`Logger.warning` stays.

### 4. Report callback failures (concern 2, layer B)

In `FlowResumeController.flow_resume_with_results/2`, when
`result["success"] == false`, call the shared reporter with
`failure_layer: "callback"`, `error_type` and `reason` from the callback body.
This is in addition to the existing Failure-message flow behaviour (unchanged).

### 5. Late-callback tracking (concern 3)

**Migration** — add a nullable column to `webhook_logs`:

```
timed_out_at :utc_datetime   # non-null ⇒ the callback arrived after the
                              # flow's wait window had elapsed
```

Update `WebhookLog` `@optional_fields` and `@type t()` (changeset already casts
`@optional_fields`).

**Detection at callback time** — in `flow_resume_with_results/2`. This is a
label-only check, **not** a wait: it adds no latency and no extra DB query.
`Webhook.update_log/2` already does `Repo.get!(WebhookLog, id)` when passed an
integer id, so the fetch is reused, not added.

1. Fetch the `WebhookLog` **once** by `response["webhook_log_id"]` (skip if nil)
   — a primary-key lookup, sub-millisecond.
2. `timeout = Application.get_env(:glific, :async_webhook_timeout, 60)` (seconds).
3. `deadline = DateTime.add(webhook_log.inserted_at, timeout)`.
4. `late? = DateTime.compare(DateTime.utc_now(), deadline) == :gt` — an in-memory
   timestamp comparison (microseconds).
5. Call the **struct** form `update_log(webhook_log, message)` so the log is not
   fetched a second time; `response_json` is persisted as today.
6. If `late?`:
   - Set `timed_out_at = deadline` on the log (makes late callbacks queryable:
     `WHERE timed_out_at IS NOT NULL`).
   - `Glific.log_error/2` a warning with `send_appsignal?: false`.
   - `Glific.Metrics.increment("Kaapi Late Callback", organization_id)`.
   - Do **not** raise a `SystemError` (not a failure).
7. If on time → existing path unchanged.

The `60` is the threshold compared against, not a delay introduced anywhere.
On-time callbacks fall straight through; late callbacks belong to a flow that
has already moved on, so there is nothing to delay either way.

No new cron job and no sweep is needed for this phase — lateness is computed
when the callback arrives. (A sweep to mark callbacks that *never* arrive is
noted as a future extension below, not in scope.)

### 6. Config

Add `:async_webhook_timeout` to `config/runtime.exs`, default `60` (seconds),
so the timeout is tunable without a deploy.

### 7. Shared reporter

Promote the currently-private `report_webhook_failure/4` to a public
`report_system_error/1` taking a context map, so both `CommonWebhook` (outbound)
and `FlowResumeController` (callback) emit identical `SystemError` payloads
through one code path / one namespace / one tag schema.

## Implementation sequence

1. Migration: `webhook_logs.timed_out_at`; update `WebhookLog` schema.
2. Add `:async_webhook_timeout` to `config/runtime.exs` (default 60).
3. Promote `report_webhook_failure` → public `report_system_error/1` (context map).
4. `Kaapi.handle_kaapi_error/4` — add `http_status` to failure maps.
5. `CommonWebhook.do_unified_llm_call/4` — keep `http_status` on the
   `{:error, %{status, body}}` branch.
6. Add `normalize_kaapi_body/1`; apply in `do_unified_llm_call/4`,
   `Kaapi.speech_to_text/5`, `Kaapi.text_to_speech/5`; replace the buggy
   `Map.merge(%{success: true}, body)` with explicit success/failure maps.
7. Extend `with_failure_reporting` to wrap the `"speech_to_text"`,
   `"text_to_speech"`, `"unified-llm-call"` clauses; enrich tags from `fields`;
   extend `extract_status_and_reason/1` for `error_type`.
8. `flow_resume_with_results/2` — report `success:false` callbacks via
   `report_system_error/1` (`failure_layer: "callback"`).
9. `flow_resume_with_results/2` — late-callback detection: set `timed_out_at`,
   warning log (`send_appsignal?: false`), `Kaapi Late Callback` metric.
10. Tests (below). Run `mix check` + `mix test_full`.
11. One line in `CLAUDE.md` error-handling section.

## Edge cases to handle during implementation

1. **Wait window is fixed at 60s — not a concern.** All three webhooks are
   `call_webhook` actions; `Action.process/3`'s `call_webhook` clause
   (`action.ex:327`) never sets `wait_time`, and the schema field has no default,
   so `action.wait_time` is always `nil` → `action.wait_time || 60` is always 60.
   Only `wait_for_time` / `wait_for_result` node types carry a custom `wait_time`,
   and those don't drive the webhook wait. So the flat `:async_webhook_timeout`
   (default 60) is *exact*, no per-node deadline needs to be persisted.
   *One cleanup:* the `60` literal lives in both `webhook.ex`
   (`action.wait_time || 60`) and the new config — point `update_context_for_wait`
   at `:async_webhook_timeout` too, so late-detection and the real wait window
   share a single source of truth and can't drift.
2. **`Map.merge(%{success: true}, body)` key collision** — atom `:success` vs
   string `"success"`. Step 6 must return a clean map, not merge.
3. **`SttTtsWorker` retries** — the worker has `max_attempts: 2`; a failed STT/TTS
   job retries, so the webhook fires (and reports) **twice**. Decide: report only
   on the final attempt (`job.attempt == job.max_attempts`), or accept duplicates.
   `unified-llm-call` is **not** affected — it runs inline in the flow process,
   not via an Oban worker, so no retry.
4. **Double reporting on transport errors** — `Kaapi.handle_kaapi_error/4`'s
   `{:error, reason}` fallback already calls `Glific.log_exception`. With the new
   wrapper this becomes a second report. Consolidate to one (drop the
   `log_exception` there, or skip wrapper-level reporting for that shape).
5. **Late callback rejected by `validate_request`** — `validate_request/2` returns
   `false` for callbacks whose signed timestamp is older than 15 min, which makes
   the `with true <- validate_request(...)` clause skip `resume_contact_flow`.
   `update_log` runs *before* that clause, so response data is saved regardless.
   The `timed_out_at` marking, the warning log and the metric must therefore be
   placed **before** the validation clause (next to `update_log`) — if placed
   after it, late-callback tracking would only cover 1–15 min-late callbacks and
   miss anything later. Placed before, it covers any delay.
6. **`webhook_log_id` missing in callback** — `parse_callback_response/1` fallback
   returns `%{}`; `response["webhook_log_id"]` is `nil`. Guard every log
   lookup/update.
7. **Slow outbound ack vs the 1-min wait** — `call_llm` has `recv_timeout: 60_000`;
   if the outbound dispatch itself takes ~60s, the flow's 60s wait can expire
   before the ack returns. The ack failure should still be reported; the flow has
   already moved on (no-op resume).
8. **`status_code` semantics for a late *failure* callback** — `update_log` writes
   400 for an error string; a late-but-valid failure callback would look like a
   400. `timed_out_at` + `error_type` disambiguate it from a real HTTP 400.
9. **Don't resume an already-moved-on flow** — for late callbacks, keep current
   behaviour (resume is a no-op once the context has progressed). Do not add a
   resume that could double-run a flow. This preserves "no flow-behaviour change".
10. **`normalize_kaapi_body/1` false positives** — only treat an *explicit*
    `success: false` as failure; a 2xx body without that key is success. Confirm
    the shape of a *successful* async ack from Kaapi so the check can't misfire.
11. **Reporting volume** — "error for all" means every failure emits a
    `SystemError`. One misconfigured org can flood the `flow_webhooks` AppSignal
    trigger. If observed, wrap `report_system_error/1` in
    `ExRated.check_rate` (already used in `SttTtsWorker`). Defer until seen.

## Testing plan

**`test/glific/flows/webhook_test.exs`** / **`common_webhook_test.exs`**
- `unified-llm-call` outbound HTTP 400 → `SystemError`, tag `http_status: 400`.
- `unified-llm-call` outbound HTTP 500 → `SystemError`, `http_status: 500`.
- `unified-llm-call` outbound transport error → `SystemError`, `http_status: nil`.
- `unified-llm-call` HTTP **200 with `{"success": false, "message": ...}`** →
  `SystemError`, `error_type: "kaapi_logical_failure"`, flow gets Failure (not a
  hung wait).
- `speech_to_text` / `text_to_speech` 4xx, 5xx, 200-logical-failure → same.
- Successful outbound → no `Appsignal.send_error` call.

**`test/glific/third_party/kaapi/stt_tts_worker_test.exs`**
- STT failure tags carry `flow_id` / `contact_id`.
- Retry does not double-report (whichever policy step 3 picks).

**`test/glific_web/flows/flow_resume_controller_test.exs`**
- Callback `success:false` → `SystemError` with `failure_layer: "callback"`.
- On-time callback (`now - inserted_at < 60s`) → `timed_out_at` stays nil,
  no warning, no `Kaapi Late Callback` metric.
- Late callback (`inserted_at` 90s ago) → `response_json` saved, `timed_out_at`
  set, warning logged with `send_appsignal?: false`, metric incremented,
  `Appsignal.send_error` NOT called.
- Late callback with nil `webhook_log_id` → no crash.
- Custom `:async_webhook_timeout` (e.g. 120s) honoured.

Mock AppSignal via `Mock` on `Appsignal.send_error/2,3`; HTTP via `Tesla.Mock`
(transport errors = `{:error, atom}` from the mock).

## Out of scope (future extensions)

- A minute-cron sweep to mark callbacks that **never** arrive
  (`status_code IS NULL` long after the deadline).
- `call_and_wait`, `unified-voice-llm-call`, and the non-Kaapi sync webhooks.
- AppSignal trigger dedup / rate-limit tuning (handled in AppSignal config,
  see the `flow_webhooks` Error-rate Trigger).
