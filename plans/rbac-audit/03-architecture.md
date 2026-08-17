# Report 3 — RBAC architecture: assessment and recommendations

**Constraint honoured:** the five roles (`glific_admin > admin > manager > staff > none`) stay
exactly as they are. Nothing here proposes new roles or renames existing ones. Everything is about
*how* roles are represented, stored, enforced, and tested.

---

## Part 1 — Diagnosis: why these bugs are structural, not incidental

Every finding in Reports 1 and 2 traces to one of six architectural properties. None is a
"someone forgot" bug; each is the predictable output of the design.

### 1.1 Authorization is opt-in, and forgetting it fails open

`lib/glific_web/schema.ex:265` applies `AddOrganization`, `SafeResolution` and the error middlewares
to every query and mutation — **but no `Authorize`**. A field with no middleware line is reachable by
any authenticated user.

The same property holds at the row level: `Repo.add_permission/3` is a call you remember to make
(15 sites), and `AccessControl.check_access/2` likewise (3 sites). Code that omits them is
indistinguishable from code that never needed them.

> **Findings explained:** 5 (`export_collection`, `export_data`), G1 (`bspbalance`), G2 (17
> subscriptions), H (Messages/Profiles have no `add_permission` at all).

### 1.2 There are two enforcement surfaces and only one enforces roles

| Surface | Gate | Fields/routes |
|---|---|---|
| GraphQL (Absinthe) | per-field `middleware(Authorize, role)` | 325 gated |
| REST (Phoenix router) | `Pow.Plug.RequireAuthenticated` — presence only | **29, none role-gated** |

`:api_protected` (`router.ex:50-53`) halts only when `current_user == nil`. `ContextPlug`
(`context_plug.ex:22-40`) then populates the process dictionary without consulting roles. The
`/flow-editor` scope reaches flows, contact fields and collections that GraphQL gates at `:manager`.

> **Findings explained:** 4, and the whole of Report 2 §A.

### 1.3 Roles are stringly-typed at every boundary

There is no single source of truth for a role name. The same concept appears as:

| Representation | Where |
|---|---|
| `:glific_admin` atom | `user_roles_enum` (`ecto_enums.ex:96-100`) |
| `"Glific_admin"` string | seeded `roles.label` (`seeds_dev.ex:1804`) |
| `"Glific Admin"` string | `check_access_role/2` (`users.ex:162`) — **never matches** |
| `'Glific admin'` string | `StaffManagement.tsx:150,153` — **never matches** |
| `'Glific_admin'` string | `StaffManagementList.tsx:82`, `role.ts:28` — matches |
| free-form `:role_label` scalar | GraphQL input (`generic_types.ex:124-149`) |

Three of six spellings are wrong, in three different files, written by different people. This is the
signature of stringly-typed authorization: **the compiler cannot help, and a typo silently disables
a security control.**

> **Findings explained:** C1/C2 (backend fallback to `:manager`), F3 (frontend dropdown guard
> broken), and finding 1's parsing step (`:role_label` accepts any existing atom).

### 1.4 Two role systems write to one column

The legacy enum (`users.roles`) and the dynamic-role tables (`roles`, `user_roles`) are not
alternatives — they are two writers to the same field. `Users.update_user/2` derives the enum from
`add_role_ids` via `check_access_role/2` **only when `add_role_ids` is present and non-empty**
(`users.ex:146-166`). Omit that key and the client's raw `roles` list flows into the changeset.

The dynamic system is also far narrower than it appears: `check_access/2` is called from 3 list
queries only, no-ops unless the default-off `roles_and_permission` flag is set, and additionally
requires the user to hold *none* of Admin/Manager/Staff (`access_control.ex:270-274`). For every
standard-role user it is inert.

> **Findings explained:** 1 (the bypass path), C3, C4, F2.

### 1.5 Authorization asks the wrong question in the one place it is relational

`Authorize.valid_role?/2` answers "does the caller out-rank threshold X?" — correct for gating an
operation. `Resolvers.Users.update_user/3` reuses it as
`valid_role?(current_user.roles, hd(target.roles))` — "does the caller out-rank this *person*?"

That is a different question, and it protects the target's **current** identity while ignoring the
**requested** one. There is no framework concept of "authorize the contents of this input", so the
only such check in the codebase was hand-rolled, and hand-rolled it wrong. `hd/1` also silently
ignores every role after the first, which is why role-stacking (`["staff","glific_admin"]`) defeats it.

> **Findings explained:** 1, 2 (the same check simply absent).

### 1.6 Identity is a 30-minute snapshot with no revocation

`APIAuthPlug.create/3` stores the **entire `%User{}` struct, roles included**, in `CredentialsCache`
(`api_auth_plug.ex:79-83`); `get_credentials/3` returns it verbatim with no DB reload, TTL 30 min.
Invalidation is conditional (`users.ex:116-122`) and **skips bare `roles` writes**.

