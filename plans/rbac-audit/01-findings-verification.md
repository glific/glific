# Report 1 — Verification of the 5 reported RBAC findings

**Scope:** independent confirmation of each finding against source, at commit `26b702634` (branch `master`, worktree `rbac-fixes`).
**Method:** read the authorizing middleware gate, the resolver, the context function, the Ecto changeset, and the existing tests for each path. Every claim below cites `file:line`.

> **Status: findings 1, 2, 3 and 5 are FIXED** (see Report 3, "Fix 0"). Finding 4 (the
> `/flow-editor` REST gap) is **not** fixed — it needs a `RequireRole` plug across 29 routes and is
> scheduled for phase 3. Line numbers below describe the code **as audited**, before the fix.

## Verdict summary

| # | Finding | Verdict | Actor as stated? | Impact as stated? |
|---|---------|---------|------------------|-------------------|
| 1 | `updateUser` checks target's current role, not requested role | **CONFIRMED — and stronger than reported** | Yes (`:manager`) | Yes; escalation path is broader than described |
| 2 | `deleteUser` has no target-role check | **CONFIRMED** | Yes (`:manager`) | Yes, with one correction (scope is intra-org) |
| 3 | Global `languages` table writable at `:manager` | **CONFIRMED** | Yes (`:manager`) | Yes — cross-tenant, and applies to create/delete too |
| 4 | All `/flow-editor/*` routes lack role authorization | **CONFIRMED (route gap) / UNVERIFIED (exploit chain)** | Partially — see below | Downgraded pending reproduction |
| 5 | Two `:staff` exports bypass the restricted-staff filter | **CONFIRMED** | Yes (restricted `:staff`) | **Corrected: intra-tenant, not cross-tenant** |

Nothing here is a false positive. Two impact statements need correction (4 and 5), and finding 1 understates the problem.

---

## Finding 1 — `updateUser` authorizes against the target's current role

### Verdict: CONFIRMED. Pinned by two passing tests.

**The defect.** `lib/glific_web/resolvers/users.ex:79-86`:

```elixir
def update_user(_, %{id: id, input: params}, %{context: %{current_user: current_user}}) do
  with {:ok, user} <-
         Repo.fetch_by(User, %{id: id, organization_id: current_user.organization_id}) do
    current_user.roles
    |> Authorize.valid_role?(hd(user.roles))   # <- target's CURRENT role
    |> do_update_user(user, params)
  end
end
```

`params` is never inspected. The only authorization question asked is "does the caller out-rank the
target *today*", never "is the caller allowed to grant the role being requested".

**The gate.** `lib/glific_web/schema/users_types.ex:139-142` — `update_user` is
`middleware(Authorize, :manager)`. The reported actor (a manager) is correct.

**The write actually lands.** Three links, all verified:

1. `user_input` exposes `field :roles, list_of(:role_label)` — `users_types.ex:81`.
2. `:role_label` is a free-form scalar, not an enum: `parse_label/1` downcases the string and calls
   `Glific.safe_string_to_atom/2` (`generic_types.ex:139-149`, `lib/glific.ex:443-454`). That is
   `String.to_existing_atom/1`, and `:glific_admin` already exists in the atom table because it is a
   member of the `user_roles_enum` Ecto enum (`lib/glific/enums/ecto_enums.ex:96-100`,
   `lib/glific/users/user.ex:85`). So `"glific_admin"` parses successfully.
3. `Glific.Users.update_user/2` (`lib/glific/users.ex:109-131`) calls
   `check_access_role/2`, which **only** overwrites `attrs.roles` when `add_role_ids` is present and
   non-empty (`users.ex:146-166`). Send `roles:` **without** `add_role_ids` and the client value
   passes through untouched into `User.update_fields_changeset/2`, which casts `:roles`
   (`lib/glific/users/user.ex:150-160`).

**The pinning tests.** `test/glific_web/schema/user_test.exs:209-236` — a **manager** updates
"NGO Staff" with `roles: ["Staff", "Admin"]` and the test *asserts the update succeeds*:

```elixir
assert user_result["roles"] == roles   # ["Staff", "Admin"]
```

Because `Authorize.valid_role?/2` uses `Enum.any?/2` (`authorize.ex:42`), a `roles` list of
`[:staff, :admin]` satisfies every `:admin` gate. The companion test at `user_test.exs:262-287`
("update a user of higher role should give an errors") documents the intended model explicitly — it
only fails because the *target* is an admin. Together these two tests encode "protect the target's
existing rank" as the design, with no notion of "authorize the requested rank."

### Where the reported impact understates the problem

The report describes self-escalation (`updateUser(id: <own>, roles: ["glific_admin"])`). That works —
`hd(own.roles)` is `:manager`, and `valid_role?([:manager], :manager)` is `true`. But there are three
further paths the report misses:

- **Escalating any lower-ranked user**, not just self — a manager can promote any `:staff` or `:none`
  user in the org to `:glific_admin`. Test `user_test.exs:288-313` demonstrates exactly this shape
  (manager promotes a `:none` user to `:manager`) and passes.
