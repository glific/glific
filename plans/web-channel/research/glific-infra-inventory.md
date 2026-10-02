# Research — Glific testing, observability and deployment inventory

**Captured:** 2026-08-28 · Repos: `glific` (branch `master`) and `glific-frontend`

Ground truth for [tech-design.md](../tech-design.md) §4.12–4.14. This is what **already exists**, so
the plan extends it rather than reinventing it.

---

## 1. Observability

### 1.1 AppSignal is the whole APM story

No `config/appsignal.exs`. Config spans four files: `config/dev.exs:44` (`active: false`),
`config/test.exs:56` (`active: false`), `config/prod.exs:12` (`active: true`), and the real one:

```elixir
# config/runtime.exs:83-93
config :appsignal, :config,
  otp_app: :glific,
  name: "Glific",
  hostname: env!("APPSIGNAL_HOSTNAME", :string),
  active: env!("APPSIGNAL_ACTIVE", :boolean, false),
  revision: Application.spec(:glific, :vsn) |> to_string(),
  push_api_key: env!("APPSIGNAL_PUSH_API_KEY", :string!),
  ecto_repos: [],
  ignore_namespaces: ["gupshup_webhooks", "gupshup_enterprise_webhooks", "flow_editor_controller"],
  instrument_oban: false
```

Three things matter:

- **`ecto_repos: []`** — automatic Ecto instrumentation is deliberately off; DB timing is hand-rolled.
- **`instrument_oban: false`** — the built-in Oban integration is off; `Glific.Appsignal` handles Oban telemetry manually.
- **`ignore_namespaces`** — the three highest-volume request paths are excluded from APM sampling. A new
  web-channel namespace would **not** be excluded by default.

Sampling is global and env-driven (`appsignal_sampling_rate`, default 100). `Glific.Appsignal` gates
Oban and Tesla metrics behind `if :rand.uniform() < sampling_rate / 100`.

**Automatic instrumentation:** `lib/glific_web/router.ex:9` (`use Appsignal.Plug`) and
`lib/glific_web/endpoint.ex:4` (`AppsignalAbsinthePlug`, which renames every GraphQL request to a
single action `"GraphQL: " <> @path`).

**Explicit instrumentation:** `Appsignal.instrument/2` is used **nowhere**. Everything goes through
`increment_counter/3`, `add_distribution_value/3` and `set_gauge/3`, via an established convention of
per-domain instrumentation modules:

- `lib/glific/appsignal.ex` — the telemetry→AppSignal bridge
- `lib/glific/providers/instrumentation.ex` — `provider_send_count`, `provider_receive_count`, `provider_status_count`, `provider_action_count`, `gupshup_seconds_since_last_inbound`, `gupshup_inbound_stale`
- `lib/glific/jobs/instrumentation.ex` — `job_run_count`
- `lib/glific/flows/webhooks/core/instrumentation.ex` — `flow_webhook_count`, `flow_webhook_latency`, `kaapi_llm_latency`
- `lib/glific/third_party/bigquery/instrumentation.ex` — `bigquery_sync_count`

**Namespacing convention:** `Glific.Appsignal.set_namespace/1` is called from each provider shunt
(`gupshup/plugs/shunt.ex:113`, `maytapi/shunt.ex:88`, `gupshup_enterprise/shunt.ex:67`,
`flow_editor_controller.ex:35`). **This is the pattern a web-channel socket should follow.**

### 1.2 Telemetry

Eight `:telemetry.execute` call sites, all `[:glific, …]`:

| Event | File:line | Measurements |
|---|---|---|
| `[:glific, :flow, :node]` | `flows/node.ex:267` | `%{}` |
| `[:glific, :flow, :stop]` | `flows/flow_context.ex:269` | `%{}` |
| `[:glific, :flow, :stop_all]` | `flows/flow_context.ex:631` | `%{}` |
| `[:glific, :flow, :start]` | `flows/flow_context.ex:786` | `%{duration: 1}` |
| `[:glific, :message, :sent]` | `communications/message.ex:65` | `%{duration: 1}` |
| `[:glific, :message, :received]` | `communications/message.ex:233` | `%{duration: 1}` |
| `[:glific, :wa_message, :sent]` | `communications/wa_group_message.ex:59` | `%{duration: 1}` |
| `[:glific, :wa_message, :received]` | `communications/wa_group_message.ex:230` | `%{duration: 1}` |

