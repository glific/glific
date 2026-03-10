# Glific - CLAUDE.md

An open source two-way communication platform for the social sector (WhatsApp-based).

## Tech Stack

- **Elixir** ~> 1.18.3 / **Phoenix** 1.7 / **PostgreSQL** 15
- **GraphQL API** via Absinthe (primary API) + REST endpoints for auth & webhooks
- **Background Jobs**: Oban with 11+ specialized queues
- **Deployment**: Gigalixir, CI/CD via GitHub Actions
- **Monitoring**: AppSignal for APM, ExCoveralls for test coverage

## Directory Structure

```
glific/
├── api.docs/            # API documentation (Bruno collections, examples)
├── assets/              # Frontend assets (JS, CSS, Tailwind, GQL)
├── build_scripts/       # Deployment scripts (Gigalixir)
├── config/              # Environment configs (dev, test, prod, runtime)
├── lib/
│   ├── glific/          # Business logic (contexts, schemas, jobs, providers)
│   │   ├── enums/       # Enum definitions (EctoEnum + constants)
│   │   ├── flows/       # Flow engine
│   │   ├── messages/    # Message handling
│   │   ├── contacts/    # Contact management
│   │   ├── providers/   # BSP integrations (Gupshup, Maytapi)
│   │   ├── third_party/ # External services (BigQuery, Dialogflow, GCS, Gemini, etc.)
│   │   └── ...          # ~49 context modules at root level
│   └── glific_web/      # Web layer
│       ├── controllers/ # REST API controllers
│       ├── schema/      # GraphQL type definitions
│       ├── resolvers/   # GraphQL resolvers
│       ├── plugs/       # Custom plugs (auth, rate limiting)
│       └── router.ex    # Route definitions
├── priv/
│   ├── repo/migrations/ # Database migrations
│   ├── repo/seeds*.exs  # Seed files
│   └── data/            # Static data files
├── rel/                 # Release configuration (vm.args, env)
└── test/
    ├── glific/          # Business logic tests
    ├── glific_web/      # Web layer tests
    └── support/         # Test helpers (DataCase, ConnCase, Fixtures)
```

## Multi-Tenancy

- Every major table has an `organization_id` foreign key
- `Repo.default_options/1` automatically reads organization_id from the process dictionary via `get_organization_id()`
- `prepare_query/3` auto-injects `WHERE organization_id = ?` into all queries
- Organization context is set once per process (e.g., in Plug pipeline or test setup) via `Repo.put_organization_id(org_id)`
- Skip org scoping with `skip_organization_id: true` for cross-org queries
- Unique constraints are often scoped: `unique_index(:table, [:field, :organization_id])`

## Code Conventions

### Module Organization

- Namespaces: `Glific.*` for business logic, `GlificWeb.*` for web layer
- Contexts pattern: Context modules (e.g., `Glific.Contacts`) as public API boundaries
- Schemas in subdirectories: `Glific.Contacts.Contact`, `Glific.Messages.Message`

### Import/Alias Order in Modules

1. `use` statements
2. `alias __MODULE__` (self-reference)
3. `require` statements (e.g., `require Logger`)
4. `import` statements (e.g., `import Ecto.Query, warn: false`)
5. Other aliases (grouped alphabetically: `alias Glific.{Contacts.Contact, Repo, ...}`)
6. Module attributes (`@required_fields`, `@optional_fields`)
7. Type definitions (`@type t()`)
8. Function definitions

### Function Naming

- `get_entity!(id)` - raises on not found
- `get_entity(id)` - returns `nil` on not found
- `fetch(queryable, id)` / `fetch_by(queryable, clauses)` - returns `{:ok, entity}` or `{:error, reason}`
- `list_entities(args)` - returns list with filtering
- `count_entities(args)` - returns count
- `create_entity(attrs)` - returns `{:ok, entity}` or `{:error, changeset}`
- `update_entity(entity, attrs)` - returns `{:ok, entity}` or `{:error, changeset}`
- `delete_entity(entity)` - returns `{:ok, entity}` or `{:error, changeset}`

### Schema Conventions

- Always define `@type t()` with all fields
- Separate `@required_fields` and `@optional_fields` as module attributes
- Always include `timestamps(type: :utc_datetime)`
- Multiple changeset functions for different purposes (e.g., `changeset/2`, `update_changeset/2`)

### Specs & Docs

- `@spec` on all public functions
- `@moduledoc` on all modules
- `@doc` with iex examples where useful

## GraphQL (Absinthe) Conventions

- **Schema**: `lib/glific_web/schema.ex` imports all type modules and defines root query/mutation
- **Types**: One file per domain in `lib/glific_web/schema/` (e.g., `contact_types.ex`, `message_types.ex`)
  - Objects, input types, result wrapper types (`contact_result`), and queries/mutations per domain
  - Use `dataloader(Repo)` for efficient batch loading of associations
- **Resolvers**: One file per domain in `lib/glific_web/resolvers/` (e.g., `contacts.ex`)
  - Resolvers return `{:ok, %{entity: data}}` for mutations
  - Use `with/else` pattern for multi-step operations
