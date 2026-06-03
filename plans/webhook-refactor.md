# Plan: Behaviour-preserving refactor of flow webhook nodes

## Context

Today's flow-webhook subsystem has two problems that compound:

1. **Error tracking is duplicated and scattered.** `with_failure_reporting/3` is defined in two modules — `Glific.Flows.Webhook` (webhook.ex:711-723, 1 callsite) and `Glific.Clients.CommonWebhook` (common_webhook.ex:840-848, 9 callsites). Failure reporting also fires from `flow_resume_controller.maybe_report_callback_failure/2` (callback time) and `FlowContext.maybe_report_timeout/2` (timeout). Adding a new webhook means remembering all of these.
2. **Dispatch is spread across four layers and several patterns.** `Action.execute/3` pattern-matches `action.url` for four FUNCTION URLs; `Webhook.execute/2` switches on method; `Webhook.perform/1` (Oban worker) switches on method again; `Glific.Clients.webhook/3` falls through to org-specific clients. Sync vs async webhooks have no common shape — readers can't tell from a glance which calls park the flow and which return immediately.

We will land **a single `@behaviour` per webhook, one file per webhook, with shared `Sync` / `Async` macros, dispatched through one entry point that owns error tracking and latency tracking**. This is **behaviour-preserving**: every AppSignal report, every WebhookLog row, every flow wakeup must look identical post-refactor. The safety net is a parameterized E2E contract test landed *before* any production-code refactor.

## User-confirmed scope choices

- **All FUNCTION webhooks migrate**, plus generic POST/GET HTTP webhooks (as a single `GenericHttp` implementation). Org-specific client modules (Sol, Avanti, Tap, ~20 of them) stay untouched as a fallback extension point.
- **Incremental migration, one webhook per PR.** Behaviour + dispatcher land dormant; each webhook is then migrated separately. Old and new paths coexist until the final delete PR.
- **Modules live at `lib/glific/flows/webhooks/`.** Namespace: `Glific.Flows.Webhooks.*`.
- **Latency telemetry is ungated.** New `flow_webhook_latency` distribution emitted by the central wrapper. Existing `kaapi_llm_latency` at flow_resume_controller.ex:300 stays untouched.

## Invariants that must NOT change

1. Every existing AppSignal report (`SystemError`, `TimeoutError`) keeps its exact `message` and tag map (`organization_id`, `webhook_name`, `flow_id`, `contact_id`, `webhook_log_id`, `http_status`, `reason`, `error_type`). AppSignal groups on exception module + message — both stay byte-identical.
2. Every `WebhookLog` row is created and updated exactly once per logical webhook, with the same columns set as today.
3. Flow JSON URL strings (`speech_to_text`, `voice-filesearch-gpt`, etc.) are frozen — they're persisted in flow definitions in production DBs.
4. Kaapi callback wire format unchanged.
5. Three reporting *phases* remain distinct facets and may all fire for one logical failure: execution-time, callback-time, timeout. We do not dedupe across phases.

## A. Module layout

```
lib/glific/flows/webhooks/
  core/
    behaviour.ex          # Glific.Flows.Webhooks.Behaviour
    dispatcher.ex         # Glific.Flows.Webhooks.Dispatcher — dispatch + ResultTranslator wire encoding
    registry.ex           # Glific.Flows.Webhooks.Registry
    instrumentation.ex    # Glific.Flows.Webhooks.Instrumentation
    errors.ex             # Glific.Flows.Webhooks.Errors
    result_translator.ex       # Glific.Flows.Webhooks.ResultTranslator — TEMPORARY; remove after handle/3 refactor
    sync.ex               # Glific.Flows.Webhooks.Sync
    async.ex              # Glific.Flows.Webhooks.Async
  implementations/
    geolocation.ex        # first migrated sync webhook
    geolocation/
      address.ex          # Glific.Flows.Webhooks.Geolocation.Address — typed success result
  callback.ex             # (planned) parse/upload/resume helpers moved from controller
  generic_http.ex         # (planned) GenericHttp + GenericHttp.Worker

  # one file per FUNCTION webhook (remaining, not yet migrated):
  speech_to_text.ex          # async
  text_to_speech.ex          # async
  unified_llm.ex             # async — handles "filesearch-gpt" + "unified-llm-call"
  unified_voice_llm.ex       # async — overrides handle_resume/2 for voice_post_process
  parse_via_chat_gpt.ex      # sync
  parse_via_gpt_vision.ex    # sync
  speech_to_text_with_bhasini.ex   # sync
  text_to_speech_with_bhasini.ex   # sync
  nmt_tts_with_bhasini.ex          # sync
  detect_language.ex               # sync
  get_buttons.ex                   # sync
  check_response.ex                # sync
  send_wa_group_poll.ex            # sync
  create_certificate.ex            # sync
```