⚠️ `duration: 1` is a placeholder — source comments say *"currently we are not measuring latency"*.
**There is no real end-to-end latency measurement anywhere in Glific.**

**Handlers attached at boot** (`lib/glific/application.ex:120-190`), all → `Glific.Appsignal.handle_event/4`
except the mailer: `[:oban, :job, :exception]`, `[:oban, :plugin, :exception]`, `[:oban, :job, :stop]`,
`[:tesla, :request, :stop|:exception]`, `[:swoosh, …]` → `Mailer`, `[:glific, :repo, :query]`,
`[:glific, :repo_replica, :query]`.

> ⚠️ **Critical gap: none of the eight `[:glific, …]` application events have a permanently attached
> handler.** They are consumed only by LiveDashboard, dynamically, while the page is open. In
> production they fire into the void.

`lib/glific_web/telemetry.ex` is supervised and runs `telemetry_poller` at 60 s with exactly one
measurement — `{Glific.Appsignal, :send_oban_queue_size, []}`. The `metrics/0` list is defined but
**the reporter is commented out**, so `metrics/0` is consumed only by LiveDashboard.

**LiveDashboard is mounted in all environments** (`router.ex:95-98`) behind HTTP basic auth
(`AUTH_USERNAME`/`AUTH_PASSWORD`); the "only for development" comment above it is stale. It is an
immediately useful surface for live socket and process inspection.

**Repo instrumentation** (`appsignal.ex:117-127`) is the best template: per-repo distributions
`glific.repo.query_time` (tagged by SQL command), `glific.repo.idle_time`, `glific.repo.queue_time`,
counter `glific.repo.query_count`, and `glific.repo.db_connection_error` tagged by classified reason.

### 1.3 Logging, errors, alerting, health

- **Logging:** `format: "$time $metadata[$level] $message\n"`, metadata `[:request_id, :user_id, :org_id, :params]`.
  Plain text, **no structured logging**. Prod `:info`; test `:emergency` with compile-time purge.
  **No log aggregation on the backend** — only what Gigalixir provides. (`VITE_LOGFLARE_*` keys are frontend-only.)
- **Errors:** no Sentry/Honeybadger on the backend; AppSignal handles all. House convention
  (`lib/glific/CLAUDE.md:99`): *"Never call `Appsignal.send_error`/`Appsignal.error` directly"* — use
  `Glific.log_error/2`, which filters known-benign errors via `ignore_error?/1`. Oban failures surface
  via `handle_event([:oban, action, :exception], …)`, but the error is attached to the span **only when
  the job has exhausted retries** (`if meta.attempt >= meta.max_attempts`).
  **Frontend does have Sentry** (`@sentry/react` 10.30.0) plus PostHog.
- **Alerting: Discord webhooks**, in three places — in-app notifications (`third_party/discord.ex`),
  the weekly SAFE analysis workflow, and deploy verification. **One** AppSignal CheckIn cron exists
  (`minute_worker.ex:99`, `"glific_stats_hourly"`). **No alert rules or dashboards are version-controlled** —
  they live in the AppSignal UI.
- **Health checks: no `/health` or readiness endpoint.** The only unauthenticated GET at root is the
  landing page. Uptime is monitored indirectly by **Instatus** — `cypress-smoke.yml` runs
  `smoke.spec.ts` against production **every 27 minutes** and pushes `OPERATIONAL`/`MAJOROUTAGE`.
  `bin/gigalixir-verify-deploy.sh` is a careful 3-phase deploy verifier with a 300 s stability window.

### 1.4 Channels / sockets / Presence

**None — and there is nothing to monitor, because there are no Phoenix Channels on `master` at all.**

- `lib/glific_web/channels/user_socket.ex` is **not** a `Phoenix.Socket` — it is
  `use Absinthe.GraphqlWS.Socket`, a GraphQL-subscriptions transport only.
- `endpoint.ex:19-24` declares one app socket (`/socket`, subprotocol `graphql-transport-ws`) plus
  `/live` for LiveDashboard.
- **`Phoenix.Presence`: zero occurrences in `lib/`.**
- **`use Phoenix.Channel`: one occurrence** — unused generator boilerplate at `glific_web.ex:82`.
- No `phoenix.channel_joined` / `socket_connected` handlers, no connected-socket gauge, no join/leave counters.

---

## 2. Testing — backend

