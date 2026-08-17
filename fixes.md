# RBAC Phase 1 — review

Branch `worktree-rbac-fixes`, uncommitted. Detail: `plans/rbac-audit/`.
Roles themselves are unchanged (`glific_admin > admin > manager > staff > none`) — only how they
are stored, enforced, and tested.

**Green:** 3001 tests / 0 failures · dialyzer 0 new · credo --strict · format · frontend 57 tests + tsc.

## Root cause

The hierarchy had **no single owner** — `Authorize`, `Users.check_access_role`, and the frontend
each re-derived it, with three different spellings of `glific_admin`. And `updateUser` checked the
target's *current* role instead of the *requested* one: a "may I touch this row" check answering
"may I write this value".

New `lib/glific/users/roles.ex` owns the ranking. Fails closed (unknown label → rank 0, was
`manager`). Two predicates, deliberately separate: `can_manage_user?` (whose row) and
`can_grant_roles?` (which value) — that split is why the fix is stricter *and* still lets an admin
edit a peer admin.

## Fixes

| Sev | What | Where |
|---|---|---|
| **CRIT** | `collectionStats` took `organization_id` **from query args**, gated `:staff`, and counted via `Repo.all(skip_organization_id: true)` → any staff read any tenant's data. Now pinned to the session; the arg is accepted but ignored. *(Found in the scan, not in the reported 5.)* | `resolvers/searches.ex` |
| **CRIT** | `updateUser` let a manager set `roles: ["Admin"]` / `["glific_admin"]`, incl. on themselves. Now validates requested roles from **both** `roles` and `add_role_ids`. | `resolvers/users.ex` |
| HIGH | `deleteUser` had no role check — manager could delete their org's admins. | `resolvers/users.ex` |
| HIGH | `languages` is a `global`-prefix table (writes hit **every tenant**) but was writable at `:manager` → `:glific_admin`. | `schema/language_types.ex` |
| HIGH | 3 org exports at `:staff` use **raw SQL**, so no org-scoping and no permission filter → `:admin`. | `schema/organization_types.ex` |
| HIGH | `check_access_role` fell back to `["manager"]` for any unrecognised label, and its `"Glific Admin"` clause was dead code (seeded label is `Glific_admin`). | `glific/users.ex` |
| MED | Role change didn't invalidate sessions on a bare `roles` write — cached creds embed roles, 30-min TTL, so **demoting a compromised account left it privileged for 30 min**. | `glific/users.ex` |
| MED | `export_collection` skipped `add_permission` — restricted staff exported unassigned collections. | `glific/groups.ex` |
| MED | Contact phone redaction ran **backwards**: `staff && !is_restricted`. Restricted users saw *more*. | `schema/contact_types.ex` |
| LOW | `bspbalance` had no gate at all → `:staff`. | `schema/provider_types.ex` |
| LOW | Role dropdown filtered on `'Glific admin'`, never matched `'Glific_admin'` — option was always visible. UX only. | frontend `StaffManagement.tsx` |
| **HIGH** | *Found by e2e against a live server, in this PR's own code.* `Roles.rank/1`'s atom clause consulted only `@rank`, never the alias map. The `:role_label` scalar downcases input to an atom, so `"Glific Admin"` arrived as `:"glific admin"` → rank **0** → `can_grant_roles?` returned true and a manager sailed past the escalation check. Only the Ecto enum stopped the write, as a MatchError 500. | `users/roles.ex` |
| **MED** | *Same source.* An `addRoleIds` value that doesn't resolve (another org's role, or nonexistent) produced `[]`, which `can_grant_roles?(_, [])` allows and `check_access_role` maps to the lowest role — so a manager could **silently demote** any user to `none`, and `update_user_roles/2` attached a cross-org `user_roles` row. Unresolvable ids are now refused. | `resolvers/users.ex` |

Two hunks are **chained**: fixing the `Glific_admin` typo turns dead code into a live escalation
path via `add_role_ids`, which the `updateUser` fix closes. Review them together.

## `collectionStats` — why `skip_organization_id` stays

The fix is entirely in the resolver: the org now comes from `current_user`, so the argument no
longer selects the tenant. That is sufficient, and it is verified safe —
`APIAuthPlug.get_credentials/3` (api_auth_plug.ex:36) **rejects the token when the subdomain org ≠
`user.organization_id`**, and GraphQL is authenticated before Absinthe runs
(`forward("/api", Absinthe.Plug)` sits behind `[:api, :api_protected]`, so
`Pow.Plug.RequireAuthenticated` 401s and `ContextPlug` guarantees `current_user`).

