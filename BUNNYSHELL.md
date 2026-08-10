# Bunnyshell ephemeral environments

`bunnyshell.yaml` (in this repo root) defines a shareable, on-demand Glific environment on
[Bunnyshell](https://www.bunnyshell.com/). It assembles three components from two repositories:

| Component       | Repo / branch                     | What it is                            |
|-----------------|-----------------------------------|---------------------------------------|
| `db`            | `postgres:15-alpine` image        | Postgres 15 (persistent `pg-data` PVC)|
| `backend`       | `glific` @ `master`               | Elixir/Phoenix API + socket           |
| `admin-console` | `glific-frontend` @ `master`      | Staff console (Vite/React)            |

The backend builds from this repo's `Dockerfile` + `config/entrypoint.sh`; the staff console
builds from its own repo's `Dockerfile` + `nginx.conf`.

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

- **Networking:** apps reach Postgres at the internal DNS name `db:5432`. The staff console
  receives the backend's public hostname at *build* time (Vite inlines env into the bundle), so
  that is a `build.arg`, not runtime env.
- **Tenant + origins:** the backend uses the same `config/runtime.exs` path as production — no
  dev-only config. `BASE_URL` is the endpoint host, which `GlificWeb.SubdomainPlug` matches as the
  root host to resolve the seeded `glific` org; `REQUEST_ORIGIN` / `REQUEST_ORIGIN_WILDCARD`
  allow-list the staff console so its WebSocket handshake passes Phoenix's `check_origin`.
- **First boot vs redeploy:** `config/entrypoint.sh` waits for Postgres, then loads the schema
  and seeds on a *fresh* database (detected by querying the DB itself) and only runs migrations
  on later boots — so data on the `pg-data` volume survives redeploys.
- **DB SSL:** `config/runtime.exs` reads `ENABLE_DB_SSL` in one place; the manifest sets it to
  `false` so the in-cluster Postgres (no TLS) works without certificates. Even left on, SSL is
  skipped when a DB's CA cert env var is absent.
