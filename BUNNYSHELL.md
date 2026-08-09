# Bunnyshell ephemeral environments

`bunnyshell.yaml` (in this repo root) defines a shareable, on-demand Glific environment on
[Bunnyshell](https://www.bunnyshell.com/). It assembles four components from three repositories:

| Component       | Repo / branch                     | What it is                            |
|-----------------|-----------------------------------|---------------------------------------|
| `db`            | `postgres:15-alpine` image        | Postgres 15 (persistent `pg-data` PVC)|
| `backend`       | `glific` @ `master`               | Elixir/Phoenix API + socket           |
| `admin-console` | `glific-frontend` @ `master`      | Staff console (Vite/React)            |
| `web-channel`   | `glific-web-channel` @ `main`     | Embeddable chat widget (Vite/React)   |

The backend builds from this repo's `Dockerfile` + `config/entrypoint.sh`; the two frontends
build from their own repos' `Dockerfile` + `nginx.conf`.

## Prerequisites

1. **Merge the `bunnyshell` branches.** The Dockerfiles/nginx configs and the backend deploy
   config this env needs currently live on the `bunnyshell` branch of each repo. Merge each to
   its default branch first, **or** temporarily set the matching `gitBranch` in `bunnyshell.yaml`
   to `bunnyshell` to try it out before merging.
2. **Set these variables in the Bunnyshell environment** (referenced as `{{ env.vars.NAME }}`,
   never committed):
   - `POSTGRES_PASSWORD` — Postgres password
   - `OBAN_FINGERPRINT`, `OBAN_AUTH_KEY` — the backend image fetches Oban Pro from getoban.pro
   - `OPEN_AI_KEY` — GPT / GPT-vision flow nodes (optional)
   - `KAAPI_ENDPOINT`, `KAAPI_API_KEY` — speech-to-text / TTS nodes (optional)
3. **Confirm the backend build-arg versions** in `bunnyshell.yaml` match a working local
   `docker build` (the Dockerfile ARGs have no defaults).

## How it works

- **Networking:** apps reach Postgres at the internal DNS name `db:5432`. The frontends receive
  the backend's public hostname at *build* time (Vite inlines env into the bundle), so those are
  `build.args`, not runtime env.
- **Tenant + origins:** `BACKEND_HOST` lets `GlificWeb.SubdomainPlug` resolve the seeded `glific`
  org, and `CHECK_ORIGIN` allow-lists the two frontends so their WebSocket handshakes pass
  Phoenix's `check_origin`. See the env-guarded block in `config/dev.exs` (a no-op when
  `BACKEND_HOST` is unset, so local dev is unchanged).
- **First boot vs redeploy:** `config/entrypoint.sh` waits for Postgres, then loads the schema
  and seeds on a *fresh* database (detected by querying the DB itself) and only runs migrations
  on later boots — so data on the `pg-data` volume survives redeploys.
- **DB SSL:** `config/runtime.exs` treats DB SSL as optional (skipped when no CA cert env var is
  set / `ENABLE_DB_SSL=false`), so the in-cluster Postgres works without certificates.

## Caveat: web-channel widget

The `web-channel` widget needs the web-channel backend feature (its REST + socket routes), which
is not yet on `glific @ master`. Until that feature is merged, the widget deploys and serves but
its chat will not connect. The `backend` + `admin-console` form a fully functional generic Glific
environment on their own.
