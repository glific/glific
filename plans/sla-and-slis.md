# API availability SLI (increment 1)

Goal: an overall API availability SLI plus per-GraphQL-operation SLIs, using AppSignal only.
Later increments (message pipeline latency, queue metrics, DB pool) get their own sections once
this one ships.

## Decisions

- **AppSignal only.** Grafana Cloud was evaluated and dropped: Glific routes organizations by
  subdomain, so off-the-shelf HTTP metrics carry a per-org `host` label, and pushing metrics out
  of Gigalixir needs extra infrastructure.
- **No reliance on request tracing for SLIs.** ~50M API requests/month exceed the AppSignal plan,
  so SLIs come from custom metrics (counters/distributions), not per-request transactions.
- **Fixed thresholds, counted at source.** AppSignal distributions keep only per-minute
  mean/p90/p95, so a monthly "% under N seconds" cannot be derived later. Each event is classified
  `good`/`bad` when it happens and counted.

## 1. Server up: external probe

- New `GET /health`: runs `SELECT 1` on `Glific.Repo`, returns `200 ok` or `503`. No auth, no
  rate limit; added to AppSignal `ignore_actions` so probes don't create transactions.
- AppSignal Uptime Monitor on `https://api.<root host>/health`, every minute, multiple regions.
  The root host maps to the `glific` organization in `GlificWeb.SubdomainPlug`; a host with no
  resolvable subdomain gets a 404 from that plug, so the probe must not use the bare Gigalixir
  hostname.
- Runs on AppSignal's infrastructure, so it keeps reporting when the app is down.

## 2. API SLIs: custom metrics

| Metric | Type | Tags | Source event |
|---|---|---|---|
| `api_request_count` | counter | `route` (router pattern), `result` (`good`/`bad`) | `[:phoenix, :router_dispatch, :stop]` and `:exception` |
| `graphql_operation_count` | counter | `entrypoint`, `outcome` (`ok`/`error`/`invalid`/`exception`), `result` (`good`/`bad`) | `[:absinthe, :execute, :operation, :stop]`, plus crash handling below |
| `graphql_operation_duration` | distribution (ms) | `entrypoint` | same |
| `graphql_operation_duration_all` | distribution (ms) | none | same; platform-wide p95 (AppSignal cannot merge percentiles across tag values) |

Classification:

- **HTTP `bad`**: 5xx status or an exception. 4xx is the client's problem and stays `good`.
- **GraphQL `bad`**: `exception`, or latency above the operation's threshold. `error`
  (resolver returned `{:error, _}`, e.g. not found) and `invalid` (validation) are user errors and
  stay `good`, but are tagged so they can be watched.
- **`entrypoint`**: the schema identifier of the first root field (e.g. `create_flow`), taken from
  the parsed document, never the client-supplied `operationName`. An allow-list of key operations
  keeps its own value; everything else is `other`.

Initial allow-list and thresholds (to be tuned from two weeks of data):

| Entrypoints | Threshold |
|---|---|
| `create_flow`, `update_flow`, `publish_flow` | 3s |
| `create_trigger`, `update_trigger`, `start_contact_flow`, `start_group_flow` | 2s |
| `create_and_send_message`, `send_hsm_message`, `create_and_send_message_to_group` | 2s |
| `contacts`, `search` (conversation list) | 1s |
| `other` | 5s |

### Crashes

Absinthe's `[:absinthe, :execute, :operation, :stop]` is emitted by the last pipeline phase, so it
never fires when a resolver raises. To count crashes against their operation:

1. A pipeline phase (added through `Absinthe.Plug`'s `:pipeline` option, after validation) stores
   the resolved `entrypoint` in the process dictionary.
2. The `[:phoenix, :router_dispatch, :exception]` handler reads it and records
   `outcome: exception`, `result: bad`.

## 3. Reading the SLIs

- **Overall API availability (month)** = minutes where the probe passed and
  `api_request_count{result: bad}` ≤ 5% of total, divided by minutes in the month.
- **Per-operation SLI (month)** = `graphql_operation_count{entrypoint: X, result: good}` ÷ total
  for `X`, pulled from the AppSignal API.
- **Alerts**: uptime monitor failure; `api_request_count{result: bad}` rising; per-entrypoint
  `bad` count above baseline.

## Open questions

- Do custom metrics count toward the AppSignal request quota, and how are tag combinations
  billed? (Decides whether this stays in AppSignal long-term.)
- Retention of custom metrics at minute/hour resolution — needed for monthly reports.