`test/test_helper.exs` is three lines. **233 test files.** Case templates in `test/support/`:
`data_case.ex`, `conn_case.ex`, **`channel_case.ex`**, `fixtures.ex`, `webhook_test_helpers.ex`, `ex_vcr/`.

> **`GlificWeb.ChannelCase` exists and has zero users.** `grep -rn "ChannelCase" test/` outside
> `test/support/` returns exactly one hit — a documentation row in `test/CLAUDE.md:17`. A web-channel
> suite would be its **first** consumer.

**Mocking:** `Tesla.Mock` is the standard (`config/test.exs:29`), used in **85 test files**. ExVCR for
Stripe/billing (3 files). **Mox: no. Bypass: no.** `config/test.exs:23` swaps the Poolboy worker for
`Glific.Processor.ConsumerWorkerMock`; `config :goth, disabled: true`; Swoosh uses `Adapters.Test`.
Per `test/CLAUDE.md`, the org default in every test is `organization_id: 1`, and `async: true` is only
allowed when the test touches no shared global state.

**Coverage:** ExCoveralls, `test_coverage: [tool: ExCoveralls, test_task: :test_full]`.
`coveralls.json` has ~60 `skip_files` entries and `"minimum_coverage": 85`. `codecov.yml` sets
**project target 88.25%, threshold 0.5%**, patch threshold 1%, `if_ci_failed: error`,
`informational: false` — an enforcing gate.

> ⚠️ **`lib/glific_web/channels/user_socket.ex`, `endpoint.ex`, `router.ex`, `plugs/` and `schema/`
> are all in `skip_files`** — so web-channel code placed under `lib/glific_web/channels/` escapes the
> gate unless the list is edited.

**CI — `.github/workflows/`, 5 workflows.** `continuous-integration.yml` runs on push to master and
all PRs, matrix pinned to `elixir 1.18.3` / `otp 27.3.3`, four jobs: `setup` (deps + PLT caches),
`code-quality` (`mix check`), `tests` (`mix coveralls.json --max-cases 2` → `codecov-action@v7`,
Postgres 13 service), `compile` (`--warnings-as-errors`).

`.check.exs` **disables more than the root `CLAUDE.md` implies**:

```elixir
{:sobelow, false},
{:mix_audit, false},
{:npm_test, false},
{:formatter, false},
{:credo, "mix credo --format oneline --strict"},
{:ex_unit, false},          # separate GH action
{:mix_format, "mix format"},
{:dialyzer, "mix dialyzer --quiet", detect: [{:package, :dialyxir}]}
```

So `mix check` = compiler + credo --strict + mix format + dialyzer + doctor (`.doctor.exs` requires
**100%** module-doc/doc coverage). **Sobelow does NOT run in CI** despite being a dependency with a
`.sobelow-conf` — contradicting the root `CLAUDE.md`.

**`cypress-tests.yml`** — full-stack e2e lives in the *backend* repo too. It checks out the backend,
`git clone`s `glific/glific-frontend`, boots Postgres 14 + `mix setup` + `mix phx.server` (HTTPS on
`glific.test:4001`) + `yarn dev`, opens an **ngrok tunnel** to expose port 4000 publicly and feeds the
URL back as `GLIFIC_API_HOST_OVERRIDE` (so BSP webhooks reach the runner), then runs Cypress sharded
3 ways via `cypress-split`, recording to the Cypress Dashboard. Two specs excluded:
`filesearch/Filesearch.spec.ts` and `smoke.spec.ts`.

**`safe-check.yml`** — weekly (Mon 02:30 UTC), Erlang Solutions' proprietary **SAFE** static analyser
against the built `_build`. Discord alert on failure. **`stale.yml`** closes PRs inactive 30 days.

**Load / performance / benchmark tooling: definitively none.** No benchee, k6, artillery, locust, no
`bench/` directory, no custom mix task. The closest existing things are *data-seeding* tasks
(`ecto.scale`, `ecto.scale_2`). **Any websocket load test is greenfield.**

**Security scanning:**

| Tool | Status |
|---|---|
| Sobelow | dependency present, **disabled in `mix check`, not run in any workflow** |
| `mix_audit` | **no** — explicitly `false` in `.check.exs` |
| `mix hex.audit` | **no** — never invoked |
| CodeQL | **no** |
| Dependabot | **yes** — `mix` weekly (limit 5, minor+patch grouped), `github-actions` monthly |
| SAFE | **yes** — weekly |
| Codacy / CodeBeat / CodeRabbit | config files present; external services, not CI jobs |