- **Role stacking.** `roles` is an array and `valid_role?/2` is `Enum.any?`. Setting
  `["staff","glific_admin"]` grants glific_admin while `hd/1` still returns `:staff`, so the account
  *continues to look low-privilege* to this very check — the escalated account can be re-edited by
  any manager, and reads as "Staff" first in the UI.
- **Session invalidation does not fire.** `users.ex:116-121` only calls
  `delete_all_user_sessions/2` when `add_role_ids`/`delete_role_ids` changed or `is_restricted`
  changed. A pure `roles:` write changes privileges without touching sessions. Whether this makes the
  escalation immediate or next-login depends on whether roles are re-read per request — see
  Report 3, "one defect, three enforcement layers".

**Robustness note (not a security issue):** `hd(user.roles)` at `users.ex:83` raises on an empty
`roles` list. The column defaults to `[:none]` (`user.ex:85`) and `update_fields_changeset` requires
`:roles`, so this is not currently reachable, but it is a `MatchError` waiting on any code path that
clears the array.

---

## Finding 2 — `deleteUser` performs no target-role check

### Verdict: CONFIRMED.

`lib/glific_web/resolvers/users.ex:120-124`:

```elixir
def delete_user(_, %{id: id}, %{context: %{current_user: user}}) do
  with {:ok, user} <- Repo.fetch_by(User, %{id: id, organization_id: user.organization_id}) do
    Users.delete_user(user)
  end
end
```

There is no role comparison of any kind — not even the (flawed) `valid_role?(…, hd(user.roles))`
that `update_user` at least attempts. The gate is `middleware(Authorize, :manager)`
(`users_types.ex:133-136`). `Glific.Users.delete_user/1` (`lib/glific/users.ex:194-205`) logs the
deletion and invalidates sessions, but adds no authorization.

The reconnaissance step in the report also holds: `users` is gated `:staff` (`users_types.ex:98-102`)
and the `:user` object exposes `field :roles` (`users_types.ex:22`), so a manager can enumerate
targets and their roles before deleting. (`is_restricted` is hidden from staff at
`users_types.ex:27-33`, but `roles` is not hidden from anyone.)

**Correction to stated impact.** The blast radius is the caller's own organization — `Repo.fetch_by`
is org-scoped on line 121. A manager can delete their org's admins, and can delete a `:glific_admin`
account *if that account is a member of their organization*. It is not a route to deleting SaaS
operators in other tenants. Within one tenant, the lockout + chained-with-finding-1 argument is
sound.

**Contrast worth noting:** the existing test `user_test.exs:194-207` deletes a fixture user as a
manager and asserts success — so, as with finding 1, the permissive behaviour is pinned.

---

## Finding 3 — the global `languages` table is writable at `:manager`

### Verdict: CONFIRMED. This is the cleanest cross-tenant finding of the five.

**The table is global.** `lib/glific/settings/language.ex:26-27`:

```elixir
@schema_prefix "global"
schema "languages" do
```

There is no `organization_id` column and no `belongs_to :organization`.

**Tenant scoping is explicitly skipped for it.** `lib/glific/repo_helpers.ex:377-394`:

```elixir
cond do
  opts[:skip_organization_id] ||
    opts[:schema_migration] ||
    opts[:prefix] == "global" ||
    query.from.prefix == "global" ||        # <- languages hits this
      sub_query?(query) ->
    {query, opts}
```

So the usual multi-tenancy backstop does not apply. The GraphQL gate is the *only* control.

**The gate is `:manager`, and it covers all three mutations** — the report only names `updateLanguage`,
but `lib/glific_web/schema/language_types.ex:80-97` gates `create_language`, `update_language` **and**
`delete_language` at `:manager`. `deleteLanguage` is arguably worse than the reported update: it
removes a row every other tenant's templates and flows reference.

**The asymmetry the report identifies is real, and inverted.** Compare `provider_types.ex`:

| Table | Tenant scope | Read gate | Write gate |
|-------|--------------|-----------|------------|
| `providers` | **org-scoped** | `:admin` (`provider_types.ex:58`) | `:glific_admin` (`:90-105`) |
| `languages` | **global / cross-tenant** | `:staff` (`language_types.ex:73`) | `:manager` (`:80-97`) |

The table with the *wider* blast radius has the *weaker* gate, by two full levels. Any manager in any
tenant can flip `is_active` or rewrite `locale` on a language row that every other organization's
localization depends on.

---

## Finding 4 — `/flow-editor/*` routes have no role authorization

### Verdict: route-level gap CONFIRMED. Exploit chain UNVERIFIED — see caveat.

**Confirmed from `lib/glific_web/router.ex:150-208`:** the entire `/flow-editor` scope pipes through
`[:api, :api_protected]` only. There is no role plug and no `Authorize` equivalent. The scope
includes writes: `POST /flow-editor/revisions/*vars` (`router.ex:191`), `POST /flow-editor/fields`,
`POST /flow-editor/groups`, `POST /flow-editor/labels`, `POST /flow-editor/flow-attachment`. Reads
include `/flow-editor/sheets`, `/globals`, `/flows/*`, `/revisions/*`.