There is no user-level `is_active`/`suspended` column at all (`user.ex:82-111`); login checks only
org status and password. "Revoking" a user means demoting them to `:none` — after which they can
still log in and still satisfy `:api_protected`.

The frontend mirrors this exactly: roles are written to `localStorage` once at login
(`Login.tsx:68`) and never refreshed.

> **Findings explained:** B, F5, and the "after re-login" caveat in finding 1.

---

## Part 2 — Recommended architecture

Ordered by (security value ÷ disruption). Items 1–3 are small and close real holes; 4–6 are the
structural work; 7 is the thing that prevents regression.

### Fix 0 — Immediate patches — ✅ IMPLEMENTED

All nine shipped. Full suite green; `mix format`, Credo `--strict`, and `tsc --noEmit` clean.

| # | Fix | Where | Status |
|---|---|---|---|
| 0.1 | `collection_stats` now ignores the client `organization_id` and uses `user.organization_id` | `resolvers/searches.ex:48-50` | ✅ |
| 0.2 | `update_user` validates the **requested** roles via `can_grant_roles?/2`, covering both `roles` and `add_role_ids` | `resolvers/users.ex:79-110` | ✅ |
| 0.3 | `delete_user` gained the target-role check | `resolvers/users.ex:141-151` | ✅ |
| 0.4 | Language create/update/delete → `:glific_admin` | `language_types.ex:70-92` | ✅ |
| 0.5 | `export_collection` enforces `has_permission?/1`; the three `organization_export_*` fields → `:admin` | `groups.ex:177-180`, `organization_types.ex:324-346` | ✅ |
| 0.6 | Role literals centralised in `Glific.Users.Roles`; frontend compares separator/case-insensitively | `users/roles.ex`, `StaffManagement.tsx:147-158` | ✅ |
| 0.7 | `bspbalance` gated | `provider_types.ex:62-66` | ✅ |
| 0.8 | Inverted phone redaction corrected | `contact_types.ex:50-56` | ✅ |
| 0.9 | Sessions invalidate on **any** role change, including a bare `roles` write | `users.ex:117-125` | ✅ |

**Two deviations from the original recommendation, both deliberate:**

- **0.7 gated at `:staff`, not `:admin`.** The wallet-balance banner (`WalletBalance.tsx`, rendered
  from `SideDrawer.tsx:71`) and `StatusBar.tsx` query `bspbalance` for **every** role. `:admin`
  would have broken the UI for staff and managers. `:staff` closes the `:none` hole — the actual
  finding — without regression.
- **`can_manage_user?/2` uses `>=`, not `>`.** Strict `>` would stop an admin editing a peer admin,
  which the previous code allowed and which the suite depends on. Escalation is blocked by
  `can_grant_roles?/2` instead; `can_manage_user?/2` only prevents reaching *up* the hierarchy.

**Beyond the nine, delivered in the same pass:**

- Root-caused **C1/C2** properly rather than patching the literal: `check_access_role/2` no longer
  falls through to `["manager"]` for an unrecognised label — an unmatched custom role now yields
  `["none"]` (fails closed), and label→role mapping lives in one place.
- **Role stacking is fixed.** `highest_rank/1` replaces `hd/1`, so `["staff", "glific_admin"]` can
  no longer hide a high-privilege role behind a low-privilege first element.
- New `Glific.Users.Roles` module — single source of truth for the hierarchy, with the middleware
  delegating to it. This is the first slice of **Fix 1**, kept in `lib/glific/` to respect the
  layering rule that business logic must not depend on the web layer.

**Regression tests added (12), all verified to fail against the unpatched code:**

| Test | Asserts |
|---|---|
| `roles_test.exs` (14 cases) | hierarchy, fail-closed unknown roles, role stacking, grant/manage rules |
| `user_test.exs` — "manager cannot grant a role above their own" | `["glific_admin"]`, `["Admin"]`, `["Staff","Admin"]` all rejected; DB unchanged |
| `user_test.exs` — "manager cannot escalate their own role" | self-escalation rejected |
| `user_test.exs` — "manager cannot delete a user of a higher role" | admin survives |
| `language_test.exs` — "a manager cannot create, update or delete a language" | all three return `Unauthorized` |
| `groups_test.exs` — "export_collection raises when not assigned" | restricted staff blocked |
| `StaffManagment.test.tsx` (2 cases) | Glific_admin absent from the dropdown for Admin **and** Manager |

The pre-existing test that **pinned the vulnerability** (`user_test.exs:209`, a manager setting
`roles: ["Staff","Admin"]` and asserting success) was rewritten to use a grantable role. The
frontend mocks never contained a Glific_admin row at all, so the old "Admin should not see Glific
admin" test passed vacuously; a new mock (`getRoleNamesWithGlificAdminMock`) makes it meaningful.