---

## 3. Testing — frontend (`glific-frontend`)

**Vitest** (`^4.0.15`), jsdom, coverage provider **istanbul**, Testing Library 16.3.
**208 test files** under `src/`. Codecov project target **81.5%**, patch threshold 0%.

### Playwright vs Cypress — it's Cypress

**Playwright: no.** Not in `package.json`, not in `yarn.lock`, no config in either repo.

**Cypress: yes, extensive and mature.** `cypress@^15.15.0` + `cypress-split@^1.24.28`.
~24 specs under `cypress/e2e/`, organised by feature area:

```
auth/{ForgotPassword,Login,Logout,Registration}.spec.ts
chat/{Chat,ChatCollection,Search}.spec.ts
collection/ contactBar/ contactImport/ filesearch/
flow/{Flow,FlowEditor}.spec.ts
interactiveMessage/ roles/staff/ search/ setting/ simulator/
staffmanagement/ template/ trigger/ waForms/ waGroup/  smoke.spec.ts
```

Support layer `cypress/support/{commands.js,commands.d.ts,chats.js,collection.js,flow.js,e2e.js}`
declares ~25 typed custom commands — `sendTextMessage`, `sendImageAttachment`, `sendAudioAttachment`,
`startFlow`, `closeSimulator`, `verifyLastMessageTimestamp`, `jumpToLatest`, … **The message-sending
and attachment commands are directly analogous to what a widget suite needs.**

Two auth paths: `login` (API-based — POST `/v1/session`, then seed `localStorage` with
`glific_session` and `glific_user`) and `appLogin` (UI-based, used by the prod smoke test).
Config: viewport 1366×768, `defaultCommandTimeout: 8000`, `retries: { runMode: 2 }`, `video: false`.
`cypress.config.ts` is **gitignored**; CI copies `cypress.config.ts.example`.

| Workflow | Trigger | What |
|---|---|---|
| `unit-testing.yml` | push master, PRs | `yarn test:coverage` → Codecov |
| `e2e-tests.yml` | push master, PRs, dispatch | mirror of the backend rig, inverted: clones `glific/glific`, ngrok, `mix setup`, Cypress **sharded 3×**, Dashboard recording |
| `e2e-tests-slow.yml` | PRs labelled `e2e-slow` | same rig, unsharded, `filesearch` only |
| `cypress-smoke.yml` | **cron `*/27 * * * *`** | `smoke.spec.ts` against **production** → Instatus |

> **A browser e2e suite for the web channel is an extension, not greenfield — but the existing rig is
> Cypress.** The genuinely new problem either way is that the widget lives in a **third** repo
> (`glific-web-channel`) that neither existing rig clones.

---

## 4. Environments and deployment

**Target: Gigalixir, buildpack (not Docker).** `.buildpacks` lists heroku-apt, gigalixir-elixir,
gigalixir-phoenix-static, gigalixir-releases. `elixir_buildpack.config`: `erlang_version=27.3.3`,
`elixir_version=1.18.3`, `hook_pre_compile="./download_ffmpeg.sh"`, `hook_post_compile="mix assets.deploy"`.
**No `fly.toml`, no `Procfile`.** The `Dockerfile` + `docker-compose.yaml` are **local-dev only**.

**Staging exists.** Three Gigalixir apps, declared in `bin/gigalixir-release.sh`:

```
staging|glific-staging|staging
frontend-staging|glific-frontend-staging|gigalixir
production|glific|production
```

`continuous-deployment.yml` deploys on push to `master` **or** a PR labelled `staging`, via
`gigalixir-action@v0.6.2`, with **`MIGRATIONS: false`**, then runs `bin/gigalixir-verify-deploy.sh`
with a 20-minute timeout. Production is manual and versioned (version bump → PR → squash-merge →
GitHub release → `git push production master:master` → verify; requires typing the app name).
Frontend also gets Netlify PR previews pointed at `api.staging.glific.com`.

> **Performance tests on staging are viable.** Caveats: `MIGRATIONS: false` means schema changes need a
> manual step, and staging's replica count and DB tier are not in the repo — confirm before treating a
> result as predictive of production.

**Runtime config** (`config/runtime.exs`, via Dotenvy):