`Glific.Flows.Webhook` (the existing module) is retained as a thin facade through the migration: keeps `report_to_appsignal/2`, `update_log/2`, `create_log/4`, and the Oban worker until the GenericHttp step. Its three exception submodules (`Error`, `SystemError`, `TimeoutError`) become aliases re-exported from `Glific.Flows.Webhooks.Errors`.

## B. The `@behaviour` contract

`lib/glific/flows/webhooks/behaviour.ex`:

```elixir
@type ctx :: %{
        organization_id: non_neg_integer(),
        flow_id: non_neg_integer() | nil,
        contact_id: non_neg_integer() | nil,
        flow_context_id: non_neg_integer() | nil,
        wa_group_id: non_neg_integer() | nil,
        webhook_log_id: non_neg_integer(),
        action: Glific.Flows.Action.t(),
        flow_context: Glific.Flows.FlowContext.t()
      }

@type sync_result  :: map() | nil | String.t()
                    | {:ok, term()} | {:error, String.t()}   # migrated webhooks (encoded by Dispatcher)
@type async_result :: {:wait, FlowContext.t(), [Message.t()]}
                    | {:ok,   FlowContext.t(), [Message.t()]}   # immediate-failure path

@callback name() :: String.t()                       # matches flow JSON URL
@callback mode() :: :sync | :async
@callback call(fields :: map(), ctx :: ctx())
          :: sync_result | async_result

# Optional callbacks (async only)
@callback handle_resume(callback :: map(), ctx :: ctx()) :: {:ok | :error, map()}
@callback wait_time_default() :: pos_integer()
@optional_callbacks handle_resume: 2, wait_time_default: 0
```

Decisions:

