# Flow Webhook Refactor Plan

Re-implements PR #5153 ("refactor: init version of flow webhook rewrite") with all CodeRabbit
feedback incorporated. Introduces a pluggable `Glific.Flows.Webhooks` architecture with
compile-time contracts, centralised instrumentation, and an incremental migration path.

## Goals

1. **Pluggable architecture** — new webhooks are modules, not clauses in `common_webhook.ex`
2. **Centralised observability** — one place for AppSignal reporting, Metrics counters, latency telemetry
3. **Incremental migration** — existing webhooks stay untouched; new modules are added alongside
4. **Clean result contract** — `{:ok, value}` / `{:error, msg}` tuples from migrated webhooks; `ResultTranslator` handles legacy shapes

## Module Layout

```
lib/glific/flows/webhooks/
├── core/
│   ├── behaviour.ex       # @callback contracts + type definitions
│   ├── sync.ex            # use-macro: injects name/0, mode/0 (:sync)
│   ├── async.ex           # use-macro: same + wait_time_default/0 (overridable)
│   ├── errors.ex          # Errors.SystemError, TimeoutError, Error (new defexception)
│   ├── registry.ex        # name → module mapping, separate from Dispatcher
│   ├── result_translator.ex  # {ok,err} tuples → legacy map/string
│   ├── instrumentation.ex # around/3, report_callback_failure/2, report_timeout/1
│   └── dispatcher.ex      # dispatch_named/3 entry point
└── implementations/
    ├── geolocation/
    │   └── address.ex     # Address struct + to_flow_map/1
    └── geolocation.ex     # first migrated webhook
```

## Behaviour Contract (`Glific.Flows.Webhooks.Behaviour`)

```elixir
@callback name() :: String.t()
@callback mode() :: :sync | :async
@callback call(fields :: map(), ctx :: ctx()) :: sync_result() | async_result()
@optional_callbacks [handle_resume: 2, wait_time_default: 0]
```

- `ctx()` carries `organization_id`, `headers`, and optional flow-context fields
- `sync_result` covers both legacy map/string returns and new `{:ok, v}` / `{:error, msg}` tuples
  (`ResultTranslator` normalises all forms — no separate `migrated_sync_result` type)

## Macro Pattern

`use Glific.Flows.Webhooks.Sync, name: "geolocation"` injects at compile time:
- `@behaviour Behaviour`
- `name/0` → compile-time constant string
- `mode/0` → `:sync`

`use Glific.Flows.Webhooks.Async, name: "kaapi_asr"` additionally injects:
- `wait_time_default/0` → `60` (overridable via `defoverridable`)

## Instrumentation

`Instrumentation.around(module, ctx, fun)` wraps every dispatched call:

1. Times via `System.monotonic_time/0`
2. Calls `fun.()`
3. Emits `"flow_webhook_latency"` distribution to AppSignal with `{webhook_name, mode, outcome}` tags
4. Increments `Glific.Metrics` counter (e.g. `"Geolocation API Success"`)
5. Reports failures via `Glific.log_exception/1` with `namespace: "flow_webhooks"`

Exception types are `Glific.Flows.Webhooks.Errors.{SystemError, TimeoutError}` — **new independent
defexceptions**, not re-exports from `Glific.Flows.Webhook.*`. AppSignal incident grouping changes
are acceptable; the old exception classes remain in place for legacy code.

Callback and timeout paths use dedicated functions:
- `report_callback_failure/2` — Kaapi async callback with `success != true`
- `report_timeout/1` — async webhook's await window expired

## Registry vs Dispatcher Split

`Registry` holds only the name → module map. `Dispatcher` orchestrates the full pipeline
(lookup → ctx → instrumentation → translation). The split provides a test seam: mocking
`Registry.lookup!` redirects the entire dispatch pipeline to a stub module without coupling
tests to the Dispatcher's internal structure.

## ResultTranslator

Temporary adapter during migration. As each webhook moves to tuple returns:
- `{:ok, value}` → calls `encoder_for(module)` → adds `success: true`
- `{:error, message}` → returns bare string (flow engine routes non-map to Failure branch)
- legacy map/string → passes through unchanged

`encoder_for(Geolocation)` → `&Address.to_flow_map/1`. Unknown modules use `default_encoder/1`
(struct → `Map.from_struct` + `success: true`; map → `Map.put(:success, true)`; scalar → wraps).

Remove `ResultTranslator` once all webhooks return tuples and the flow engine routes on the
application-level `success` field instead of `is_map/1`.

## Migration Sequence

| Step | Action |
|------|--------|
| 1 | ✅ Core infrastructure (`behaviour`, `sync`, `async`, `errors`, `registry`, `result_translator`, `instrumentation`, `dispatcher`) |
| 2 | ✅ Geolocation — first migrated webhook (`Geolocation` + `Address`) |
| 3 | ✅ Route `common_webhook.ex` geolocation clause through `Dispatcher.dispatch_named/3` |
| 4 | Migrate `with_failure_reporting` webhooks one by one (each shrinks `common_webhook.ex` by ~20 lines) |
| 5 | Migrate Kaapi async webhooks — add `handle_resume/2` + `wait_time_default/0` |
| 6 | Remove `with_failure_reporting` helper from `common_webhook.ex` once empty |
| 7 | Remove `ResultTranslator` and update flow engine to route on `{:ok, _}` / `{:error, _}` |

## Invariants

- `test/glific/flows/webhooks/*.exs` (12 e2e tests) — never modified
- Flow JSON URL string `"geolocation"` preserved
- `WebhookLog` schema and CRUD untouched
- `Glific.log_exception/1` is the only AppSignal reporting path (never call `Appsignal.send_error` directly)

## Tests Added

- `test/glific/flows/webhooks/implementations/geolocation_test.exs` — unit tests for `call/2`, all Google status codes, middleware, whitespace coords, retry
- `test/glific/flows/webhooks/core/result_translator_test.exs` — all `to_legacy_structure/2` shapes
- `test/glific/flows/webhooks/core/webhook_infrastructure_test.exs` — Registry, Instrumentation, Dispatcher, macro behaviour, Errors

## Files Modified

- `lib/glific/clients/common_webhook.ex` — geolocation clause delegated to `Dispatcher.dispatch_named/3`; private helpers removed
- `lib/glific/partners.ex` — `update_credential/2` propagates `organization_id` into attrs; spec tightened
- `lib/glific/third_party/bigquery/bigquery.ex` — spec tightened (`non_neg_integer() | nil` → `non_neg_integer()`)
- `test/glific/flows/common_webhook_test.exs` — geolocation failure assertion updated to match new error message shape
- `test/glific_web/controllers/kaapi_controller_test.exs` — `{:ok, _}` → `{:ok, failed_version}` for timestamp assertion
