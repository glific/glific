# Glific - CLAUDE.md

An open source two-way communication platform for the social sector (WhatsApp-based).

## Tech Stack

- **Elixir** ~> 1.18.3 / **Phoenix** 1.7 / **PostgreSQL** 15
- **GraphQL API** via Absinthe (primary API) + REST endpoints for auth, webhooks & utility integrations (e.g. Superset embed token)
- **Background Jobs**: Oban with 11+ specialized queues
- **Deployment**: Gigalixir, CI/CD via GitHub Actions
- **Monitoring**: AppSignal for APM, ExCoveralls for test coverage

## Documentation map

Read the layered docs for the area you are working in — they are the source of truth for
conventions and patterns:

| Area | File |
|------|------|
| Business logic (contexts, schemas, Oban, providers, caching, errors) | `lib/glific/CLAUDE.md` |
| Web layer (GraphQL, resolvers, authorization, `.gql` assets) | `lib/glific_web/CLAUDE.md` |
| Tests, fixtures, mocking, coverage | `test/CLAUDE.md` |
| Database migrations | `priv/repo/migrations/CLAUDE.md` |

Specialized agents in `.claude/agents/` (`backend-engineer`, `code-reviewer`,
`test-automator`) encode the same conventions for automated implement/review/test workflows.

When unsure how something is done, find the nearest existing example and mirror it. Reference
implementations: `Glific.Tags` / `Glific.Tags.Tag`, `GlificWeb.Resolvers.Tags`,
`GlificWeb.Schema.TagTypes`, `test/glific/tags_test.exs`, `test/glific_web/schema/tag_test.exs`.

## Directory Structure

```
glific/
├── .claude/             # Claude Code config (settings, skills, agents)
├── api.docs/            # Bruno API collections
├── assets/              # Frontend assets + assets/gql/ GraphQL operation files
├── config/              # Environment configs (dev, test, prod, runtime)
├── lib/
│   ├── glific/          # Business logic — see lib/glific/CLAUDE.md
│   └── glific_web/      # Web layer — see lib/glific_web/CLAUDE.md
├── plans/               # Architecture planning docs (e.g. webhook-refactor.md)
├── priv/repo/           # Migrations, seeds, structure.sql
├── test/                # Mirrors lib/ — see test/CLAUDE.md
└── rel/                 # Release configuration
```

## Cross-cutting code style

Applies to all Elixir modules unless a layer doc says otherwise.

### Import/alias order

1. `use` statements
2. `alias __MODULE__` (self-reference)
3. `require` statements (e.g., `require Logger`)
4. `import` statements (e.g., `import Ecto.Query`)
5. Other aliases (grouped alphabetically: `alias Glific.{Contacts.Contact, Repo, ...}`)
6. Module attributes (`@required_fields`, `@optional_fields`)
7. Type definitions (`@type t()`)
8. Function definitions

### Specs & docs

- `@spec` on all public functions
- `@moduledoc` on all modules
- `@doc` with iex examples where useful

## Multi-tenancy (summary)

Glific is multi-tenant: every major table has `organization_id`, and `Repo.prepare_query/3`
auto-injects org scoping from the process dictionary. Set context with
`Repo.put_organization_id/1`; use `skip_organization_id: true` only for deliberate cross-org
paths. **Oban workers and resolver by-id lookups have extra rules** — see
`lib/glific/CLAUDE.md` and `lib/glific_web/CLAUDE.md`.

**Schema maintenance invariant**: When adding a new org-scoped table (any migration that includes
an `organization_id` column), also add the table name to `Glific.Erase.org_data_deletion_order/0`
in `lib/glific/erase.ex`. A CI drift test asserts the list covers every live `organization_id`
table — missing entries fail the test suite. FK cycles (`organizations` ↔ contacts/flows,
`assistants` ↔ `assistant_config_versions`) are pre-broken by `Erase.break_fk_cycles/1` before
the ordered deletes run; cyclic FK columns must be nulled there too.

## Admin Scripts

- **Location**: `lib/glific/scripts/` — IEx console helpers, not web-facing or Oban workers
- **Pattern**: self-contained module with `@moduledoc` showing the exact IEx invocation
- **Naming**: `Glific.Scripts.<Domain>` (e.g., `Glific.Scripts.Evals`)
- Always call `Repo.put_organization_id/1` at the top of any function that touches org-scoped data

## Claude Code Project Configuration

- **Settings**: `.claude/settings.json` — `permissions.deny` blocks secret config files
  (`config/.env.dev`, `config/dev.secret.exs`)
- **Worktree symlinks**: `worktree.symlinkDirectories` symlinks `_build`, `deps`, `priv/cert`,
  `config/.env.dev`, and `config/dev.secret.exs` from the main checkout into isolated worktrees
- **Skills** (`.claude/skills/`): `fix-flaky-tests`, `improve-code-coverage`,
  `make-branch-ready-for-review`

## Code Quality & Formatting

- **Formatter**: `mix format` (imports from `:ecto`, `:ecto_sql`, `:phoenix`)
- **Linter**: Credo (non-strict locally; `--strict` in CI)
- **Type checking**: Dialyzer (PLTs in `priv/plts/`)
- **CI**: `MIX_ENV=test mix check` — Credo + Dialyzer + Doctor + Format + compile with
  warnings-as-errors
- **Security**: Sobelow

## Common Commands

```bash
mix setup              # Install deps, compile, reset DB, deploy assets
mix test               # Run tests (creates DB, loads, migrates)
mix test_full          # Full DB reset before tests
mix format             # Format code
mix check              # Run all code quality checks (Credo, Dialyzer, Format)
mix ecto.reset         # Drop + setup database
mix coveralls.html     # Generate test coverage report
```
