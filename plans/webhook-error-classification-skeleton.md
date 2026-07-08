# Skeleton (pseudo-code) — webhook error classification

Reading aid for [webhook-error-classification.md](webhook-error-classification.md). Each block is
labelled with its real target path. This is **illustrative pseudo-code** — not wired to compile —
meant to show how the pieces connect. Design shown is the behaviour-callback variant; the
typed-return variant (`{:error, ErrorType.t(), msg}`) is noted at the end.

---

## 1. NEW `lib/glific/flows/webhooks/core/error_classifier.ex`

The single engine: `classify/2` (module verdict → heuristic fallback), `route/1`, and the
reporter that turns a class into an AppSignal incident / metric / suppression.

```elixir
defmodule Glific.Flows.Webhooks.ErrorClassifier do
  @moduledoc "Classifies a webhook failure into a bucket and routes the observability signal."

  alias Glific.Flows.Webhook.{ConfigurationError, SystemError}

  # crash = OUR bug; transient = retryable upstream blip; code = real provider status in the text
  @crash     ~r/no function clause matching|is undefined|no match of right hand side|\*\* \(/
  @transient ~r/conversation_locked|Another process is currently operating|is overloaded|server_is_overloaded|rate limit|try again/
  @code      ~r/\(code:\s*(\d{3})|Status:\s*(\d{3})/

  @type class :: :config | :system | :transient | :stale

  # ── entry point ────────────────────────────────────────────────────────────
  # module verdict wins; nil → engine heuristics.
  @spec classify(module() | nil, map()) :: class()
  def classify(module, result) do
    cond do
      module && function_exported?(module, :error_class, 1) && (c = module.error_class(result)) -> c
      true -> heuristic(result)
    end
  end

  # ── engine fallback (external / untyped errors) ──────────────────────────────
  @spec heuristic(map()) :: class()
  defp heuristic(result) do
    reason = result["reason"] || result["error"] || result["message"] || ""
    code   = result["http_status"] || provider_status(reason)   # NEVER the DB status_code column

    cond do
      reason =~ @crash                          -> :system       # our crash (logged as 400)
      reason =~ @transient                      -> :transient    # BEFORE status (locked/overloaded are 400/503)
      code in [408, 429]                        -> :transient
      is_integer(code) and code in 400..499     -> :config       # provider rejected our request
      is_integer(code)                          -> :system       # 5xx
      true                                      -> :system       # fail-safe → still pages
    end
  end

  @spec provider_status(String.t()) :: integer() | nil
  defp provider_status(reason) do
    case Regex.run(@code, reason) do
      [_, code] -> String.to_integer(code)
      [_, _, code] -> String.to_integer(code)
      _ -> nil
    end
  end

  # ── routing: class → action ──────────────────────────────────────────────────
  @spec route(class()) :: {:report, String.t()} | :count | :suppress
  def route(:system),    do: {:report, "flow_webhooks"}
  def route(:config),    do: {:report, "flow_webhook_config_errors"}
  def route(:transient), do: :count      # metric only, no incident (rate-alert in AppSignal)
  def route(:stale),     do: :suppress   # counter only, no incident

  # ── the one place a class becomes a report ───────────────────────────────────
  # `class` picks the struct + namespace; `result`/`tags` carry the message + detail.
  @spec report(class(), map(), map()) :: :ok
  def report(class, result, tags) do
    case route(class) do
      {:report, namespace} ->
        reason = result["reason"] || result["error"] || result["message"] || "Webhook failure"
        # low-cardinality :message so AppSignal groups; detail rides in tags
        exception =
          case class do
            :config -> %ConfigurationError{message: "Webhook config_error from #{tags.webhook_name}"}
            _       -> %SystemError{message: "Webhook system_error from #{tags.webhook_name}"}
          end

        Glific.log_exception(exception,
          namespace: namespace,
          tags: Map.merge(tags, %{reason: reason, error_type: to_string(class)})
        )

      _skip ->   # :count | :suppress → no incident, just the metric below
        :ok
    end

    track_count(tags.webhook_name, class)
    :ok
  end

  defp track_count(webhook_name, class),
    do: Appsignal.increment_counter("flow_webhook_count", 1, %{
          webhook_name: webhook_name || "unknown",
          status: "failure",
          error_type: to_string(class)
        })
end
```

---

## 2. `lib/glific/flows/webhooks/core/behaviour.ex` — add the optional callback

```elixir
@doc """
Classify a failure this webhook produced into a bucket, or nil to defer to the
central engine. Optional — the Sync/Async macro injects a `nil` default.
"""
@callback error_class(result :: map()) :: :config | :system | :transient | :stale | nil
```

---

## 3. `lib/glific/flows/webhooks/core/sync.ex` + `async.ex` — inject the default

```elixir
# inside defmacro __using__(opts), in the quote block of BOTH files:
def error_class(_result), do: nil        # default: "not my error, use the engine"
defoverridable error_class: 1            # …a module may replace it
```

(`sync.ex` already injects `mode → :sync`, `async.ex` → `:async`; this default rides alongside,
so every node — sync or async — is guaranteed to have `error_class/1`.)

---

## 4. Per-module override — one local clause (e.g. `implementations/filesearch_gpt.ex`)

