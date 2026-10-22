# Platform SLAs and usage metrics

Thresholds marked
**X** are set after two weeks of baseline data.

## SLAs

| # | SLA | Target | Good event | Measured from |
|---|---|---|---|---|
| 1 | API uptime | 99.9% / month | Request answered with a non-5xx status, and an external probe of `/health` succeeds | Every HTTP request + external probe every minute |
| 2 | API response time | 99.9% of requests < **X** s | Request completes in under X seconds | Every HTTP request (server-side duration) |
| 3 | Flow processing latency | 99.9% of inbound messages < **X** s | Inbound message tagged and its flow step run within X seconds | `message.inserted_at` → `Processor.MessageWorker` completes |
| 4 | Gupshup outbound latency | 99.9% of session messages < **X** s | Message accepted by Gupshup within X seconds of creation | `message.inserted_at` → `sent_at` set in `Communications.Message.handle_success_response/2` |

Definitions:

- **Window**: calendar month. 99.9% allows ~43 minutes of downtime, or 0.1% of events over
  the threshold.
- **Uptime (1)** combines two signals: the probe catches "server unreachable", request status
  catches "server up but failing". A minute is down if the probe failed or more than 5% of that
  minute's requests returned 5xx.
- **4xx responses** are client errors and count as good.
- **Response time (2)** applies to all routes; slow-by-design routes (exports, uploads) are
  listed as exclusions or get their own threshold.
- **Flow processing (3)** starts at `inserted_at`, so it includes webhook handling, the queue
  wait in `gupshup_inbound` and flow execution. Messages that time out or crash count as bad.
- **Outbound latency (4)** covers session (non-template) messages only. HSM/template and broadcast
  sends are deliberately paced by the per-org BSP rate limit and broadcast batching, so they are
  tracked as a metric, not an SLA. Timing starts at `inserted_at`, not the Oban job, because
  rate-limited jobs snooze and Oban's queue time resets on each snooze.

Exclusions (apply to every SLA):

- Outages of Meta/WhatsApp and Gupshup.
- NGO-owned webhooks, LLM providers, Google services called from flows.
- Planned maintenance announced 48h ahead.

## Usage metrics

| Metric | Breakdown | Purpose |
|---|---|---|
| API calls | REST route; GraphQL entrypoint | Which endpoints are used, and whether only by Glific's own apps or also by external integrations |
| Active websocket connections | socket type | Load and capacity on persistent connections |
| Websocket messages | socket type, direction (inbound/outbound) | Traffic over persistent connections |

Socket types:

- `graphql_ws` — `GlificWeb.UserSocket` at `/socket` (frontend GraphQL subscriptions).
- `web_channel` — `GlificWeb.WebChannelSocket` at `/web_socket` (web channel widget,
  `RoomChannel`).

Websocket message direction:

- Inbound: client → server frames (`RoomChannel.handle_in/3`; GraphQL-WS client messages).
- Outbound: server → client pushes (channel `push`/broadcasts; GraphQL subscription publishes).

GraphQL **entrypoint** is the schema identifier of the operation's first root field (e.g.
`create_flow`), read from the parsed document, never the client-supplied `operationName`.

## Common dimensions

Every API and websocket metric carries:

| Dimension | Values |
|---|---|
| `client` | `glific_frontend`, `web_channel`, `external`, `bsp_webhook` |
| `route` / `entrypoint` | Router pattern for REST; GraphQL entrypoint for `/api` |
| `status_class` | `2xx`, `3xx`, `4xx`, `5xx` (HTTP only) |
| `organization_id` | For drill-down; not used in platform-wide SLA figures |

How `client` is determined, in order:

1. Route: BSP webhook paths (`/gupshup`, `/gupshup-enterprise`, `/maytapi`) → `bsp_webhook`;
   `/web_socket` and `/api/v1/web_channel/*` → `web_channel`.
2. An explicit `x-glific-client` request header sent by the Glific frontend → `glific_frontend`.
   Requires a one-line change in the frontend's Apollo/HTTP client.
3. Until the header ships: `Origin` matching `REQUEST_ORIGIN` / `REQUEST_ORIGIN_WILDCARD`
   → `glific_frontend`.
4. Anything else → `external`.

## What the codebase needs

- `GET /health` — DB check, `200`/`503`, for the external probe.
- One structured record per HTTP request (method, route, entrypoint, status, duration, client,
  organization) from `[:phoenix, :endpoint, :stop]`, replacing Phoenix's default two-line request
  log.
- GraphQL entrypoint captured after parsing (Absinthe pipeline phase) so crashes are attributed
  to their operation.
- Timing at the end of `Processor.MessageWorker.perform/1` and in
  `Communications.Message.handle_success_response/2`.
- Connection and message counters in `UserSocket` and `WebChannelSocket` / `RoomChannel`.

## Open decisions

- Values for each **X**.
- Whether response time (2) applies to all routes or a named set of key routes/operations.
- Whether the probe-based and request-based uptime signals are published separately or combined.
