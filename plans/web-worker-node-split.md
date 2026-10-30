# Web / worker node split — POC

Issue #6082 · Epic #5803

## 1. Model

Two Gigalixir apps built from the same release, clustered over Erlang distribution:

- **`glific`** (web) — serves HTTP and websockets, inserts Oban jobs, executes none.
- **`glific-oban`** (worker) — executes every Oban queue and runs the plugins (Cron, pruner,
  lifeline). Its endpoint keeps serving on port 4000 because Gigalixir only adds replicas that pass
  the port 4000 health check to the cluster DNS name.

Phoenix.PubSub (and so Absinthe subscriptions, web channel rooms and Presence) works across the
cluster with the default adapter, so a job on the worker pushes updates to sockets on the web app.

## 2. Configuration

| Env var | Where | Effect |
|---|---|---|
| `NODE_ROLE=web` | web app | Oban starts with `queues: false, plugins: false, peer: false` |
| `NODE_ROLE` unset or `worker` | worker app, dev, test | Oban runs as today |
| `CLUSTER_QUERIES` | both apps | `basename=hostname` pairs for `DNSCluster`; unset disables clustering |
| `ERLANG_COOKIE` | both apps | must be identical |

`peer: false` on the web app matters: the Oban leader runs the plugins, so a web node winning
leadership would stop Cron everywhere.

Gigalixir setup, from support (ticket 6488):

```
gigalixir create -n glific-oban --cloud gcp --region us-central1
gigalixir config:set -a glific      ERLANG_COOKIE=<same> NODE_ROLE=web    CLUSTER_QUERIES=<below>
gigalixir config:set -a glific-oban ERLANG_COOKIE=<same> NODE_ROLE=worker CLUSTER_QUERIES=<below>

CLUSTER_QUERIES=glific=epmd-1fpmc0c-55504fm.glific.svc.cluster.local,glific-oban=<GIGALIXIR__EPMD_SERVICE of glific-oban>.glific-oban.svc.cluster.local
```

Gigalixir's own `DNS_CLUSTER_QUERY` only resolves the current app's replicas, so it is not used.

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
NODE_ROLE=worker CLUSTER_QUERIES=web=localtest.me,worker=localtest.me HTTP_PORT=4100 HTTPS_PORT=4101 \
  elixir --name worker@127.0.0.1 --cookie glific -S mix phx.server
```

The frontend keeps pointing at the web node (`https://glific.test:4001`).

Checks, from either node's IEx:

```elixir
Node.list()
# web
Oban.config().queues          # []
Oban.config().peer            # false
# worker
Oban.check_queue(queue: :default)
```

## 4. Known gaps

- **Cachex is per node.** `Glific.Caches.Replicator` copies `set`/`remove` to the other nodes over
  PubSub, so a flow published on web reaches the worker. `put_global` (org index, media
  validation, Kaapi models) stays per node; the org index refreshes itself every minute.
- **Pow sessions (Mnesia) and `Glific.State`** stay on the web node. Fine while only web requests
  use them; #5822 moves sessions to the DB.
- **DB connections.** `POOL_SIZE` is per app; both apps together must fit Cloud SQL
  `max_connections`.
- **Dev mailbox.** `Swoosh.Adapters.Local` registers its storage globally, so two clustered dev
  nodes log a `global: Name conflict` for it on connect. Dev only; prod uses a different adapter.
- **Worker still serves the full router.** Nothing routes traffic to it, but it could be trimmed to
  a health check route.