- **Middleware**: Applied per field
  - `Authorize` middleware for role-based access (`:staff`, `:manager`, `:admin`, `:any`)
  - `AddOrganization` middleware injects org context
  - `ChangesetErrors` / `QueryErrors` for error formatting
- **Enums**: Centralized in `enum_types.ex`, backed by `EctoEnum` + `Glific.Enums.Constants`

## Testing Conventions

- **Test Cases**:
  - `Glific.DataCase` - for business logic/database tests (SQL Sandbox, sets org context)
  - `GlificWeb.ConnCase` - for HTTP/GraphQL endpoint tests (sets up auth, roles)
  - `GlificWeb.ChannelCase` - for WebSocket channel tests
- **Test Organization**: Mirror `lib/` structure under `test/`
- **Fixtures**: Direct fixture functions in `test/support/fixtures.ex` (no ExMachina)
  - Pattern: `entity_fixture(attrs \\ %{})` with sensible defaults using Faker
  - Nested fixtures for dependencies (e.g., `organization_fixture` creates a contact first)
- **Test Setup**: Each DataCase test automatically:
  - Sets `organization_id` to 1 via `Repo.put_organization_id(1)`
  - Creates a test user and fills organization cache
- **GraphQL Testing**: `auth_query_gql_by/3` macro in ConnCase for authenticated GraphQL queries
- **Async Tests**: `use Glific.DataCase, async: true` for parallel execution
- **Module Attributes**: `@valid_attrs` and `@invalid_attrs` for test data
- **HTTP Mocking**: Tesla.Mock for external API calls
- **Coverage**: ExCoveralls with `mix test_full` task

## Error Handling Patterns

- **`with/else` pattern** - Primary pattern for multi-step operations:
  ```elixir
  with {:ok, entity} <- Repo.fetch_by(Entity, %{id: id}),
       {:ok, result} <- Context.update_entity(entity, params) do
    {:ok, %{entity: result}}
  end
  ```
- **Bang functions** (`!`) raise exceptions; non-bang return `{:ok, data}` / `{:error, reason}`
- **`Glific.log_error/2`** - Central error logging that logs to Logger + sends to AppSignal
- **Rescue clauses** in resolvers for unexpected errors
- **`Repo.fetch/2` / `Repo.fetch_by/2`** - Custom wrappers returning `{:ok, entity}` / `{:error, ["Resource not found"]}`

## Background Jobs (Oban)

- **Workers**: Define with `use Oban.Worker, queue: :queue_name, max_attempts: N`
- **Entry point**: `perform(%Oban.Job{args: args})` with pattern matching
- **Return values**: `:ok`, `{:error, reason}`, or `{:snooze, seconds}`
- **Queues**: 11+ specialized queues (gupshup, bigquery, crontab, default, dialogflow, gcs, webhook, broadcast, wa_group, purge, etc.)
- **Crontab**: 15 scheduled jobs via Oban Cron plugin (ranging from every minute to daily)
- **Rate limiting**: `ExRated.check_rate/3` for BSP rate limits
- **Feature flags**: `FunWithFlags.enabled?/2` for dynamic behavior switching

## Authentication & Authorization

- **Authentication**: Pow library for session/token management
- **Token flow**: API access token + renewal token pattern
- **Role hierarchy**: `glific_admin` > `admin` > `manager` > `staff` > `none`
- **GraphQL Authorization**: `Authorize` middleware checks user roles per field
- **API Auth Plug**: `GlificWeb.APIAuthPlug` extracts and validates tokens from requests
- **Organization isolation**: Queries automatically scoped by `organization_id`

## Caching

- **Library**: Cachex with bucket `:glific_cache`
- **Organization-scoped keys**: `{organization_id, key}`
- **Global keys**: `{:global, key}`
- **API**: `Glific.Caches.set/4`, `Glific.Caches.get/3`, `Glific.Caches.fetch/3` (with fallback function)
- **TTL**: Default 24 hours, configurable per key
- **Cache invalidation**: Reload key pattern (`{organization_id, :cache_reload_key}`)

## Database Conventions

- **Repo**: `Glific.Repo` (primary) + `Glific.RepoReplica` (read-only replica, points to primary in tests)
- **Migrations**: Timestamp-based naming `YYYYMMDDhhmmss_description.exs`
- **Soft deletes**: `deleted_at` field with partial indexes (`WHERE deleted_at IS NULL`)
- **Timestamps**: Always `timestamps(type: :utc_datetime)`
- **Seeds**: Modular seed files (`seeds_dev.exs`, `seeds_credentials.exs`, `seeds_optins.exs`, `seeds_scale.exs`)
- **Query helpers**: Centralized in `RepoHelpers` - `list_filter/5`, `filter_with/2`, `opts_with_name/2`, `opts_with_field/3`
- **Audit**: `ExAudit.Repo` for change tracking

## Code Quality & Formatting

- **Formatter**: `mix format` with imports from `:ecto`, `:ecto_sql`, `:phoenix`
- **Linter**: Credo (non-strict mode, max 120 char lines, max 3 nesting levels)
- **Type checking**: Dialyzer with PLT files in `priv/plts/`
- **CI checks**: `mix check` runs Credo + Dialyzer + Format + compilation with warnings-as-errors
- **Security**: Sobelow for security analysis

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
