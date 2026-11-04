# Web / worker node split — POC

Issue #6082 · Epic #5803

## 1. Model

Two Gigalixir apps built from the same release, clustered over Erlang distribution:

- **`glific`** (web) — serves HTTP and websockets, inserts Oban jobs, executes none.
- **`glific-oban`** (worker) — executes every Oban queue and runs the plugins (Cron, pruner,
  lifeline). `GlificWeb.Endpoint` runs with `server: false` (it is still needed for PubSub and
  subscription publishing), and port 4000 is served by `GlificWeb.Plugs.HealthCheck` alone,
  because Gigalixir only adds replicas that answer on port 4000 to the cluster DNS name. Neither
  the API nor its websockets are reachable on the worker's public `*.gigalixirapp.com` domain.

Phoenix.PubSub (and so Absinthe subscriptions, web channel rooms and Presence) works across the
cluster with the default adapter, so a job on the worker pushes updates to sockets on the web app.

## 2. Configuration

| Env var | Where | Effect |
|---|---|---|
| `NODE_ROLE=web` | web app | Oban starts with `queues: false, plugins: false, peer: false` |
| `NODE_ROLE=worker` | worker app | Oban runs as today; endpoint not served; `HTTP_PORT` answers `GET /health` only |
| `NODE_ROLE` unset | dev, test, single-app deploys | everything as today |
| `CLUSTER_QUERIES` | both apps | `basename=hostname` pairs for `DNSCluster`; unset disables clustering |
| `ERLANG_COOKIE` | both apps | must be identical |

`peer: false` on the web app matters: the Oban leader runs the plugins, so a web node winning
leadership would stop Cron everywhere.

Gigalixir's own `DNS_CLUSTER_QUERY` only resolves the current app's replicas, so it is not used.
Each app's internal DNS name is `<GIGALIXIR__EPMD_SERVICE>.<app>.svc.cluster.local`, and the
replicas are named `<app>@<pod IP>` (Gigalixir support, ticket 6488). Production `glific`'s
service is `epmd-1fpmc0c-55504fm`.

## 3. Running locally

`dns_cluster` resolves through DNS, not `/etc/hosts`, so `localhost` does not resolve.
`localtest.me` is a public DNS name that points to `127.0.0.1`.

```bash
mix compile
```

```bash
NODE_ROLE=web CLUSTER_QUERIES=web=localtest.me,worker=localtest.me \
  elixir --name web@127.0.0.1 --cookie glific -S mix phx.server
```

```bash
NODE_ROLE=worker CLUSTER_QUERIES=web=localtest.me,worker=localtest.me HTTP_PORT=4100 \
  elixir --name worker@127.0.0.1 --cookie glific -S mix phx.server
```

The frontend keeps pointing at the web node (`https://glific.test:4001`). The worker only answers
`http://localhost:4100/health`; it starts no HTTPS listener and no asset watchers. Two nodes use
two DB pools, so lower `POOL_SIZE` / `REPLICA_POOL_SIZE` if Postgres runs out of connections.

Checks, from either node's IEx:

```elixir
Node.list()
# web
Oban.config().queues          # []
Oban.config().peer            # false
# worker
Oban.check_queue(queue: :default)
```

## 4. Rollout

Both apps run the same release from the same commit. The releases buildpack starts whatever
release it builds (ours is `prod`), so the worker app needs no Procfile or release changes.
Do staging first (`glific-staging` + `glific-staging-oban`), then production (`glific` +
`glific-oban`). Every step can be undone on its own, and the web app keeps working throughout.

1. **Ship the code with nothing set.** Merge to master. With `NODE_ROLE` and `CLUSTER_QUERIES`
   unset, the app behaves as before.

2. **Create the worker app with the web app's config.** It must be in the same cloud and region
   for the two apps to reach each other.

   ```bash
   gigalixir create -n glific-staging-oban --cloud gcp --region us-central1
   gigalixir config:copy -s glific-staging -d glific-staging-oban
   gigalixir config:set -a glific-staging-oban NODE_ROLE=worker APPSIGNAL_HOSTNAME=glific-staging-oban
   ```

   Keep the copied `GIGALIXIR_APP_NAME`: the `custom_certificate` queue now runs on the worker and
   adds custom domains through the Gigalixir API, and those domains belong to the web app.

3. **Share the cookie and deploy the worker.** Add the repository variable (not a secret, so the
   job's `if` can read it) `GIGALIXIR_WORKER_APPNAME=glific-staging-oban`; from then on the
   `deploy-worker` job in `continuous-deployment.yml` deploys the same commit to the worker with
   the deploy action and verifies it, in parallel with the web app. Deploy once by hand, or re-run CI.

   ```bash
   gigalixir config:set -a glific-staging      ERLANG_COOKIE=<long-random-value>
   gigalixir config:set -a glific-staging-oban ERLANG_COOKIE=<long-random-value>
   ```

   Both apps now run jobs, which Oban handles, and they are not clustered yet.

4. **Cluster them.** Read each app's service name from a remote console
   (`gigalixir ps:remote_console -a <app>`, then `System.get_env("GIGALIXIR__EPMD_SERVICE")`) and
   set the same value on both apps:

   ```bash
   CLUSTER_QUERIES=glific-staging=<web service>.glific-staging.svc.cluster.local,glific-staging-oban=<worker service>.glific-staging-oban.svc.cluster.local
   ```

   Check `Node.list()` on each app shows the other.

5. **Stop jobs on the web app.**

   ```bash
   gigalixir config:set -a glific-staging NODE_ROLE=web
   ```

   Check: jobs show `attempted_by` worker nodes, Cron runs once a minute, bot replies appear in the
   chat screen, a republished flow takes effect. Rollback is `gigalixir config:unset -a
   glific-staging NODE_ROLE`.

6. **Size each app.** Scale the worker for job throughput (`gigalixir ps:scale -a
   glific-staging-oban --size … --replicas …`) and the web app for requests. Set `POOL_SIZE` and
   `REPLICA_POOL_SIZE` per app so that, across all replicas of both apps, connections stay under
   Cloud SQL `max_connections`.

Migrations keep running from the web app only, as today.

Before production:

- Add the worker apps to `TARGETS` in `bin/gigalixir-release.sh` and
  `bin/gigalixir-verify-deploy.sh` (they must stay in sync), so a production release pushes and
  verifies both apps from the same commit.
- Confirm with Gigalixir whether their health check is a TCP connect or an HTTP request, and if
  HTTP, which path. The worker answers `200` on `/` and `/health` either way.
- If Cloud SQL restricts client IPs, confirm the worker app's egress IP is allowed.

## 5. Known gaps

- **Cachex is per node.** `Glific.Caches.Replicator` copies `set`/`remove` to the other nodes over
  PubSub, so a flow published on web reaches the worker. `put_global` (org index, media
  validation, Kaapi models) stays per node; the org index refreshes itself every minute.
- **Pow sessions (Mnesia) and `Glific.State`** stay on the web node. Fine while only web requests
  use them; #5822 moves sessions to the DB.
- **DB connections.** `POOL_SIZE` is per app; both apps together must fit Cloud SQL
  `max_connections`.
- **Dev mailbox.** `Swoosh.Adapters.Local` registers its storage globally, so two clustered dev
  nodes log a `global: Name conflict` for it on connect. Dev only; prod uses a different adapter.