**Every new test was verified to fail against the unpatched code.** This mattered: the first draft
of the frontend test passed both before *and* after the fix, and the first draft of the
`export_collection` test silently ran as an admin. Both would have been worthless as regression
tests. Two lessons worth carrying into phase 2:

- **A security test that has never failed proves nothing.** Assert the negative case against the
  old code before trusting it. Half of my first-draft tests were vacuous.
- **`with` and no `else` fails open — the same shape as the bugs being fixed.** The
  `export_collection` test copied a pattern from `contacts_test.exs` that resolves a seeded user;
  in `groups_test.exs` that describe block has no `setup`, so the fetch failed, the
  `put_current_user` never ran, and the test passed as an admin. Fixed by constructing the
  restricted user explicitly with `Fixtures.user_fixture/1` rather than depending on ambient seed
  state. This is worth a lint: **a test that establishes a security precondition must assert that
  the precondition took effect.**

### Verification performed

| Gate | Result |
|---|---|
| `mix compile --warnings-as-errors` | clean (it caught the now-unreachable `do_update_user(false, …)` clause) |
| Full backend suite | 3001 tests, 0 failures on an uncontended run |
| Targeted suites (users, groups, language, contacts, roles) | 90 tests, 0 failures |
| `mix format --check-formatted` | clean |
| `mix credo --strict` | clean (one pre-existing TODO elsewhere) |
| `mix dialyzer` | passed — 34 errors, all 34 pre-existing skips, none new |
| Frontend `vitest` (StaffManagement) | 57 tests, 0 failures |
| Frontend `tsc --noEmit` | clean |

Note on flakiness: intermediate full-suite runs reported 12/22/35 failures while Dialyzer or a
second suite ran concurrently. Those were `:eaddrinuse` (port contention on `GlificWeb.Endpoint`)
and `DBConnection.ConnectionError` (pool exhaustion) — infrastructure, not logic. Confirmed by
re-running uncontended.

### Fix 1 — Make roles a type, not a string

Introduce one module that owns the role vocabulary and the hierarchy:

```elixir
defmodule Glific.Roles.Role do
  @roles [:glific_admin, :admin, :manager, :staff, :none]
  @rank  %{glific_admin: 4, admin: 3, manager: 2, staff: 1, none: 0}

  def all, do: @roles
  def rank(role), do: Map.fetch!(@rank, role)
  def parse("Glific_admin"), do: {:ok, :glific_admin}   # every spelling, one place
  ...
  def at_least?(user_roles, threshold),
    do: Enum.any?(user_roles, &(rank(&1) >= rank(threshold)))
  def highest(user_roles), do: Enum.max_by(user_roles, &rank/1)
end
```

Then:
- Replace `:role_label`'s free-form `safe_string_to_atom` parse with an **Absinthe enum**
  (`enum_types.ex`), so `roles: ["glific_admin"]` is rejected at the schema boundary unless the value
  is legal *and* the caller is authorized. This alone blocks finding 1's input vector.
- Replace `hd(user.roles)` with `Role.highest/1` — kills the role-stacking bypass.
- Delete `check_access_role/2`'s string `cond` and its `true -> ["manager"]` fallback. **Fail closed**
  (`:none`) when a label doesn't resolve.
- Export the same vocabulary to the frontend (generated constants file or a `roles` query) so no
  `.tsx` file ever writes a role literal again.

### Fix 2 — Make the gate mandatory, not opt-in

Invert the default in `schema.ex`'s `middleware/3` callback:

```elixir
def middleware(middleware, field, %{identifier: type}) when type in [:query, :mutation] do
  unless has_authorize?(middleware), do: raise "no Authorize gate on #{field.identifier}"
  ...
end
```

This is a **compile-time** check — a new field without a gate fails the build. Cheap, and it makes
1.1 structurally impossible going forward. Apply the same to subscriptions, where all 17 are
currently ungated (G2).

If a hard raise is too disruptive initially, the same callback can inject a `:glific_admin` default
for ungated fields — fail closed rather than open — and let the 18 known cases be fixed forward.

### Fix 3 — Give REST the same gate

Two options; recommend (a).

**(a) A `RequireRole` plug**, used per-scope in the router:

```elixir
scope "/flow-editor", GlificWeb.Flows do
  pipe_through([:api, :api_protected, {RequireRole, :manager}])
```

This puts REST and GraphQL on one hierarchy and one `Role` module. `/flow-editor` should be
`:manager` — matching `update_flow`/`publish_flow` — with read-only actions at `:staff` if the
editor needs them.

**(b)** Move flow-editor operations to GraphQL. Correct long-term, but large; the embedded
`@glific/flow-editor` library dictates the REST shape.

