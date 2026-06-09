# `lib/glific/` — Business Logic Layer (Contexts, Schemas, Jobs, Providers)

This is the heart of Glific: ~53 context modules plus their schema subdirectories, Oban
workers, BSP providers, and third-party integrations. Everything here is framework-agnostic
business logic — **no Absinthe, no Plug, no HTTP concerns** (those live in `lib/glific_web/`).

> Read this before adding or refactoring anything under `lib/glific/`. The root `CLAUDE.md`
> covers project-wide conventions; this file covers the layer-specific patterns and the
> non-obvious invariants that the codebase actually enforces.

## The canonical "vertical slice" for a domain entity

A new entity (say `Widget`) is built bottom-up. The context + schema halves live here:

```
lib/glific/widgets/widget.ex     # Ecto schema  (Glific.Widgets.Widget)
lib/glific/widgets.ex            # Context API   (Glific.Widgets)
```

The web half (`lib/glific_web/schema/widget_types.ex`, resolver, `schema.ex` wiring) and the
test/`.gql` halves are documented in `lib/glific_web/CLAUDE.md` and `test/CLAUDE.md`.

### Schema module (`lib/glific/<ctx>/<entity>.ex`)

Mirror `Glific.Tags.Tag` — the cleanest reference implementation:

- `use Ecto.Schema` + `import Ecto.Changeset`
- Alias block (alphabetical), grouped `alias Glific.{...}`
- `@required_fields` and `@optional_fields` as module attributes (lists of atoms)
- `@type t() :: %__MODULE__{...}` listing **every** field, including assocs as
  `Assoc.t() | Ecto.Association.NotLoaded.t() | nil`
- `schema "<table>" do ... timestamps(type: :utc_datetime) end`
- `@spec changeset(t(), map()) :: Ecto.Changeset.t()` that `cast`s, `validate_required`s, adds
  `foreign_key_constraint/2` for each FK, and **scopes uniqueness by org**:
  `unique_constraint([:field, :organization_id])`
- Every entity belongs to an `Organization` (`belongs_to :organization, Organization`).

### Context module (`lib/glific/<ctx>.ex`)

Mirror `Glific.Tags`. The context is the **only** public boundary — schemas are never called
directly from the web layer. Use the `Repo` helper functions instead of hand-writing queries:

| Function | Naming contract |
|----------|-----------------|
| `list_<entities>(args)` | `Repo.list_filter(args, Entity, &Repo.opts_with_label/2, &Repo.filter_with/2)` |
| `count_<entities>(args)` | `Repo.count_filter(args, Entity, &Repo.filter_with/2)` |
| `get_<entity>!(id)` | raises (`Repo.get!`) |
| `fetch_<entity>(id)` / `fetch_by(...)` | returns `{:ok, e}` / `{:error, ["Resource not found"]}` |
| `create_<entity>(attrs)` | `%Entity{} \|> Entity.changeset(attrs) \|> Repo.insert()` |
| `update_<entity>(e, attrs)` | `... \|> Repo.update()` |
| `delete_<entity>(e)` | `Repo.delete(e)` |

`Repo.list_filter/5` and `Repo.filter_with/2` already understand the standard `%{filter: ..., opts: %{order, limit, offset}}` shape. Custom filters get a private `filter_with/2` clause that pattern-matches the extra keys and falls through to `super` — grep `defp filter_with` in any context (e.g. `Glific.Contacts`) for the pattern.

## Multi-tenancy — the most important invariant

- `Glific.Repo.prepare_query/3` **automatically** injects `WHERE organization_id = ?` into
  almost every query, reading the id from the process dictionary (`Repo.get_organization_id/0`).
- Org context is set per-process: `Repo.put_organization_id(org_id)` (done in the Plug pipeline
  for web requests, in `DataCase`/`ConnCase` for tests, and **manually inside every Oban worker**).
- To run a genuinely cross-org query, pass `skip_organization_id: true` as a repo opt — do this
  rarely and deliberately (SaaS/admin/cron paths only).