- **Wire format (today):** `Glific.Flows.Webhook.handle/3` still treats any map as Success and bare strings as Failure. Until that is refactored, `Dispatcher` applies `ResultTranslator.to_legacy_structure/2` after `call/2` for migrated webhooks: `{:ok, value}` → results map (`success: true` + payload), `{:error, msg}` → string. Legacy webhooks that still return maps pass through unchanged.
- **Internal format (migrated sync webhooks):** `call/2` returns `{:ok, typed_value}` or `{:error, String.t()}`. Geolocation uses `Geolocation.Address` instead of a generic map. Register per-module encoders in `ResultTranslator.encoder_for/1`.
- Sync `call/2` may still return `map() | nil` on unmigrated webhooks. `%{success: false, ...}` maps remain visible to `Instrumentation` until those webhooks adopt tuple results + dispatcher encoding (or until `handle/3` is fixed).
- Async `call/2` returns `{:wait, ctx, []}` (preserves today's `update_context_for_wait/2` shape) or `{:ok, ctx, [failure_msg]}` for immediate-failure branches (Kaapi creds missing, body decode error).
- `handle_resume/2` is the per-webhook callback hook. The `Async` macro injects a default that mirrors today's `flow_resume_controller.do_flow_resume`. Only `unified-voice-llm-call` overrides it to run `voice_post_process`.
- `headers` deliberately not in the signature — they're inside `fields` for FUNCTION webhooks and built by Dispatcher for HTTP.

## C. Shared macros

`Glific.Flows.Webhooks.Sync` — sketch:

```elixir
defmacro __using__(opts) do
  webhook_name = Keyword.fetch!(opts, :name)
  quote do
    @behaviour Glific.Flows.Webhooks.Behaviour
    @webhook_name unquote(webhook_name)
    @impl true
    def name, do: @webhook_name
    @impl true
    def mode, do: :sync
    # Author writes only call/2. Dispatcher adds instrumentation + ResultTranslator
    # wire encoding; unit tests of call/2 assert {:ok, _} / {:error, _} tuples.
  end
end
```

`Glific.Flows.Webhooks.Async` mirrors `Sync`, plus:

```elixir
def mode, do: :async
def handle_resume(callback, ctx),
  do: Glific.Flows.Webhooks.Callback.default_handle_resume(callback, ctx)
defoverridable handle_resume: 2
def wait_time_default, do: 60
defoverridable wait_time_default: 0
```

Macros explicitly do **not** inject `with_failure_reporting` — that's the Dispatcher's job. Per-webhook modules contain only integration code (call Tesla, call Kaapi, build payload). All cross-cutting concerns (logging, AppSignal, latency, log-row creation, wait state) live in `Dispatcher` + `Instrumentation`.

## D. Centralized instrumentation

`Glific.Flows.Webhooks.Dispatcher.dispatch/2` is the single funnel:

```elixir
def dispatch_named(name, fields, headers) do
  module = Registry.lookup!(name)
  ctx    = build_ctx(fields, headers)
  Instrumentation.around(module, ctx, fn ->
    module.call(fields, ctx)
    |> ResultTranslator.to_legacy_structure(module)   # TEMPORARY — remove when handle/3 routes on success field
  end)
end
```

`ResultTranslator` is the only place that converts `{:error, msg}` → string for flow Failure routing. Webhook modules must not call it directly.

`Instrumentation.around/3` — the only home of failure reporting + latency:

```elixir
def around(module, ctx, fun) do
  start = System.monotonic_time()
  result = fun.()
  emit_latency(module, ctx, start, :ok)
  maybe_report_webhook_failure(result, module.name(), ctx)
  result
rescue
  exception ->
    emit_latency(module, ctx, start, :error)
    report_webhook_failure(module.name(), ctx, nil, Exception.message(exception))
    reraise exception, __STACKTRACE__
end
```

`maybe_report_webhook_failure/3`, `extract_status_and_reason/1`, and `report_webhook_failure/4` move verbatim from `CommonWebhook` (common_webhook.ex:840-905). Same `%SystemError{message: "Webhook system_error from #{webhook_name}"}` so AppSignal grouping does not change.

**The three reporting phases remain distinct, all routed through Instrumentation:**

| Phase | Today | After |
|---|---|---|
| Execution (call/2) | `with_failure_reporting` in 2 modules | `Instrumentation.around/3` — ONE place |
| Callback (resume) | `maybe_report_callback_failure` in flow_resume_controller.ex:142 | `Instrumentation.report_callback_failure/2` — same tags, `SystemError{message: "Webhook callback failure"}` |
| Timeout | `maybe_report_timeout` in flow_context.ex | `Instrumentation.report_timeout/2` — unchanged `TimeoutError`, unchanged tags |

**Latency:**
- Existing `kaapi_llm_latency` distribution at flow_resume_controller.ex:300 stays exactly where it is — preserves today's metric.
- New `flow_webhook_latency` distribution emitted by `Instrumentation.around/3` with tags `%{webhook_name: ..., mode: :sync | :async, outcome: :ok | :error}`. Always-on per user choice.

## E. E2E test strategy (lands FIRST, before any refactor)

New file: `test/glific/flows/webhooks/contract_test.exs`. Tests the **current production code** through the **public surface** — assertions are written to keep passing across the refactor.

```elixir
defmodule Glific.Flows.Webhooks.ContractTest do
  use Glific.DataCase, async: false
  import Mock  # already used by webhook_test.exs

  @sync_webhooks  [%{url: "geolocation", ...}, %{url: "parse_via_chat_gpt", ...}, ...]
  @async_webhooks [%{url: "speech_to_text", ...}, %{url: "filesearch-gpt", ...}, ...]

  for w <- @sync_webhooks do
    describe "sync webhook #{w.url}" do
      test "happy path returns map and writes exactly one log row"
      test "failure path returns %{success: false} and fires exactly one Appsignal report"
      test "exception path rescues, re-raises, fires one Appsignal report"
    end
  end

  for w <- @async_webhooks do
    describe "async webhook #{w.url}" do
      test "parks flow with is_await_result=true on success"
      test "wakes flow with Failure + one Appsignal report on Kaapi failure"
      test "callback resumes flow with same webhook_log_id"
      test "timeout fires TimeoutError with org_id/webhook_name/flow_id/contact_id"
    end
  end

  describe "generic HTTP webhook (POST/GET)" do
    test "Oban perform updates log and wakes flow"
    test "non-2xx response writes log error and wakes with Failure"
  end
end
```

**Invariants asserted per row:**

1. `WebhookLog` count delta = exactly 1.
2. `WebhookLog.url == webhook url`, `request_json` non-empty, `status_code` set on completion.
3. Appsignal capture (reuse the `capture_appsignal` helper at common_webhook_test.exs:1382-1420) sees N reports per failure:
   - sync failure: N=1, `SystemError`, tags include `organization_id`, `webhook_name`, optionally `http_status`/`reason`.
   - async Kaapi failure: N=1, `SystemError`.
   - async timeout: N=1, `TimeoutError`.
   - async callback-arrived-with-success=false: N=1, `SystemError` with `webhook_log_id` in tags.
4. For async: `FlowContext.is_await_result == true` after `call/2`; `wakeup_at` in future.
5. For async callback: posting the canonical payload to `/webhook/flow_resume` (reuse `FlowResumeControllerTest` signature helpers) results in `FlowContext.is_await_result == false`, same `webhook_log_id` updated (no new row), correct Success/Failure temp message.
6. For sync happy paths: zero Appsignal reports fire.

Extract shared helpers (signed-payload builders, mock factories) into `test/support/webhook_contract_helpers.ex` so both this test and the existing controller test share them.

## F. Migration sequence (one PR per step)

**Step 1 — Test net (no production code changes).**
- Land `test/glific/flows/webhooks/contract_test.exs` and `test/support/webhook_contract_helpers.ex`.
- Every assertion must pass against current code. Any failure here is a pre-existing bug — file an issue, mark `@tag :skip`, do not fix yet.

**Step 2 — Behaviour + macros + Dispatcher + first webhook (geolocation).** *(landed on current branch)*
- Created `Glific.Flows.Webhooks.{Behaviour, Sync, Async, Registry, Instrumentation, Dispatcher, Errors, ResultTranslator}` under `lib/glific/flows/webhooks/core/`.
- `Errors` re-exports `SystemError`/`TimeoutError`/`Error` for AppSignal grouping compatibility.
- Migrated `geolocation` to `lib/glific/flows/webhooks/implementations/geolocation.ex` with typed success struct `Geolocation.Address`.
- `call/2` returns `{:ok, Address.t()}` | `{:error, String.t()}`. `Dispatcher` applies `ResultTranslator.to_legacy_structure/2` (map on success, string on failure) so flow routing matches legacy `normalize_failure/1` behaviour without changing `Webhook.handle/3` yet.
- HTTP client: Tesla `Logger`, `Telemetry` (`google_maps_geocoding`), and `Glific.get_tesla_retry_middleware/0`.
- `CommonWebhook.webhook("geolocation", ...)` delegates to `Dispatcher.dispatch_named/3`. All other clauses untouched.
- Tests: `test/glific/flows/webhooks/implementations/geolocation_test.exs` (raw tuples + middleware/retry), `result_translator_test.exs`, `webhook_infrastructure_test.exs` (dispatcher wire format), `common_webhook_test.exs` (integration).

**Step 3 — Migrate remaining sync FUNCTION webhooks, one PR each, in this order:**
1. `detect_language`, `get_buttons`, `check_response` — pure deterministic.
2. `parse_via_chat_gpt`, `parse_via_gpt_vision` — exercise rescue path.
3. `speech_to_text_with_bhasini`, `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini` — exercise Tesla failure.
4. `send_wa_group_poll`, `create_certificate` — multi-step business logic.

**Per-webhook migration recipe:**
- Extract `CommonWebhook.webhook("X", fields, headers)` body into `Glific.Flows.Webhooks.X.call/2`.
- Prefer `{:ok, typed_struct}` / `{:error, String.t()}` from `call/2`; add `ResultTranslator.encoder_for/1` when the success type is not a plain map.
- Do **not** call `ResultTranslator` from the webhook module — encoding is only in `Dispatcher`.
- Register `X` in `Registry`.
- Shrink the `CommonWebhook.webhook("X", ...)` clause to `Dispatcher.dispatch_named("X", fields, headers)`.
- Remove that webhook's `|> normalize_failure()` pipe if present (dispatcher encoding supersedes it for tuple results).
- Run `test/glific/flows/webhooks/` + relevant `common_webhook_test.exs` cases.

**Step 4 — Migrate generic HTTP (`GenericHttp`).** Risky — handle with care.
- The current `Webhook` Oban worker (lib/glific/flows/webhook.ex:455-540) becomes `Glific.Flows.Webhooks.GenericHttp.Worker`.
- Oban queue name (`:webhook`) and `unique` config (lines 21-30) preserved bit-for-bit so in-flight jobs don't orphan.
- `Action.execute(%{type: "call_webhook"} = action, ...)` updated to call `Dispatcher.dispatch/2` instead of `Webhook.execute/2`.
- **Risk:** in-flight Oban jobs reference the old worker module by string in the DB. Mitigation: keep `Glific.Flows.Webhook.perform/1` as a `defdelegate` to the new worker for ≥48h after deploy. Each Oban row resolves the worker module at perform time; delegation keeps old rows runnable.

**Step 5 — Migrate async webhooks:**
1. `unified-llm-call` / `filesearch-gpt` — most exercised by tests.
2. `unified-voice-llm-call` / `voice-filesearch-gpt` — overrides `handle_resume/2`.
3. `speech_to_text`, `text_to_speech` — special: they enqueue `SttTtsWorker`. The new modules' `call/2` calls `SttTtsWorker.enqueue/5` (logic from webhook.ex:143-188 moves over). The Kaapi call inside the worker still goes through `CommonWebhook.webhook/3` → Dispatcher. Idempotency requirement: when `ctx.webhook_log_id` is already set, `Instrumentation` skips log creation and reuses it.

**Step 6 — Migrate callback path.**
- Move `parse_callback_response/1`, `maybe_upload_tts_audio/1`, `track_kaapi_latency/1`, `maybe_report_callback_failure/2` from `flow_resume_controller.ex` into `Glific.Flows.Webhooks.Callback`.
- Controller becomes a thin shell that calls `Callback.handle_text/2` and `Callback.handle_voice/2`.
- Each async webhook module can now override `handle_resume/2` for response shaping.

**Step 7 — Delete duplicates.** One final PR:
- Delete `Glific.Flows.Webhook.with_failure_reporting/3` (webhook.ex:711-723).
- Delete `Glific.Clients.CommonWebhook.with_failure_reporting/3` and helpers `maybe_report_webhook_failure/3`, `report_webhook_failure/4`, `extract_status_and_reason/1` (common_webhook.ex:840-905).
- `CommonWebhook.webhook(name, fields, headers)` head reduces to `Dispatcher.dispatch_named(name, fields, headers)`. The org-fallback in `Glific.Clients.webhook/3` (clients.ex:277-284) is preserved.
- The four `def execute(%{type: "call_webhook", method: "FUNCTION", url: ...})` clauses in `action.ex:643-673` collapse into the single `def execute(%{type: "call_webhook"} = action, context, [])` clause delegating to `Dispatcher.dispatch/2`.

## G. Critical files

**Modified:**
- `lib/glific/flows/action.ex` — collapse FUNCTION dispatch at lines 643-682 into single Dispatcher call.
- `lib/glific/flows/webhook.ex` — shrink to facade; delete `with_failure_reporting`; preserve `report_to_appsignal`, `update_log`, `create_log`.
- `lib/glific/clients/common_webhook.ex` — each `def webhook(name, ...)` head shrinks to Dispatcher call; delete `with_failure_reporting` block at 840-905.
- `lib/glific_web/flows/flow_resume_controller.ex` — move parse/upload/latency/report helpers into `Webhooks.Callback`; controller becomes thin shell.
- `lib/glific/flows/flow_context.ex` — replace `maybe_report_timeout` with `Webhooks.Instrumentation.report_timeout/2` (same args, same struct, same tags).
- `lib/glific/third_party/kaapi/stt_tts_worker.ex` — use `Webhooks.Errors` and `Webhooks.Instrumentation.report_callback_failure/2` from one place instead of inlining log updates.

**Created (Step 2, current branch):**
- `lib/glific/flows/webhooks/core/{behaviour,dispatcher,registry,instrumentation,errors,result_translator,sync,async}.ex`
- `lib/glific/flows/webhooks/implementations/geolocation.ex`
- `lib/glific/flows/webhooks/implementations/geolocation/address.ex`
- `test/glific/flows/webhooks/core/{webhook_infrastructure_test,result_translator_test}.exs`
- `test/glific/flows/webhooks/implementations/geolocation_test.exs`

**Planned (later steps):**
- `lib/glific/flows/webhooks/callback.ex`, `generic_http.ex`, remaining `implementations/*.ex`
- `test/glific/flows/webhooks/contract_test.exs`, `test/support/webhook_contract_helpers.ex`

**Reused as-is** (referenced by Instrumentation / Dispatcher):
- `Glific.Flows.Webhook.report_to_appsignal/2` (webhook.ex:80-91) — already the single AppSignal sink, kept exactly as-is.
- `Glific.Flows.WebhookLog` — schema and CRUD unchanged.
- `Glific.ThirdParty.Kaapi.SttTtsWorker` — Oban worker unchanged; only its `do_kaapi_call/5` failure path is routed through `Instrumentation.report_callback_failure/2`.
- Existing `capture_appsignal` test helper (common_webhook_test.exs:1382-1420) — extracted to `test/support/webhook_contract_helpers.ex` in Step 1 and reused.

## H. Verification

Per step:

1. `mix test test/glific/flows/webhooks/contract_test.exs` — must stay green from Step 1 onward. **This is the gate.** No step proceeds otherwise.
2. `mix test test/glific/flows/ test/glific_web/flows/ test/glific/third_party/kaapi/` — full webhook surface.
3. `mix check` — Credo, Dialyzer, format.
4. `mix test` — full suite once per step.

**Manual exercise (dev env):**
- `mix phx.server` against a dev DB with an organization that has Kaapi creds configured.
- In Floweditor, build a flow with each webhook type: one sync FUNCTION (e.g. `parse_via_chat_gpt`), one async FUNCTION (e.g. `speech_to_text`), one generic POST. Trigger via a test contact.
- Inspect `webhook_logs` table — row count, `request_json`, `response_json`, `status_code`, `error` must match a control capture taken before Step 2.

**AppSignal byte-equality verification:**
- Before Step 2: capture a baseline. In an IEx shell, force-trigger each failure path (mock Kaapi to return `%{success: false, reason: "x"}`, time out an async webhook, raise inside a sync webhook). Wrap `Appsignal.send_error` via `Mock` and record the `inspect/2` of its arguments.
- After each migration step: re-run the same scenarios, diff. Diff must be empty modulo the new `flow_webhook_latency` distribution.
- Specifically diff: exception module (`SystemError` vs `TimeoutError`), `message` field byte-identical, tag keys/values `{organization_id, webhook_name, flow_id, contact_id, webhook_log_id, http_status, reason, error_type}`.

**Rollback:** every step is one PR. Old call sites are preserved until the step that explicitly deletes them, so every intermediate state on `master` compiles and behaves identically to before. Revert is `git revert <step>`.

## Risks called out

- **Step 4 Oban handoff** is the riskiest. In-flight `:webhook` queue jobs reference the worker module by string in `oban_jobs.worker`. The `defdelegate` shim in old `Glific.Flows.Webhook` is mandatory and stays for ≥1 deploy cycle (~48h).
- **Step 5 STT/TTS dispatch through Dispatcher inside `SttTtsWorker`** is subtle. The webhook log already exists at perform time. `Instrumentation.around/3` must accept `ctx.webhook_log_id` and skip log creation when present, matching today's `CommonWebhook.webhook("speech_to_text", ...)` which expects the log row to already exist.
- **`call_and_wait`** is documented deprecated. Migrate last (or leave as the lone legacy clause in `CommonWebhook` and migrate when it's deleted). Do not block earlier steps on it.

## Step 2 follow-ups (post-geolocation PR)

- Refactor `Glific.Flows.Webhook.handle/3` to route on application success (not `is_map/1`), then delete `ResultTranslator`.
- Land `contract_test.exs` (Step 1) if not already present.
- Migrate remaining sync FUNCTION webhooks per Step 3 recipe (`{:ok,_}` / `{:error,_}` + `encoder_for/1`).

## Deferred: `handle/3` map-vs-string routing

`ResultTranslator` exists solely because `handle/3` emits `"Success"` for any map. Geolocation failures must be strings at the dispatcher boundary until that changes. Do not add `normalize_failure/1` to new migrated webhooks — use tuples + `ResultTranslator` instead.