Separately, and regardless: fix `get_flow_revision/2` to actually use its `flow_uuid` argument
(`flows.ex:455`), validate the `save_revisions` payload, and add signature verification to the BSP
webhooks (Stripe at `plugs/stripe_webhook.ex` is the in-repo model).

### Fix 4 — Authorize *inputs*, not just operations

The missing concept behind findings 1 and 2. Add an explicit rule for privilege-bearing fields:

```elixir
defmodule Glific.Users.Policy do
  # may the actor assign this role?
  def can_grant?(actor, requested), do: Role.at_least?(actor.roles, requested)
  # may the actor act on this target at all?
  def can_manage?(actor, target),
    do: Role.rank(Role.highest(actor.roles)) > Role.rank(Role.highest(target.roles))
end
```

`update_user` must satisfy **both**; `delete_user` must satisfy `can_manage?`. Note `can_manage?` uses
strict `>`, which also fixes the self-escalation case that `valid_role?`'s `>=` semantics permit today.

### Fix 5 — One row-level mechanism, applied at the context boundary

Today five mechanisms coexist (`add_permission`, `AccessControl.check_access`, per-field resolvers,
resolver-level `valid_role?`, the `upload_contacts` boolean). Consolidate:

- Extend `add_permission` coverage to **Messages** and **Profiles** (currently zero), and to by-id
  accessors — `get_flow!/1`, `get_trigger!/1`, `get_profile!/1` are bare `Repo.get!`.
- Decide whether `AccessControl` replaces or supplements `add_permission`, then apply the winner to
  reads **and** by-id fetches, not just list queries.
- Apply row-level filtering to the **subscription** path, which currently bypasses it entirely (G2).
- Route all reads through context functions; forbid `Repo.fetch_by` on resources in resolvers, where
  it silently skips the context's permission logic (`resolvers/contacts.ex:58,119,131`).

### Fix 6 — Make identity live, and make revocation real

- **Re-read roles per request**, or store only `user_id` in the token and load the user. If the
  30-minute cache must stay for performance, key it so any `users` row update busts it.
- **Add a user-level `is_active` flag**, checked at login *and* per request. Today there is no way to
  disable an account without deleting it.
- **Client-side:** re-fetch `currentUser` on navigation or subscription reconnect and update
  `localStorage`, so a demoted user's UI collapses without a manual logout.

### Fix 7 — Test the policy, not the examples

This is what would have caught all five findings, and it is the highest-leverage item in the report.

There are currently **zero** tests asserting schema-wide gate coverage, and the existing user tests
actively **pin the vulnerable behaviour** (`user_test.exs:209-236` asserts a manager can set
`roles: ["Staff","Admin"]`). Those assertions must be inverted as part of fix 0.2.

Add three mechanical tests:

1. **Gate coverage** — walk the Absinthe schema via `__absinthe_type__(:query)` /`(:mutation)`
   /`(:subscription)`; assert every field has an `Authorize` middleware. Maintain an explicit
   allow-list so an intentional exception is a visible, reviewed line of code.
2. **Gate snapshot** — assert the full `operation → role` map against a checked-in fixture. Any gate
   change then shows up in a diff and must be justified in review. This is how `create_language`
   sitting at `:manager` becomes visible.
3. **Escalation matrix** — for each role pair (actor, target) × each of `updateUser`/`deleteUser`,
   assert allow/deny. ~20 cases, table-driven.

Plus a router test asserting every route in an authenticated scope pipes through a role plug.

---

## Part 3 — What to do, in order

| Phase | Work | Why this order |
|---|---|---|
| **1. ✅ DONE** | Fix 0.1–0.9 + C1/C2 root cause + `Users.Roles` + 12 regression tests | Self-contained patches closing verified holes. 0.1 was a genuine cross-tenant leak |
| **2. Next** | Fix 7 (tests 1 + 2) | Freezes the current gate map before refactoring, so later phases can't regress silently |
| **3.** | Fix 2 (mandatory gate) + Fix 3 (REST plug) | Removes the two fail-open surfaces. Both are additive and low-risk |
| **4.** | Fix 1 (`Role` module + GraphQL enum) + Fix 4 (input policy) | The typed-role refactor; enables deleting the string `cond`s |
| **5.** | Fix 6 (live identity, `is_active`) | Touches auth and caching — do it with tests in place |
| **6.** | Fix 5 (unify row-level) | Largest and least urgent; only affects restricted staff |

**One-line summary:** the five roles are fine. The problems are that authorization is *optional*
(nothing forces a gate), *stringly-typed* (typos silently disable it), *split across two surfaces*
(REST has none), *operation-scoped only* (inputs are never authorized), and *snapshotted* (revocation
doesn't take effect). Fixes 2, 1, 3, 4 and 6 address exactly those five properties — and fix 7 is
what keeps them addressed.