- **In Oban workers you must call `Repo.put_process_state(org_id)`** (or `put_organization_id`)
  at the top of `perform/1` — the job runs in a fresh process with no org context. Forgetting
  this is the #1 source of "works in dev, leaks/empties in prod" bugs. See `Contacts.ImportWorker`.

## Oban workers (background jobs)

```elixir
use Oban.Worker, queue: :queue_name, max_attempts: N   # priority: optional
@impl Oban.Worker
def perform(%Oban.Job{args: %{"organization_id" => org_id} = args}) do
  Repo.put_process_state(org_id)        # MANDATORY — restore tenant context
  ...
  :ok                                    # | {:error, reason} | {:snooze, seconds}
end
```

- Args are serialized to JSON, so they come back **string-keyed** and atoms become strings
  (`Enum.map(roles, &String.to_existing_atom/1)` — note `to_existing_atom` to avoid atom-table
  exhaustion).
- Queues are declared in `config/config.exs` (`gupshup`, `bigquery`, `crontab`, `default`,
  `dialogflow`, `gcs`, `webhook`, `broadcast`, `wa_group`, `purge`, …). Adding a queue means
  adding it to config, not just the worker.
- Scheduled work hangs off `Glific.Jobs.MinuteWorker` (the crontab fan-out) — most periodic jobs
  add a clause there rather than registering a new cron entry.
- Rate-limited BSP sends use `ExRated.check_rate/3`; dynamic behavior uses
  `FunWithFlags.enabled?/2`.

## Error handling & logging

- Use `with ... <- ... do ... end` (+ optional `else`) for multi-step flows. Let the happy
  path read top-to-bottom; handle failures in `else`.
- **Logging exceptions: always `Glific.log_exception/1`.** For recoverable errors use
  `Glific.log_error/2`. **Never call `Appsignal.send_error`/`Appsignal.error` directly** — the
  wrappers centralize Logger + AppSignal and suppress known-benign beneficiary errors
  (`ignore_error?/1`).
- Bang functions raise; non-bang return tagged tuples. Don't mix the two contracts in one fn.

## Caching (Cachex, bucket `:glific_cache`)

- Org-scoped key: `{organization_id, key}`. Global key: `{:global, key}`.
- API: `Glific.Caches.set/4`, `get/3`, `fetch/3` (fetch takes a fallback fn for cache-miss).
- Default TTL 24h. Invalidate via the reload-key pattern (`{org_id, :cache_reload_key}`).
- Organization config is heavily cached — after changing partner/org data, expect to
  `Partners.fill_cache/1` (tests do this in setup).

## Large subsystems — read before touching

These are old, dense, and pattern-divergent. Read the subtree and nearby tests **before**
editing or "cleaning up":

- `flows/` (34 modules) — the flow execution engine (FlowContext, actions, nodes, broadcast).
  State machine; small changes have wide blast radius.
- `providers/` (25 modules) — BSP integrations (Gupshup, Gupshup Enterprise, Maytapi). Outbound
  message sending, webhooks, workers. Tesla-based HTTP; mocked with `Tesla.Mock` in tests.
- `third_party/` — BigQuery, Dialogflow, GCS, Gemini, Sheets, Kaapi, etc.
- `partners.ex` / `partners/` — organizations, providers, credentials, billing. Central to
  multi-tenancy and caching.

## When standardizing / cleaning up (this is a goal of these agents)

Glific predates several of its own conventions, so you will find drift. Safe, mechanical
standardizations: adding missing `@spec`/`@moduledoc`/`@doc`, aligning the alias/import order
from the root `CLAUDE.md`, replacing direct `Appsignal` calls with `Glific.log_*`, converting
nested `case` into `with`, scoping unique constraints by org. **Behavior-changing** cleanups
(query semantics, changeset validations, deletion of "dead" code that may be called via
GraphQL/Oban/flows) require running the full test suite and, when ambiguous, asking first.
Always confirm a symbol is truly unused across `lib/`, `test/`, `assets/gql/`, seeds, and flow
definitions before deleting it.
