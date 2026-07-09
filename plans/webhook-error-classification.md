# Webhook error classification: config vs system errors

Issue: [#5196](https://github.com/glific/glific/issues/5196)

## Problem

All webhook failures report to AppSignal as `SystemError`. ~85% are actually **config errors**
(NGO admin / user caused: missing key, bad JSON, unresolved `@…` var, Kaapi not active), so
on-call gets paged for problems only the user can fix.

Goal: split into two AppSignal namespaces — **system** errors page on-call, **config** errors
notify support.

## Two reporting stacks (both live, both get the change)

| Stack | Exception | Reports via | Used by |
|---|---|---|---|
| Legacy | `Glific.Flows.Webhook.SystemError` | `Webhook.report_to_appsignal/2` | sync `CommonWebhook` nodes |
| New | `Glific.Flows.Webhooks.Errors.SystemError` | `Instrumentation` (`Glific.log_exception`) | async Kaapi nodes |

---

## Architecture revision (post-review) — unidirectional error flow

The first cut (PR #5351, already merged/shipped) centralised classification behind a
`Behaviour.error_class/1` **callback**: `ErrorClassifier.classify(module, result)` calls *back
into* the module to ask for its verdict. Review flagged this as the wrong shape — it makes the
control flow **bounce back into the module**:

```
flow → dispatcher → instrument → filesearch_gpt.call → (error) → instrument
     → ErrorClassifier.classify(module, …) → filesearch_gpt.error_class   ← re-enters the module
```

**Target: a unidirectional pipeline. The module names the error once, on the way out, and the
call never comes back to it.**

- **`call/2` returns the error type inline.** Instead of `%{success: false, reason: …}` +
  a separate `error_class/1` clause, the module returns the class *with* the failure — one
  value, one direction. Pattern-match on it downstream (`:config` vs `:system`), don't ask the
  module again.
- **`AsyncResult` gains an `error_type` field** (plus the message). Async acks/callbacks carry
  the class the same way sync returns do — an async failure can be `:config` or `:system` just
  like a sync one.
- **`ErrorClassifier` becomes a pure function of the returned result** — module verdict is read
  off the result, not fetched via a callback. The heuristic tiers (crash / transient / provider
  status) stay exactly as-is for *external* errors the module can't classify; they already only
  read the returned result, so they're already unidirectional.
- Keep a **single** classifier for the Copilot/Oracle LLM-copy calls; other nodes handle their
  own returns. Don't grow one mega-switch across unrelated node types.

### Sync first, async second (incremental)

- **Sync nodes:** most validation happens upfront; provider 400s are caught when the response
  comes back. Return `:config`/`:system` inline from `call/2`. Do these first — lower risk.
- **Async nodes:** some config errors only surface at *runtime* from Copilot (e.g. unresolved
  conversation/thread id → 400). These can't be validated upfront — they must be caught in the
  **webhook / flow-resume controller** and reported as `:config` there. Upfront checks still
  apply where possible (e.g. assistant-id prefix validation). Tackle async **after** sync lands.

### PR sequencing

1. **This work / done:** classification engine + routing (config vs system namespaces), stale +
   transient suppression. Shipped with the callback shape.
2. **Next PR:** migrate the remaining sync nodes off `CommonWebhook` (same pattern as
   `create_certificate` / `geolocation`), **and** fix the error structure in the same PR —
   replace the callback with the unidirectional `call/2` return + `AsyncResult.error_type`, and
   simplify away the verbose current result format. Delete `CommonWebhook` once the last call is
   moved.
3. **Cleanup:** remove the legacy `report_to_appsignal/2` + `Webhook.SystemError` path from the
   codebase (used only by pre-framework nodes). AppSignal history is retained by its 30-day
   retention, so deleting the code loses nothing operationally. Tracked in
   [#5346](https://github.com/glific/glific/issues/5346).

### Config-error hotspots to design around

- **STT and GPT/Copilot nodes** — thread/conversation-id typos, user-input errors (highest volume).
- **Create Certificate** — users store the cert template in a *personal* drive instead of the
  *shared* drive; a frequent, self-inflicted config failure worth its own clear message.
- **`"… does not have any active flows awaiting results"`** — flow moved on before the async
  response arrived. Currently classed `:stale` (suppressed); flagged for **investigation** (why
  the flow advances early), not just suppression.

---

## Solution overview

Production logs show **four** failure kinds, not two. Two of the highest-volume ones both flow
through `report_resume_failure` and are *not* provider/system failures:

- **stale** — `"<id> does not have any active flows awaiting results"` (`flow_context.ex:1011`):
  a late/duplicate Kaapi callback for a flow that already resumed or expired. Expected race,
  ~half of all volume. **Not an error** — suppress it (counter only, no AppSignal incident),
  ideally at the source in `report_resume_failure`.
- **transient (upstream-busy)** — OpenAI `conversation_locked` / "Another process is currently
  operating" / `server_is_overloaded` / rate-limit. **Not retried** (flow fails to the contact),
  but not actionable per-occurrence — track the *rate*, don't page on singletons. OpenAI returns
  these as **400/503**, so a naive status rule misfiles them — they need their own tier *before*
  status.

So:

1. Add a `ConfigurationError` exception type (to both stacks).
2. **Centralise classification in the framework, not at call sites.** One engine
   (`Webhooks.ErrorClassifier`) holds all the generic rules; the `Behaviour` gains one optional
   `error_class/1` callback so a module can classify *its own* domain failures in a single local
   place; the `Sync`/`Async` macro injects a default so modules opt in only when they need to.
   `Instrumentation` calls the engine once and routes — no per-site `error_type` tagging.
3. Class is `:config | :system | :transient | :stale` (`:timeout` unchanged).
4. Route: `:config` → `flow_webhook_config_errors` (notify); `:system` → `flow_webhooks`
   (page); **`:transient` → metric only (no incident); `:stale` → suppressed (counter only)**.

### Where classification lives (centralised)

```
                        module.error_class(result)          # per-module, ONE local clause (optional)
                                 │  (nil → defer)
report site ──► ErrorClassifier.classify(module, result) ──► ErrorClassifier heuristics   # crash→transient→status→failsafe
  (Instrumentation / CommonWebhook / resume)      │
                                                  └──► class ──► route: report | notify | count | suppress
```

- `Webhooks.ErrorClassifier` — the **single** engine: the fallback tiers below + the routing
  map. Used by both the new and legacy stacks and the resume path.
- `Behaviour.error_class/1` — the **one** hook a module implements to name its own failures
  (`:config` for `Media URL is invalid`, etc.), co-located with the code that raises them.
  Returns `nil` to defer to the engine.
- `Sync`/`Async` macro — injects `def error_class(_), do: nil` + `defoverridable`, so every
  webhook has it for free.
- `Instrumentation` — one call: `class = ErrorClassifier.classify(module, result)`, then route.

> **`Kaapi is not active` and missing `X-API-KEY` are `:system`, not `:config`.** Glific
> auto-onboards orgs to Kaapi and manages their keys, so an inactive/keyless org is a Glific
> **provisioning gap** we must fix — it should page, not go to the NGO. (This overrides issue
> #5196, which listed them as config.)

---

## ⚠️ The `status_code` DB column is useless — ignore it

`webhook.ex:173` hardcodes `status_code: 400` for **every** failure. So a Gemini 500, a
Cloudflare 502, and an Elixir crash all log as `400`. **Classification must never read that
column.** The provider's *real* status lives inside `response_json`, in one of two places:

- a nested **`http_status`** field (e.g. `%{success: false, http_status: 502}`), or
- embedded as **text in the message/reason** string: `(code: 400)`, `(code: 500 INTERNAL)`,
  `Status: 403`.

Some failures have neither status nor a parseable code — they're classified by `error_type`
(if Glific-raised) or fall to crash/pattern heuristics.

## Classification — module callback first, engine heuristics as fallback

`ErrorClassifier.classify(module, result)`:

1. **Module callback** — if the failing webhook module implements `error_class/1` and it returns
   a non-nil class for this result, use it. This is the deterministic, per-module path: each
   module names its own domain failures in one local clause, so a reworded message is fixed in
   the same file and never remisclassifies.
2. **Engine heuristics** — otherwise run the generic tiers below (for external provider errors
   the module can't or didn't classify).

The module knows its own failures, so the `:config` cases that used to be scattered patterns now
live as one `error_class/1` clause per owning module:

| Module / site | `error_class/1` returns | Class |
|---|---|---|
| `third_party/kaapi.ex` (not active) | `:system` | provisioning gap — we onboard |
| `webhooks/kaapi.ex` (missing `X-API-KEY`) | `:system` | we manage keys |
| `Geolocation` (bad `latlng`) | `:config` | user input |
| `FilesearchGpt` (assistant not found) | `:config` | flow config |
| STT / voice impls (media invalid/needed) | `:config` | user input |
| `Request` (bad JSON body) | `:config` | flow author |
| `CommonWebhook` fallthrough (unknown fn) | `:config` | flow author |
| resume path (`report_resume_failure`) | `:stale` / `:config` | stale callback / `Could not find category` |

Everything with no module verdict falls to the engine:

### Engine tiers (fallback, checked in order)

For **external** provider errors relayed as opaque strings. Inputs: a **real provider status**
(nested `http_status` OR a code parsed from the message) and the **reason** string.

### Tier 2 — Crash signature → system

A crash surfaces as a failure logged `400` with no real status — `GCSWORKER: upload failed —
no function clause matching …`, `function nil.webhook/2 is undefined`. Match first, force
**system**: `~r/no function clause matching|is undefined|no match of right hand side|\*\* \(/`

### Tier 3 — Stale callback → suppress

The resume path isn't a webhook module, so `report_resume_failure` supplies the class directly:
it recognises the `flow_context.ex:1011` reason as `:stale` (counter only, **no** AppSignal
incident) and the `router.ex` reason as `:config` (`Could not find category`). Everything else
from resume defers to the engine.

### Tier 4 — Upstream-transient → count, alert on rate (MUST precede status)

`~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit|try again/`
→ **transient**. **We do NOT retry** — the flow takes its Failure branch and the contact's
message goes unanswered, so this is a real user-visible failure. But a *single* occurrence isn't
actionable (on-call can't fix OpenAI being busy), so it doesn't belong in config (NGO can't act)
or page-on-every system. Treatment: its own `error_type`, **counted**, with a **rate-based
AppSignal alert** that fires only on an abnormal spike (= a genuine OpenAI outage, or a Glific
concurrency bug for `conversation_locked`). Runs *before* the status tier because OpenAI returns
these as a **400/503** that the status rule would otherwise misfile as config/system.

> `conversation_locked` often means Glific fired two LLM calls at the same conversation
> concurrently — worth a separate investigation, not just monitoring.

### Tier 5 — Real provider status (nested field or parsed from the string)

Real status only, never the DB column: `http_status` if present, else parsed with
`~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/`.

| Signal | Verdict |
|---|---|
| 400–499 (except 408, 429) | **config** — provider rejected our request (bad/empty input, unresolved var) |
| 408 / 429 | **transient** |
| ≥ 500 | **system** — provider down (Gemini 500, OpenAI 503, Cloudflare 502/520) |

### Tier 6 — Reason fallback (external, untagged, no status)

Only external strings we can't tag reach here. `conversation_locked` etc. are already caught by
Tier 4. A tiny allowlist remains as a safety net; everything else fails safe to system.

**Fail safe: anything unmatched stays `:system` so it still pages.**

> **Decision — ambiguous statusless cases default to system, on purpose.** Inaudible-audio STT,
> `[GEMINI] Failed to extract audio bytes`, `Audio file download failed`, `[KAAPI] … NoneType`
> are **not** promoted — they can look identical to a real Kaapi/Gemini outage, so we page and
> investigate. Add an `error_type` (or Kaapi does) once we're sure of the cause.

### The engine

`Glific.Flows.Webhooks.ErrorClassifier` — one module, used by both stacks and the resume path.

```elixir
@crash     ~r/no function clause matching|is undefined|no match of right hand side|\*\* \(/
@transient ~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit|try again/
@code      ~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/

# Entry point: module verdict wins, else the engine heuristics.
@spec classify(module() | nil, map()) :: :config | :system | :transient | :stale
def classify(module, result) do
  cond do
    module && function_exported?(module, :error_class, 1) && (c = module.error_class(result)) -> c
    true -> heuristic(result)
  end
end

# reason = result["reason"] || result["error"] || result["message"];
# http_status = NESTED result["http_status"] (never the DB status_code column)
defp heuristic(result) do
  reason = result["reason"] || result["error"] || result["message"] || ""
  code = result["http_status"] || provider_status(reason)
  cond do
    reason =~ @crash -> :system                                    # Tier 2
    reason =~ @transient -> :transient                             # Tier 4 (before status)
    code in [408, 429] -> :transient                               # Tier 5
    is_integer(code) and code in 400..499 -> :config               # Tier 5
    is_integer(code) -> :system                                    # Tier 5 (5xx)
    true -> :system                                                # fail safe
  end
end

defp provider_status(reason) do
  case Regex.run(@code, reason) do
    [_, code] -> String.to_integer(code)
    [_, _, code] -> String.to_integer(code)
    _ -> nil
  end
end
```

The `Behaviour` callback + macro default:

```elixir
# Behaviour
@callback error_class(result :: map()) :: :config | :system | :transient | :stale | nil

# Sync / Async __using__ macro injects:
def error_class(_result), do: nil
defoverridable error_class: 1

# e.g. Geolocation overrides in ONE place:
def error_class(%{reason: "Invalid geocoding request" <> _}), do: :config
def error_class(_), do: nil
```

`:timeout` is unchanged — its own `TimeoutError` path, `flow_webhooks` namespace.

**Routing:** `:system` → `flow_webhooks` (page) · `:config` → `flow_webhook_config_errors`
(notify) · `:transient` → metric only, no incident · `:stale` → counter only, suppressed.

> **Durable fix (separate Kaapi ask):** the callback should send a structured `http_status` +
> `error_type` in its body instead of burying the code in prose. Glific already reads
> `result["error_type"]` into tags (always nil today). Once Kaapi populates it, Tier 5 keys off
> the real field and the regex becomes a pure fallback. Track as a Kaapi-side request.

---

## Changes needed

**1. NEW `lib/glific/flows/webhooks/core/error_classifier.ex`** — the single engine.
`classify(module, result)` (module verdict → engine heuristics) + `route(class)` mapping class
→ `{:report, namespace} | :count | :suppress`. Both stacks and the resume path call this.

**2. `lib/glific/flows/webhooks/core/behaviour.ex`** — add the optional callback
`@callback error_class(result :: map()) :: :config | :system | :transient | :stale | nil`.

**3. `lib/glific/flows/webhooks/core/sync.ex` + `async.ex`** — inject the default in `__using__`:
`def error_class(_result), do: nil` + `defoverridable error_class: 1`. Every webhook gets it
free; authors override only when they own domain failures.

**4. Per-module `error_class/1` overrides** — one local clause each, co-located with the code
that raises the failure: `Geolocation` (`:config`), `FilesearchGpt` (assistant-not-found →
`:config`), STT/voice impls (media → `:config`), and the Kaapi-creds path (`:system`). No
changes at every return site — just the one classifier clause per module.

**5. `lib/glific/flows/webhook.ex`** — add `ConfigurationError`; `report_to_appsignal/2` picks
namespace from the exception struct (`ConfigurationError` → `flow_webhook_config_errors`).

**6. `lib/glific/flows/webhooks/core/errors.ex`** — add the same `ConfigurationError`; drop the
"intentionally absent" note.

**7. `instrumentation.ex`** (new stack) — `report_failure` / `report_callback_failure` /
`report_resume_failure` each become: `class = ErrorClassifier.classify(module, result)` then
`route(class)` — `{:report, ns}` builds `ConfigurationError`/`SystemError` under `ns`; `:count`
bumps the metric; `:suppress` returns without reporting. `track_webhook_count/3` adds
`error_type: to_string(class)`. `report_resume_failure` supplies stale/`Could not find category`
verdicts directly (no module).

**8. `lib/glific/clients/common_webhook.ex`** (legacy stack) — `report_webhook_failure/4` calls
the same `ErrorClassifier.classify/2` + `route/1`; add `error_type` to the metric.

**9. `lib/glific_web/flows/flow_resume_controller.ex:26`** — remove the stray `IO.inspect(result)`.

---

## How to test

New `test/glific/flows/webhook_test.exs` — `Tesla.Mock` for provider responses, assert on the
AppSignal span namespace + the built exception type + the metric tag.

**Module-callback tests** — a fake module implementing `error_class/1` wins over the engine:
- `classify(GeoStub, %{"reason" => "Invalid geocoding request…"})` → `:config`
- `classify(KaapiStub, %{...})` → `:system` (even with a 400/500 in the result — module wins)

**Engine `heuristic/1` tests (one per fallback branch):**

| `result` | Expected | Tier |
|---|---|---|
| `%{"reason" => "…no function clause matching…"}` | `:system` | 2 (crash, logged 400) |
| `%{"reason" => "OpenAI bad request (code: 400): …conversation_locked…"}` | `:transient` | 4 |
| `%{"http_status" => 502}` | `:system` | 5 (nested field) |
| `%{"message" => "OpenAI bad request (code: 400): Invalid 'conversation.id'…"}` | `:config` | 5 (code from string) |
| `%{"message" => "[GEMINI] Server error (code: 500 INTERNAL): …"}` | `:system` | 5 |
| `%{"reason" => "[GEMINI] STT response is missing transcribed text…"}` | `:system` | fail safe |

**Integration tests:**
- Kaapi-not-active → **system** namespace (via module `error_class/1`), not config.
- A Geolocation failure → config namespace, driven by the callback (assert it still classifies
  config even if the message text changes — proves it's not string-matched centrally).
- A `"does not have any active flows"` resume failure → **no AppSignal incident**, counter only.
- A `conversation_locked` callback → transient (no page).
- `flow_webhook_count` carries `error_type`.
- `mix check` passes.

---

## Acceptance criteria
- [ ] classification lives in one `ErrorClassifier` engine + one `Behaviour.error_class/1`
  callback (macro-defaulted); no per-return-site tagging
- [ ] `kaapi_not_active` + `missing_api_key` classify as **system** (not config)
- [ ] config errors report under `flow_webhook_config_errors`, system under `flow_webhooks`
- [ ] stale ("no active flows") suppressed to a counter — no incident
- [ ] transient (`conversation_locked` / overloaded / 429) does not page
- [ ] `flow_webhook_count` has `error_type` (system/config/transient/stale/timeout)
- [ ] both stacks + resume path call `ErrorClassifier.classify/2`
- [ ] module-callback + engine `heuristic/1` unit tests cover every branch + `mix check` passes

## Follow-up
Migrating remaining sync nodes off the legacy stack and deleting `report_to_appsignal/2` +
`Webhook.SystemError` is tracked in [#5346](https://github.com/glific/glific/issues/5346).