The GraphQL equivalents of several of these are gated `:manager` or higher, so the REST surface is a
strictly weaker path to the same data and the same writes. Full per-action comparison is in
**Report 2**, which treats this as a class rather than an instance.

**What I am NOT asserting.** The source finding self-flagged "PARTIALLY VERIFIED: reproduce the
draft-trigger execution," and I did not reproduce it either. The following remain unverified and
should not be reported as fact:

- that a saved malicious revision is reachable via `draft:<keyword>` and executes;
- that `call_webhook` exfiltration and phishing `send_msg` fire from the org's verified number;
- the stated actor, "a revoked `:none`-role user." Whether a `:none` user can obtain a valid token
  at all is a separate question about the login path — resolved in Report 2, TASK 4. Note that
  `Authorize.valid_role?/2` rejects `:none` users from *every* GraphQL field, including
  `:none`-gated ones (`authorize.ex:39-40` requires membership in
  `[:glific_admin, :admin, :manager, :staff]`), which is what makes the REST bypass interesting —
  but "rejected by GraphQL" does not by itself establish "can still authenticate."

**Report the confirmed claim, which is serious on its own:** any principal holding a valid API token —
regardless of role, including `:staff` and `:none` if they can authenticate — can read and overwrite
flow definitions through REST, bypassing the `:manager` gate that governs the same objects in GraphQL.

---

## Finding 5 — two `:staff` exports bypass the restricted-staff permission filter

### Verdict: CONFIRMED, with the impact scope corrected from cross-tenant to intra-tenant.

**What "restricted staff" means.** `lib/glific/repo_helpers.ex:340-347`:

```elixir
def skip_permission?(user \\ get_current_user()) do
  cond do
    is_nil(user) -> raise(RuntimeError, message: "Invalid user")
    user.is_restricted and Enum.member?(user.roles, :staff) -> false
    true -> true
  end
end
```

Row-level filtering applies to exactly one population: users with `is_restricted == true` **and**
`:staff` in `roles`. For them, `Repo.add_permission/3` (`repo_helpers.ex:359-365`) applies the
context's filter — for groups, `Groups.add_permission/2` (`lib/glific/groups.ex:43-47`) inner-joins
`user_groups` so only assigned collections are visible.

**Path A — `exportCollection`.** Gate is `:staff` (`group_types.ex:124-126`). Resolver
`lib/glific_web/resolvers/groups.ex:36-38` passes the client id straight through.
`Groups.export_collection/1` (`lib/glific/groups.ex:177-190`) queries `ContactGroup` joined to
`Contact`, selecting `[c.name, c.phone]` with **no** `Repo.add_permission` call. Its immediate
neighbour `get_group!/1` (`groups.ex:166-172`) *does* call it — the omission is visible in a
five-line diff.

**Path B — `organizationExportData`.** Gate is `:staff` (`organization_types.ex:325-330`). Resolver
`lib/glific_web/resolvers/partners.ex:160-164` calls `Export.export_data(user.organization_id, …)`.
`lib/glific/partners/export.ex` builds **raw SQL** (`sql/3` at `:157-166`, `SELECT JSON_AGG(t) FROM
(SELECT * …)`), so it bypasses Ecto entirely — `prepare_query` and `add_permission` are both
structurally out of the picture. `@tables` (`export.ex:13-25`) covers `contacts`, `messages`,
`messages_media`, `locations`, `flows`, `flow_results`, `groups`, `interactive_templates`,
`organizations`, `organization_data`, `profiles`. `SELECT *` on `contacts` and `messages` means full
phone numbers, contact `fields` JSONB, and message bodies.

**Correction to stated impact.** The report says "cross-tenant" is not claimed, and that is right —
but state it positively, because it is the difference between a High and a Critical: both paths are
**org-scoped**. Path B interpolates `user.organization_id` from the session
(`export.ex:169-174`); Path A runs through `prepare_query` on `ContactGroup`, which carries
`organization_id`. The finding is **intra-tenant privilege bypass**: a restricted staff member reads
beneficiary PII for the whole organization instead of only their assigned collections. The report's
own note that credentials and users are not in `@tables` is correct (`export.ex:13-25`).

Rate limiting is absent — `export.ex:41` carries the comment `# Add a rate limiter here, once per
minute or so per organization`, unimplemented. The 500-row cap (`export.ex:44-45`) is per call, with
a client-controlled `offset`, so it bounds nothing.

---

## Cross-cutting observation

The five findings are three distinct failure modes, not five instances of one:

1. **No input-content authorization** (finding 1) — the operation is gated, the *payload* is not.
2. **Silent omission of a non-mandatory check** (findings 2 and 5) — `add_permission` and the
   resolver-level role comparison are opt-in calls, so forgetting them fails open and looks
   identical to code that never needed them.
3. **A second, ungated door to the same resource** (findings 3 and 4) — global-prefix tables escape
   `prepare_query`; REST routes escape `Authorize`.

Mechanisms for each are in Report 3.