| Variable | Default | Notes |
|---|---|---|
| `HTTP_PORT` | 4000 | |
| `DATABASE_URL` | required | |
| `READ_REPLICA_DATABASE_URL` | falls back to primary | |
| `POOL_SIZE` | **20** | applied to **both** Repo and RepoReplica |
| `HACKNEY_POOL_SIZE` | 50 | plus a fixed 50-conn `:kaapi_upload_pool` |
| `USE_REPLICA_DB` | false | only switches `Glific.Searches` |
| `REQUEST_ORIGIN`, `REQUEST_ORIGIN_WILDCARD` | required | → `check_origin` |
| `MAX_RATE_LIMIT_REQUEST` | 180 | |
| `ENABLE_DB_SSL` | true | verify_peer, CA cert written to `priv/cert` at boot |
| `GUPSHUP_WEBHOOK_IPS` | **required in prod — the app refuses to boot without it** | |

> ⚠️ **`REQUEST_ORIGIN`/`REQUEST_ORIGIN_WILDCARD` feed `check_origin`, and `check_origin` governs
> WebSocket upgrades.** A widget embedded on arbitrary third-party domains will be rejected unless the
> web-channel socket declares its own `check_origin`.

### Clustering — none. This is the blocker.

- **`libcluster`: not a dependency. `dns_cluster`: not a dependency.** Zero hits in `mix.exs`,
  `mix.lock`, `config/`, `lib/`. No `Cluster.Supervisor` in the supervision tree.
- `rel/env.sh.eex` — distribution is **commented out**:
  ```sh
  # export RELEASE_DISTRIBUTION=name
  # export RELEASE_NODE=<%= @release.name %>@127.0.0.1
  ```
- `rel/vm.args.eex` — every line commented, **including `##+Q 65536`** ("Increase number of concurrent
  ports/sockets"). The port/socket limit has not been raised.
- `application.ex:24` — `{Phoenix.PubSub, name: Glific.PubSub}` with **no `:adapter`**, i.e. default
  `Phoenix.PubSub.PG2`. PG2 broadcasts across *connected BEAM nodes* — and with `RELEASE_DISTRIBUTION`
  unset, nodes never connect.

> **Consequence: PubSub is effectively node-local.** `Absinthe.Subscription` rides the same PubSub.
> Today this is invisible because Glific runs **one replica** (confirmed 2026-08-30). The moment it
> runs more than one, a message published on node A will not reach a socket held on node B — for the
> web channel *and* for staff GraphQL subscriptions.

**Database:** pool **20** per repo per node; no `queue_target`/`queue_interval` tuning.
`prepare: :named`, `parameters: [plan_cache_mode: "force_custom_plan"]` on both repos — a deliberate
multi-tenant planning choice. **Read replica exists** (`Glific.RepoReplica`, `read_only: true`,
started in the supervision tree) but adoption is narrow — `USE_REPLICA_DB` only redirects
`Glific.Searches`. **PgBouncer: no.** Oban runs in the `global` Postgres schema.

---

## 5. Blockers for the plan

1. **`Phoenix.PubSub` has no distributed adapter and release distribution is disabled.** Highest
   priority for the scaling section. Latent at one replica; a correctness bug at two.
2. **Zero load/performance tooling.** The websocket load-test harness is entirely greenfield.
3. **No Phoenix Channel, Socket or Presence monitoring — and no Phoenix Channels at all.** Every socket
   metric must be built. `Glific.Appsignal` + the `*/instrumentation.ex` modules give a clean pattern.
4. **No `/health` or readiness endpoint.** Needed if load-balancer socket draining is ever wanted.
5. **The eight `[:glific, …]` telemetry events have no permanent handler.** New events without an
   `attach` in `application.ex` produce nothing in production.
6. **`check_origin` is env-driven and gates WebSocket upgrades.** A widget on customer domains needs an
   explicit per-socket decision.
7. **`+Q` is commented out** — the default BEAM port limit caps concurrent websockets.
8. **`lib/glific_web/channels/` is in `coveralls.json`'s `skip_files`** — new code escapes the 88.25% gate.
9. **Sobelow does not actually run in CI**, and there is no dependency-vulnerability audit.
10. **Playwright would fork the e2e tooling.** Cypress is deeply established: 24 specs, a typed
    25-command support layer, two symmetrical cross-repo CI rigs with ngrok + sharding + Dashboard
    recording, and a 27-minute production smoke test wired to Instatus.
11. **Staging exists and is viable**, but `MIGRATIONS: false` and its unverified replica count/DB tier
    are caveats on any result measured there.