`Repo.all(skip_organization_id: true)` inside `CollectionCount.make_result/3` is **left as-is on
purpose**: `MinuteWorker` `"five_minute_tasks"` calls `CollectionCount.collection_stats()` for
*all* orgs in one `group_by organization_id` query with **no org in the process dict**, so
auto-scoping there would hit `prepare_query`'s
`raise "expected organization_id or skip_organization_id to be set"` and kill the 5-minute cron.
Splitting that path is a refactor, not a security fix, and is deliberately out of scope here.

The `organization_id` arg stays `non_null` and is simply ignored, so no client change is needed.

## Behaviour changes / judgement calls

- Managers & admins can **no longer** manage languages. If admins should, the answer is per-org
  languages, not a lower gate — product call.
- `bspbalance` is `:staff`, not the `:admin` I'd proposed: `WalletBalance` renders in the drawer for
  every role. Tightest gate that doesn't break the UI; still closes `:none`.
- `can_manage_user?` is `>=`, not `>` — strict `>` would block admin-edits-peer-admin.

## Not fixed

- **Finding 4** (`/flow-editor/`* unauthorized): needs a `RequireRole` plug — `RequireAuthenticated`
  is presence-only, so *every* REST route is role-blind. Its two claimed exploit chains were **not
  reproduced**; reported as a route gap only.
- `AddOrganization` uses `Map.put_new` → client `organization_id` still wins wherever a resolver
  reads it from args.
- 17 fields still ungated (all subscriptions). Nothing makes a missing gate fail to compile — that's
  how `bspbalance` happened.

- **`createAccessRole` sits at `:manager`** and accepts `is_reserved` in its input, so a manager can
  write rows in the very table that drives role assignment. The label→`reserved` mapping neutralises
  the escalation (verified), but a manager writing to an authorization-governing table deserves a
  second look. Pre-existing; not touched here.

Corrections to the audit's ratings: finding 2 is intra-org not platform-wide; finding 5 is
intra-tenant not cross-tenant; finding 1 was **understated**.

## E2E verification against a running server

All ten fixes were exercised over real HTTP + GraphQL on a local `mix phx.server` — tokens from
`POST /api/v1/session`, users at all five role levels plus a restricted staff user, and a real
second organization. **All ten held.** Highlights worth trusting more than a unit test:

- `collectionStats(organizationId: "2")` as org-1 staff, with org 2 holding 7 contacts, returned
  keys `['1']` only.
- Session invalidation: with a raw-SQL demotion (bypassing `update_user`) the old token still
  returned `roles:["Admin"]` and 200 on the admin-gated export — the stale-privilege window is
  real. Through `updateUser`, `fetchUserSessions` went 2→0 and the old token got **401
  immediately**. A name-only write does *not* purge, so there's no over-invalidation.
- `languages` confirmed to live in the `global` Postgres schema, and admin as well as manager now
  get `Unauthorized`.

**Trap for anyone writing tests here:** a 401 response has no GraphQL `errors` array, so a naive
harness reads it as success. Any `updateUser` touching a user purges *that user's* sessions, which
can kill a token mid-test and make later assertions "pass" against `data: null`. Assert on HTTP
status, not just `errors`.

## Tests — 13 added, each seen failing before its fix

Read the **deletions** in `user_test.exs`: `roles = ["Staff", "Admin"]` was a *passing* assertion
that a manager can promote to admin. The suite was green **because** the escalation worked.

`collectionStats` had **no `.gql` asset and no schema test** — which is why the cross-tenant hole
survived. Both now exist; the test passes another org's id and asserts you still get your own
stats. Against the old resolver it fails with `left: ["1525"]` vs `right: ["1"]` — org 1's staff
user reading org 1525's stats, the exploit demonstrated rather than argued.

Two of my own tests were broken in the same way as the bugs: the groups test copied a `with`
without an `else`, so the user switch silently no-op'd and it ran as admin (failed open, like
finding 5); the frontend test passed pre-fix because the mock had no `Glific_admin` row.

## Review order

1. `roles.ex` + its test — the new contract alone.
2. `resolvers/users.ex` **with** `glific/users.ex` — the chained fix.
3. `resolvers/searches.ex` — 2 lines, biggest impact.
4. The 4 gate changes — confirm the levels match product intent.


## TODO

- Split `CollectionCount`'s cron and per-user paths so the resolver side can drop
  `skip_organization_id: true` (the cron genuinely needs it — see the `collectionStats` section).
  Then drop the ignored `organization_id` arg once no client sends it. Refactor, not a fix.
- Refactor update_user as its too complex
- We need to remove is_restricted column from the user table
