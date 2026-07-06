# `lib/glific_web/` — Web Layer (GraphQL, Resolvers, Controllers, Plugs)

The HTTP/GraphQL boundary. GraphQL (Absinthe) is the **primary API**; REST controllers exist
only for auth (Pow), provider webhooks, and a few utility endpoints. This layer is thin: it
authorizes, injects org context, calls a `Glific.*` context function, and shapes the result.
**No business logic lives here** — push it down into `lib/glific/`.

> Pairs with `lib/glific/CLAUDE.md` (the context/schema half of every feature).

## GraphQL is wired in three files per entity + one shared file

For entity `Widget` you create/touch:

1. `lib/glific_web/schema/widget_types.ex` — types, inputs, queries, mutations
2. `lib/glific_web/resolvers/widget.ex` — resolver functions
3. `lib/glific_web/schema.ex` — **import the types and the fields** (easy to forget → silent 404)

### 1. Type module (`schema/<entity>_types.ex`) — mirror `TagTypes`

```elixir
defmodule GlificWeb.Schema.WidgetTypes do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]
  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :widget_result do          # result wrapper: entity + errors
    field :widget, :widget
    field :errors, list_of(:input_error)
  end

  object :widget do
    field :id, :id
    # ... scalar fields ...
    field :organization, :organization do
      resolve(dataloader(Repo))     # assocs via dataloader — never hand-load
    end
  end

  input_object :widget_filter do ... end   # one field per filterable column
  input_object :widget_input  do ... end   # writable fields only

  object :widget_queries do
    field :widget, :widget_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Widget.widget/3)
    end
    field :widgets, list_of(:widget) do
      arg(:filter, :widget_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Widget.widgets/3)
    end
    field :count_widgets, :integer do
      arg(:filter, :widget_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Widget.count_widgets/3)
    end
  end

  object :widget_mutations do
    field :create_widget, :widget_result do
      arg(:input, non_null(:widget_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Widget.create_widget/3)
    end
    field :update_widget, :widget_result do
      arg(:id, non_null(:id))
      arg(:input, :widget_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Widget.update_widget/3)
    end
    field :delete_widget, :widget_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Widget.delete_widget/3)
    end
  end
end
```

### 2. Resolver (`resolvers/<entity>.ex`) — mirror `Resolvers.Tags`

- Every fn is arity-3: `(_parent, args, %{context: %{current_user: user}})`.
- Mutations return `{:ok, %{widget: widget}}` (the key matches the `*_result` object field).
- Use `with ... do ... end`; let `ChangesetErrors`/`QueryErrors` middleware format failures.
- **SECURITY — re-scope every by-id lookup to the caller's org:**
  ```elixir
  Repo.fetch_by(Widget, %{id: id, organization_id: user.organization_id})
  ```
  Do **not** trust that `prepare_query` alone is enough for mutations/reads keyed by a
  client-supplied id — always pass `organization_id` explicitly. Omitting it is a tenant-isolation
  bug (an attacker passes another org's id).
- **Organization-level endpoints ignore any client-supplied `id` outright** — resolvers like
  `organization`, `update_organization`, `delete_organization_test_data` derive the target
  solely from `current_user.organization_id`; the `id` arg (if still present for API
  compatibility) is never read. There is no "other org's id" to re-scope against if the argument
  is never trusted in the first place.

### 3. Wire into `schema.ex` (BOTH steps, or the field won't exist)

```elixir
import_types(__MODULE__.WidgetTypes)     # near the other import_types lines

# inside `query do`:
import_fields(:widget_queries)

# inside `mutation do`:
import_fields(:widget_mutations)
```

## Authorization (`Authorize` middleware)

Role hierarchy (high→low): `glific_admin > admin > manager > staff > none`. Conventions:

- **Reads** (`field`, `list`, `count`): `middleware(Authorize, :staff)`
- **Writes** (create/update/delete): `middleware(Authorize, :manager)`
- Admin/SaaS-only operations: `:admin` / `:glific_admin`. Open endpoints: `:any`.
- **Full org lifecycle mutations require `:glific_admin`, not `:admin`** — `create_organization`,
  `delete_organization`, `delete_organization_test_data`, `delete_inactive_organization`,
  `reset_organization`. `:admin` is scoped to staff of a single org; these operations act across
  tenants and are SaaS-operator-only.

Other per-field middleware: `AddOrganization` (injects org context), `RequireFeatureFlag`
(gates by `FunWithFlags`), `SafeResolution` (wraps resolvers so an unexpected raise becomes a
GraphQL error instead of a 500). Enums are centralized in `schema/enum_types.ex`.

## `.gql` operation assets (required for tests, and they double as API docs)

Every query/mutation a test exercises needs a matching file under `assets/gql/<entity>/`:
`by_id.gql`, `count.gql`, `create.gql`, `delete.gql`, `list.gql`, `update.gql`, and a shared
`fields.frag.gql` fragment. They use `#import "./fields.frag.gql"` and reference the shared
`ErrorFields` fragment. The `<entity>_test.exs` loads them with
`load_gql(:create, GlificWeb.Schema, "assets/gql/<entity>/create.gql")`.
**No `.gql` file → no schema test.**

## REST controllers, plugs, providers

- `controllers/` — Pow auth, provider webhook receivers, media/upload, misc REST.
- `plugs/` — `APIAuthPlug` (token extraction/validation), rate limiting, tenant resolution.
- `providers/` (under `glific_web`) — inbound webhook routing for Gupshup/Maytapi; actual
  message handling delegates into `Glific.Providers.*`.
- `router.ex` — pipelines: `:api` (GraphQL, token-auth) vs public webhook routes.

## Standardization notes

When cleaning up this layer: align `field` ordering and middleware roles with the dominant
pattern above, ensure every resolver by-id call is org-scoped, ensure mutations return the
`%{entity: ...}` shape, and confirm new types are imported **and** their fields imported in
`schema.ex`. Verify GraphQL changes with the matching `test/glific_web/schema/<entity>_test.exs`
(see `test/CLAUDE.md`).