```elixir
defmodule Glific.Flows.Webhooks.FilesearchGpt do
  use Glific.Flows.Webhooks.Async, name: "filesearch-gpt"
  # ↑ macro injects: name/0, mode/0 => :async, error_class/1 => nil (overridable)

  # Only the failures THIS module raises; everything else defers (nil → engine).
  @impl true
  def error_class(%{reason: "Assistant not found" <> _}), do: :config
  def error_class(_), do: nil

  @impl true
  def call(fields, ctx) do
    # ... fires the Kaapi LLM request; returns {:wait, …} or an immediate failure map
  end
end

# geolocation.ex — a sync node classifying its own input error
def error_class(%{reason: "Invalid geocoding request" <> _}), do: :config
def error_class(_), do: nil

# the Kaapi-creds path returns a Glific-owned failure → :system (we onboard/manage keys)
def error_class(%{reason: "Kaapi is not active" <> _}), do: :system
```

---

## 5. `lib/glific/flows/webhook.ex` — ConfigurationError + namespace routing (legacy stack)

```elixir
defmodule ConfigurationError do
  @moduledoc "NGO/flow-author misconfiguration; routed to a separate AppSignal namespace."
  defexception [:message]
end

# report_to_appsignal picks the namespace from the exception struct type:
defp namespace_for(%ConfigurationError{}), do: "flow_webhook_config_errors"
defp namespace_for(_),                     do: "flow_webhooks"

def report_to_appsignal(exception, tags) do
  Glific.log_exception(exception, namespace: namespace_for(exception), tags: tags)
end
```

---

## 6. `lib/glific/flows/webhooks/core/errors.ex` — same ConfigurationError (new stack)

```elixir
defmodule ConfigurationError do
  @moduledoc "Webhook failure caused by NGO/flow-author misconfiguration."
  defexception [:message]
end
# (delete the old "ConfigurationError is intentionally absent" note)
```

---

## 7. `lib/glific/flows/webhooks/core/instrumentation.ex` — report sites call classify + report

```elixir
alias Glific.Flows.Webhooks.{ErrorClassifier, Registry}

# ── Site 1: sync / immediate-dispatch failure (from around/3) ────────────────
# NOTE the plumbing change: pass `module` + raw `result` (not just webhook_name + extracted bits).
defp maybe_report_failure(%{success: false} = result, module, ctx) do
  class = ErrorClassifier.classify(module, result)
  ErrorClassifier.report(class, result, tags_from(ctx, module))
end
defp maybe_report_failure(_ok, _module, _ctx), do: :ok

# ── Site 2: async callback failure (from resume) ─────────────────────────────
# No module in scope here → look it up from the webhook_name in the callback.
def report_callback_failure(%{"success" => s} = result, response) when s != true do
  module = Registry.lookup(response["webhook_name"])          # usually external → returns nil → heuristic
  class  = ErrorClassifier.classify(module, result)
  ErrorClassifier.report(class, result, tags_from(response, module))
end
def report_callback_failure(_result, _response), do: :ok

# ── Site 3: resume failure (stale / could-not-find-category) ─────────────────
# Glific owns these; supply the class directly (no module).
def report_resume_failure(response, reason) do
  result = %{"reason" => reason}
  class =
    cond do
      reason =~ ~r/does not have any active flows/ -> :stale     # suppress
      reason =~ ~r/Could not find category/        -> :config    # flow author
      true                                         -> :system
    end
  ErrorClassifier.report(class, result, tags_from(response, nil))
end

# ── Site 4: timeout (unchanged) — its own TimeoutError under flow_webhooks ────
```

---

## 8. `lib/glific/clients/common_webhook.ex` — legacy stack uses the SAME engine

```elixir
alias Glific.Flows.Webhooks.ErrorClassifier

defp report_webhook_failure(webhook_name, meta, http_status, reason) do
  result = %{"http_status" => http_status, "reason" => reason}
  class  = ErrorClassifier.classify(nil, result)   # no behaviour module on the legacy path
  ErrorClassifier.report(class, result, %{
    webhook_name: webhook_name,
    organization_id: meta[:organization_id],
    flow_id: meta[:flow_id],
    contact_id: meta[:contact_id]
  })
end
```

---

## 9. `lib/glific_web/flows/flow_resume_controller.ex:26` — delete the stray debug

```elixir
def flow_resume(%Plug.Conn{...} = conn, result) do
  # IO.inspect(result)   ← REMOVE
  response = result |> Webhook.parse_callback_response() |> Webhook.maybe_upload_tts_audio()
  run_supervised(fn -> Webhook.resume(organization_id, result, response) end)
  json(conn, "")
end
```

---

## Variant — typed return (kills string-matching in step 4)

If we adopt `@type sync_result :: ... | {:error, ErrorType.t(), String.t()}`, the module emits an
**atom** instead of matching its own prose, and `error_class/1` becomes trivial:

```elixir
# error_type.ex (NEW) — the atom → class map, one source of truth
defmodule Glific.Flows.Webhooks.ErrorType do
  @class %{
    kaapi_not_active: :system, missing_api_key: :system, tts_upload_failed: :system,
    invalid_json_body: :config, unknown_webhook_fn: :config, invalid_media_url: :config,
    assistant_not_found: :config, invalid_geocoding: :config, empty_input: :config,
    flow_category_unmatched: :config, stale_callback: :stale,
    rate_limited: :transient, service_unavailable: :transient
  }
  def class(type), do: Map.get(@class, type)
end

# call/2 returns {:error, :assistant_not_found, "Assistant not found: "}
# → result carries error_type: :assistant_not_found

# then the module override is message-proof:
def error_class(%{error_type: t}) when not is_nil(t), do: Glific.Flows.Webhooks.ErrorType.class(t)
def error_class(_), do: nil
```

Same flow, same `classify/2`/`report/3` — only the module's *input signal* changes from a fragile
string prefix to a stable atom. The engine heuristic stays as the fallback for external
(Kaapi/OpenAI/Gemini) errors until Kaapi sends `error_type` in its callback body.
```
