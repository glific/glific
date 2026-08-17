# Report 2 — Deep scan: additional RBAC gaps across backend and frontend

**Scope:** systematic sweep beyond the 5 reported findings — GraphQL gate inventory, REST surface, public endpoints, and frontend page/API consistency.
**Status of this file:** backend + REST sections are complete and independently verified. Frontend consistency matrix is appended at the end when the frontend sweep lands.

> **Status:** the `collectionStats` cross-tenant leak below, plus `bspbalance`, the inverted phone
> redaction, and the export gates, are **FIXED** (Report 3, "Fix 0"). Still open: the 29 ungated
> REST routes (§A), the 17 ungated subscriptions (§G2), unsigned BSP webhooks (§D), the
> `add_permission` gaps for Messages/Profiles (§H), and the frontend route-tree issues (§F).
> Line numbers describe the code **as audited**.

## The single most severe finding: `collectionStats` is a cross-tenant read at `:staff`

This is more severe than any of the five reported findings, and no reported finding covers it.

`lib/glific_web/schema/search_type.ex:192-197` declares `arg(:organization_id, non_null(:id))` and
gates the field at `:staff`. The resolver (`lib/glific_web/resolvers/searches.ex:48-50`) destructures
that client-supplied id and passes it through **without any comparison to `user.organization_id`**:

```elixir
def collection_stats(_, %{organization_id: org_id}, _) do
  {:ok, CollectionCount.collection_stats([org_id], true)}
end
```

`Partners.org_id_list/2` (`lib/glific/partners.ex:1395-1403`) simply integer-casts whatever list it
is handed. `contact_organization_query/1` (`:1410-1417`) then filters `c.organization_id in
^org_id_list` — the *attacker's* list. And the execution disables the tenant backstop outright,
`lib/glific/searches/collection_count.ex:86-93`:

```elixir
|> Repo.all(skip_organization_id: true)
```

**Impact:** any `:staff` user in any tenant reads contact statistics — All / Unread / Not-responded /
Not-replied / Optin / Optout counts — for **any other organization on the platform**, by passing that
org's id. Org ids are small sequential integers. `prepare_query` cannot save this because
`skip_organization_id: true` is explicit.

**Why this class was missed:** `Middleware.AddOrganization` uses `Map.put_new/3`
(`lib/glific_web/schema/middleware/add_organization.ex:37`), so a **client-supplied
`organization_id` argument always wins** over the injected one. Every operation that declares
`arg(:organization_id, …)` must therefore re-pin it in the resolver. `Resolvers.Billings`
does this correctly via `target_org_id/2` (`billings.ex:131-133`, glific_admin only);
`collection_stats` is the one non-`glific_admin` operation that declares the arg and does not.

**Recommended action: fix this first.** The patch is two lines — ignore the arg and use
`user.organization_id` — and it closes a genuine cross-tenant data leak.

---

## Headline numbers

| Metric | Value | Source |
|---|---|---|
| GraphQL fields across `*_queries`/`*_mutations`/`*_subscriptions` | 343 | full schema parse |
| Gated with `middleware(Authorize, …)` | 325 | — |
| **Ungated** | **18** (1 query + 17 subscriptions) | see section G |
| Gate distribution | 154 `:staff` · 118 `:manager` · 30 `:admin` · 23 `:glific_admin` | — |
| Uses of `:any` / `:none` gates | **0** | two branches of `valid_role?/2` are dead code |
| REST routes behind `:api_protected` with a role check | **0 of 29** | section A |
| Tests asserting schema-wide gate coverage | **0** | `test/glific_web/schema/middleware/` holds only `require_feature_flag_test.exs` |

Two structural facts underpin everything below, both verified:

- **There is no default gate.** `lib/glific_web/schema.ex:265` applies only `AddOrganization`,
  `SafeResolution`, and the error middlewares. A field without an explicit `Authorize` line is
  reachable by any authenticated user, role `:none` included.
- **A `:none` user is rejected by every gated field.** `authorize.ex:39-40` handles the `:staff` and
  `:none` *thresholds* in one clause, but that clause requires the caller to hold one of
  `[:glific_admin, :admin, :manager, :staff]` — which `:none` does not. This matters for reading the
  rest of the report: the 18 **ungated** fields and the 29 REST routes are the only places a `:none`
  principal gets through, which is precisely what makes them worth the attention below.

---

## A. The REST surface has no role enforcement at all — 29 routes

This generalizes reported finding 4 from one scope to the whole non-GraphQL surface.

### The pipeline is presence-only

`lib/glific_web/router.ex:50-53` — `:api_protected` runs `Pow.Plug.RequireAuthenticated` plus
`GlificWeb.ContextPlug`. `RequireAuthenticated` halts if and only if `current_user == nil`.
`ContextPlug` (`lib/glific_web/plugs/context_plug.ex:22-40`) puts the user into the process
dictionary and the Absinthe context — it **reads no roles and rejects nobody**.

So for REST, "authenticated" is the entire authorization model. A `:none` token and a
`:glific_admin` token are indistinguishable to every controller.

A grep for `valid_role?|Authorize|roles|:admin|:manager|:staff` across all REST controllers returns
exactly one hit — `flow_editor_controller.ex:212`, the literal string `roles: ["send", "receive"]`
inside a static WhatsApp-channel JSON blob. **There is no role logic in any REST controller.**

### REST vs GraphQL gate delta (verified)

Every row requires only a valid token over REST:

| REST action | file:line | GraphQL equivalent | GraphQL gate | Delta |
|---|---|---|---|---|
| `POST /flow-editor/revisions/*` `save_revisions` | `flow_editor_controller.ex:564` | `update_flow` / `publish_flow` | **`:manager`** | **any role → `:manager` write** |
| `GET /flow-editor/sheets` | `:606` | `sheets` | **`:manager`** | any role → `:manager` read (incl. Sheet URLs) |
| `POST /flow-editor/fields` | `:137` | `create_contacts_field` | **`:manager`** | any role → `:manager` write |
| `GET /flow-editor/fields` | `:104` | `contacts_fields` | **`:manager`** | any role → `:manager` read |
| `POST /flow-editor/groups` | `:63` | `create_group` | **`:manager`** | any role → `:manager` write |
| `POST /flow-editor/labels` | `:188` | *no create mutation exists* | n/a | write reachable **only** via ungated REST |
| `GET /flow-editor/revisions/*`, `/flows/*` | `:553`, `:509` | `flow` / `flows` | `:staff` | any role → `:staff` |
| `GET /flow-editor/recents/*`, `/activity` | `:628`, `:466` | — | — | verbatim recent end-user message text |
| `GET /flow-editor/users`, `/recipients` | `:91`, `:415` | `users` / `contacts` | `:staff` | any role → `:staff` |
| `POST /flow-editor/flow-attachment` | `:587` | `upload_media` | `:staff` | uploads to the org's GCS bucket |
| `POST /api/v1/get-embed-token` | `superset_controller.ex:19` | — | — | feature-flag check only, no role |

### Two additional defects inside these actions (verified in source)

**A1 — `get_flow_revision/2` ignores the flow it is given.** `lib/glific/flows.ex:455-458`:

```elixir
def get_flow_revision(_flow_uuid, revision_id) do
  revision = Repo.get!(FlowRevision, revision_id)
```

The first parameter is discarded. Cross-org access is still blocked by `prepare_query` (org is set
by `Plug.put_organization` on every request), but **any revision id within the org is readable
regardless of the flow named in the path**, and ids are sequential integers.

**A2 — `save_revisions` is an unvalidated overwrite primitive.** `flow_editor_controller.ex:564-568`
passes the entire request body into `Flows.create_flow_revision/2`, which resolves the target flow
*solely* from `definition["uuid"]` (`flows.ex:465`) and inserts with no shape validation. Any
authenticated user of the org can overwrite the draft definition of any flow in that org.

This is the mechanism behind reported finding 4. I still have not reproduced the draft-trigger
*execution* step, so the confirmed claim remains "unauthorized write of flow drafts", not
"arbitrary WhatsApp send".

### A3 — the actor in finding 4 is confirmed, with a nuance worth stating

Verified at `lib/glific_web/controllers/api/v1/session_controller.ex:16-22`: login checks
`%Organization{status: :active}` and the password. **There is no role check on login.** Confirmed at
`lib/glific/users/user.ex:82-111`: the `users` table has **no `is_active`/`disabled`/`suspended`
column** — `confirmed_at` exists but is never consulted on any auth path.

So "revoked" in Glific means *demoted to `:none`*, and a `:none` user can always re-login and obtain
a token that satisfies `:api_protected`. Demotion via `add_role_ids` does kill existing sessions
(`lib/glific/users.ex:118-122`), but the user simply logs in again. The only true revocation is
deletion.

---

## B. Session invalidation is conditional — a new finding

`lib/glific/users.ex:116-122`:

```elixir
if validate_add_role_ids?(attrs) ||
     updated?(user.is_restricted, attrs[:is_restricted]) ||
     validate_delete_role_ids?(attrs) do
  GlificWeb.APIAuthPlug.delete_all_user_sessions(@pow_config, user)
end
```

Sessions are purged only when `add_role_ids`, `delete_role_ids`, or `is_restricted` changed — **not
when the bare `roles` field changed**, which `users_types.ex:81` exposes as a first-class input and
`User.update_fields_changeset` casts directly (`user.ex:150-160`).

Combined with token caching — `APIAuthPlug.create/3` stores the **whole `%User{}` struct, roles
included**, in `CredentialsCache` (`api_auth_plug.ex:79-83`), and `get_credentials/3` returns it
verbatim with no DB reload (`:33-43`), TTL 30 minutes (`:45`) — this produces two symmetric bugs:

- **Demotion doesn't take effect.** `updateUser(roles: ["none"])` with no `add_role_ids` strips a
  user's privileges in the DB while their existing token keeps presenting `admin`/`manager` to the
  `Authorize` middleware for up to 30 minutes.
- **Escalation is delayed, not prevented.** The same caching is why reported finding 1 says "after
  re-login". It is a 30-minute delay on an attack, not a control.

---

## C. Six additional backend issues found while tracing

**C1 — `check_access_role/2` fails open to `:manager`.** `lib/glific/users.ex:157-164` ends with
`true -> ["manager"]`. Any custom role whose label doesn't match one of five hardcoded strings
silently grants legacy `:manager`.

**C2 — the super-admin label never matches.** The same `cond` tests `"Glific Admin"` (with a space,
`users.ex:162`) but the role is seeded as `"Glific_admin"` (underscore,
`lib/glific/seeds/seeds_dev.ex:1804`). That branch is unreachable, so a Glific_admin dynamic-role
assignment falls through to the C1 fallback and yields `:manager`.

**C3 — the dynamic-role system covers list queries only.** `AccessControl.check_access/2` is called
from exactly three sites: `Groups.list_groups` (`groups.ex:63`), `Triggers` (`triggers.ex:345`),
`Flows.list_flows` (`flows.ex:45`). The by-id accessors are bare `Repo.get!`:
`Flows.get_flow!/1` (`flows.ex:219-223`) and `Triggers.get_trigger!/1` (`triggers.ex:312-316`).
**A user filtered out of the list can still fetch the object by id.**

**C4 — dynamic roles no-op unless a flag is on.** `check_access/2` short-circuits on
`Flags.get_roles_and_permission(organization)` (`access_control.ex:260`,
`lib/glific/misc/flags.ex:172`), a FunWithFlags check that is off by default. It *also* requires
`organization_role?/1` (`:270-274`), which returns true only when the user holds **none** of
Admin/Manager/Staff. The entire subsystem is inert for every standard-role user.

**C5 — `languages` is not the only global-prefix table.** The `@schema_prefix "global"` escape in
`prepare_query` (`repo_helpers.ex:383-384`) means any such table loses tenant scoping. Finding 3
covers `languages`; the same class needs an audit for every other global table, since the GraphQL
gate is the sole control.

**C6 — feature-flag and dashboard UIs sit behind one shared password.** `/feature-flags`
(`router.ex:38-41`) exposes the FunWithFlags admin UI — **read and write** — and `/dashboard`
(`:97`) exposes LiveDashboard, both gated by `Plug.BasicAuth` with a single global
username/password (`:232-236`). No per-user attribution, no org scoping. Whoever holds it can flip
`roles_and_permission` (C4) for any org.

---

## D. Public endpoints — writes with no authenticity check

Verified: `grep -rn "signature|hmac|secure_compare|x-api-key" lib/glific_web/providers/` returns
**zero hits across the entire provider tree.**

| Endpoint | Accepts | Check | Verdict |
|---|---|---|---|
| `POST /gupshup/*`, `/gupshup-enterprise/*`, `/maytapi/*` (`router.ex:117-121`) | Inbound messages + billing/template events. `Shunt.build_context` installs the **org root user** as the `Repo` current_user (`providers/gupshup/plugs/shunt.ex:20-24`), then dispatches on attacker-controlled `params["type"]` | **NONE** | **Unauthenticated writes executing as root user** |
| `POST /webhook/flow_resume` (`:130`) | Resumes a parked flow in the subdomain's org | **NONE** | Unauthenticated flow control |
| `POST /kaapi/*` (`:135-140`) | LLM callbacks written into Assistants / PromptGenerator / AIEvaluations state | **NONE** — the module documents its own posture as "request_id treated as an unguessable token" | Unauthenticated writes |
| `POST /api/v1/onboard/update-registration-details` (`:74`) | **Mutates registration data of any `org_id` the caller supplies**, running as that org's root user (`onboard_controller.ex:33-40`) | **NONE** — no captcha, no token, no ownership check. `get_registration/1` is `Repo.fetch_by(Registration, id: registration_id)` (`registrations.ex:34-36`), a sequential integer | **Cross-tenant write via IDOR** |
| `GET /webhook/exotel/optin` (`:131`) | Opts a phone in and starts a flow | Caller's phone must match an org exotel credential | Weak, parameters guessable |
| `POST /webhook/stripe` (`:129`) | Billing events | **Signature verified** (`plugs/stripe_webhook.ex`) | OK |
| `POST /dify/chatbot-diagnose` (`:144`) | Table/query spec | **Shared secret via `Plug.Crypto.secure_compare`, fails closed** (`chatbot_controller.ex:59-68`) | OK |

Stripe and Dify show the codebase knows how to verify a webhook. The BSP providers — the
highest-volume, highest-trust inbound path — simply don't.

Note `POST /api/v1/registration/reset-password` (`:68`) resets a password and mints a token on OTP
alone, with **no org-status check** — bypassing the suspended-org gate that `session_controller.ex`
applies to normal login.

---

## E. Frontend — session storage and the trust boundary

`glific-frontend/src/services/AuthService.tsx:108-122` stores the user object, roles included, in
**`localStorage`** under `glific_user`; `getUserSession('roles')` reads it back. `context/role.ts:15-24`
memoizes that into a module-level `role` array driving every UI decision.

This is the correct pattern *provided* the UI is treated as cosmetic and the server re-authorizes —
which is exactly why the REST gap in section A matters. `localStorage` is attacker-editable, so
`role.ts` is not a security boundary and cannot be made into one. The relevant question is never
"can a user edit localStorage to see the admin menu" (yes, and that is fine) but "does every API
that menu reaches enforce the role server-side" — and for the 29 REST routes, no.

Two structural notes:

- **`AuthenticatedRoute.tsx:237-268` swaps whole route trees**, not per-route guards. A user is
  either in `staffRoutes` or the full `adminRoutes`. There is no per-page role declaration, so
  page-level authorization cannot be expressed even where the API distinguishes.
- **`checkDynamicRole()` routes any non-standard role into the full admin tree**
  (`role.ts:33-44`, `AuthenticatedRoute.tsx:242`). Combined with C1 — where a custom role grants
  backend `:manager` — a custom role gets the admin UI *and* manager API rights, neither of which
  its definition necessarily specifies.

---

## G. The 18 ungated GraphQL fields

**G1 — `bspbalance` (`provider_types.ex:62-65`) is the only ungated query in the schema.** Verified:
the field has a `resolve` and no `middleware` line, while every sibling in the same file
(`provider` `:58`, `providers` `:71`, `count_providers` `:78`, `quality_rating` `:84`) is `:admin`.
Resolver → `Partners.get_bsp_balance/1` scoped to the caller's own org, so this is an
**intra-org information leak** (BSP wallet balance readable by any authenticated user, including
`:none`), not a cross-tenant one. Low severity, trivial fix, and a clean example of gate-by-omission.

**G2 — all 17 subscriptions are ungated, and their `config` is a tenant check, not a role check.**
`Schema.config_fun/2` (`schema.ex:310-318`) compares `args.organization_id` to
`user.organization_id` and nothing else. Two consequences:

- A `:none` user — rejected by every gated query — can subscribe to `received_message` /
  `sent_message` and receive the org-wide firehose of inbound and outbound WhatsApp traffic.
  **This is the most direct contradiction of the role model in the schema**: the same data that
  `messages` gates at `:staff` streams to anyone with a token.
- Subscription topics are org-wide, so **`is_restricted` staff receive messages for contacts outside
  their assigned collections**. The row-level `add_permission` model does not apply to the pubsub
  path at all — making this a third bypass of the same boundary as reported finding 5.

## H. Row-level permission (`add_permission`) — omissions beyond finding 5

Reported finding 5 named two bypasses. The full picture: `add_permission` is an **opt-in call at
each query site**, and entire resource families never call it.

| Resource | Coverage | Notable omissions |
|---|---|---|
| Contacts | good (6 sites) | `list_contact_history`/`count_contact_history` (`contacts.ex:1009,1024`) — restricted staff read any contact's flow/state history. Resolvers for `update_contact`/`delete_contact`/`contact_location` (`resolvers/contacts.ex:58,119,131`) use raw `Repo.fetch_by`, bypassing `Contacts.get_contact!/1` — org-scoped but **not** collection-scoped |
| Groups | good (5 sites) | `export_collection` (finding 5); `list_organizations_groups` passes `skip_permission = true` hard-coded (`groups.ex:94`) |
| Searches | good (7 sites) | — |
| **Messages** | **none — no `Messages.add_permission` exists** | `list_messages/1` with `filter: {contact_id: N}` (`messages.ex:44`) and `Conversations.do_get_message_ids/3` (`conversations.ex:37-46`) reach message bodies directly. Restricted staff are filtered at the *contact* layer for `search`, but not on these paths |
| **Profiles** | **none** | `list_profiles/1` accepts `filter: {contact_id: …}` (`profiles.ex:32-39`); `get_profile!/1` is a bare `Repo.get!` |
| **Export** | **none — raw SQL** | finding 5, path B |
| Flows/Triggers | different system (`AccessControl`) | see C3/C4 — list-only, and inert by default |

The pattern: **five different mechanisms guard row-level access** (`add_permission`,
`AccessControl.check_access`, per-field resolvers, resolver-level `valid_role?`, and the
`upload_contacts` boolean at `contacts/import.ex:79`), none mandatory, each covering a different
subset of resources.

## I. Gate-consistency anomalies worth triaging

Verified spot-checks; full table in the inventory. These are cases where sibling operations on the
same resource carry different gates, which usually signals an oversight rather than a decision:

| Anomaly | Detail |
|---|---|
| **`contact.phone` redaction is inverted** | `contact_types.ex:50-56`: `if Enum.member?(user.roles, :staff) && !user.is_restricted, do: {:ok, ""}, else: {:ok, contact.phone}`. An **unrestricted** staff member gets `""`; a **restricted** staff member — the more limited role — gets the real phone number. Verified verbatim. Almost certainly a logic bug, and it undercuts finding 5's redaction argument |
| `clear_messages` `:staff` vs `delete_message` `:admin` | `message_types.ex:325` vs `:319` — bulk destructive delete is gated *lower* than single delete |
| Assistant CRUD at `:staff` | `assistant_types.ex:188-235` — 7 mutations incl. `set_live_version`, changing production bot behaviour and incurring provider cost; every comparable config CRUD (flow, trigger, sheet, form) is `:manager` |
| Collection membership at `:staff` | `contact_group_types.ex:88-100` — collection membership **is** the row-level ACL, so staff can mutate the boundary that restricts them, while the `user_groups` half is `:manager` (`user_group_types.ex:59-71`) |
| `create_access_role`/`update`/`delete` at `:manager` | `role_types.ex:68-81` — managers edit the org's own authorization config |
| `organization_export_config` at `:staff` | `organization_types.ex:332` — runs `skip_organization_id: true` against `information_schema.columns`: platform-wide schema disclosure |
| Certificate/template create-vs-delete splits | `certificate_types.ex:40,47` vs `:55`; `session_template_type.ex:226` vs `:238` |

---

## F. Frontend page ↔ API consistency matrix

### F0. How frontend authorization actually works

`AuthenticatedRoute.tsx:230-268` performs a **whole-tree swap**, not per-route guards:

```
:237  if (userRole.includes('Staff'))            route = staffRoutes        // 8 paths
:241  if (checkDynamicRole() || Manager || Admin || Glific_admin)
                                                 route = adminRoutes        // ~70 paths
```

The second `if` has no `else` and runs after the first, so it **overwrites** it. Three consequences:

1. There are exactly **two** authorization levels in the UI — staff, and everything else. Manager,
   Admin, Glific_admin and every dynamic role receive an **identical** route tree.
2. A user holding `Staff` *plus* a dynamic role gets the **Staff menu** (`role.ts:60-63` runs after
   the Dynamic block and last-write-wins) but the **admin route tree**. Menus and routes disagree by
   construction.
3. A user whose only role is `None` matches neither branch — `route` stays `undefined` and renders a
   blank page rather than redirecting.

**The menu is the only thing that distinguishes Manager from Glific_admin.** `getMenus`
(`menu.ts:350-356`) filters by `roles.includes(role)`, and `menu.ts:294,301` restrict Organizations
and Consulting to `['Glific_admin']`. But filtering a menu does not unregister a route.

### F1. The core finding — SaaS-operator pages render for Managers and dynamic roles

Every row: the route is registered for the role, the menu link is hidden, and typing the URL mounts
the container and fires its queries. The backend gate is the **only** control.

| Route | Menu says | Actually reachable by | Operations fired | Backend gate | Net |
|---|---|---|---|---|---|
| `/organizations` | Glific_admin only (`menu.ts:294`) | Manager, Admin, **dynamic** | `q:organizations`, `q:countOrganizations`, `m:deleteOrganization`, `m:updateOrganizationStatus` | `:glific_admin` (`organization_types.ex:284,292,390,396`) | **Backend holds.** Page renders, data calls fail |
| `/consulting-hours/` | Glific_admin only (`:301`) | Manager, Admin, **dynamic** | `q:consultingHours`, `m:create/update/deleteConsultingHour` | `:glific_admin` (`consulting_hour_types.ex:78-121`) | **Backend holds** |
| `/organizations/:id/extensions` | no entry at all | Manager, Admin, **dynamic** | `m:createExtension`, `m:deleteExtension`, `q:getOrganizationExtension` | `:glific_admin` (`extension_types.ex:45-80`) | **Backend holds** |
| `/organizations/:id/customer` | no entry | Manager, Admin, **dynamic** | `m:createBilling`, `m:updateBilling`, `q:getOrganizationBilling` | `:admin` (`billing_types.ex:77-115`) | **Gap for dynamic roles** — see F2 |
| `/settings/billing` | adminLevel (`:318`) | **Manager**, dynamic | `m:createBillingSubscription`, `m:updatePaymentMethod`, `q:customerPortal` | `:admin` (`billing_types.ex:64-121`) | Backend holds |
| `/settings/:type` (providers) | adminLevel | **Manager**, dynamic | `m:createCredential`, `m:updateCredential`, `q:credential` | `:admin` (`credential_types.ex:41-55`) | Backend holds |
| `/settings/organization` | adminLevel | **Manager**, dynamic | `m:updateOrganization`, `q:organization` | `:admin` / `:staff` | Backend holds on write |
| `/contact-management` | adminLevel (`:258`) | **Manager**, dynamic | `m:ImportContacts`, `m:MoveContacts` | `:manager` (`contact_types.ex:302,309`) | **REAL GAP — manager passes** |
| `/staff-management` | Manager+ but **dynamic excluded** (`:256`) | **dynamic roles** | `q:users`, `m:deleteUser`, `m:updateUser` | `:staff` / `:manager` | **REAL GAP — see F2** |
| `/role`, `/role/add` | Manager+ but **dynamic excluded** (`:292`) | **dynamic roles** | `m:createAccessRole`, `m:updateAccessRole`, `m:deleteAccessRole` | `:manager` (`role_types.ex:68-81`) | **REAL GAP — see F2** |

**The reassuring half:** for genuinely SaaS-operator-scoped data (organizations, consulting,
extensions), the backend gate is `:glific_admin` and holds. These rows are UX bugs — a Manager sees
a page that then errors — not privilege escalation.

**The dangerous half:** `contact-management`, `staff-management` and `role` are gated `:manager` or
lower on the backend, and the frontend hides them from a population the backend admits.

### F2. Dynamic roles are the systematic hole

`checkDynamicRole()` (`role.ts:33-44`) returns `true` for **any** role label outside
`['Admin','Manager','Staff','None','Glific_admin']`, which routes it into the full admin tree
(`AuthenticatedRoute.tsx:242`). Meanwhile `menu.ts` deliberately excludes `'Dynamic'` from Staff
management (`:256`) and Roles (`:292`) — the two pages that edit authorization itself.

Chained with backend finding **C1** (`users.ex:163`: any unrecognized role label falls through to
`["manager"]`), a custom role gets:

- the **full admin UI** (frontend, via `checkDynamicRole`),
- **`:manager` backend rights** (via the `check_access_role` fallback),
- reaching `/staff-management` and `/role` — pages the menu says dynamic roles must not see,
- where `updateUser` is gated `:manager` and, per **finding 1**, does not validate the requested role.

That is a complete escalation chain from "custom role with no permissions defined" to `:glific_admin`,
using only pages the UI renders.

### F3. The client-side escalation guard is broken by a string literal

`StaffManagement.tsx:147-155` filters the assignable-role dropdown:

```js
if (isManager) rolesList = rolesList.filter((i) => i.label !== 'Admin' && i.label !== 'Glific admin');
if (isAdmin)   rolesList = rolesList.filter((i) => i.label !== 'Glific admin');
```

`rolesList` is built from the server's `accessRoles` (`:140-145`), where the seeded label is
**`"Glific_admin"`** with an underscore (`seeds_dev.ex:1804`). `'Glific admin'` with a space never
matches. **The Glific_admin option remains in the dropdown for both Manager and Admin.**

The sibling check in `StaffManagementList.tsx:82` uses `'Glific_admin'` correctly, so the *list*
hides edit/delete on Glific_admin rows while the *form* offers the role. Two files, same concept,
different literal.

Combined with reported finding 1, this means the escalation does not require a crafted GraphQL
mutation — **a Manager can select "Glific_admin" from a dropdown in the normal staff-edit UI.**
This materially raises finding 1's exploitability from "attacker with API knowledge" to "any manager
who opens the staff page."

### F4. Where the frontend hides a control the backend would allow

These are real authorization decisions made **only** in the client. The mutation is gated at or
below the user's role, so a direct API call succeeds:

| Control hidden | Where | Hidden from | Mutation | Backend gate |
|---|---|---|---|---|
| Collection create/edit/delete buttons | `CollectionList.tsx:150,158`; `List.tsx:600` | Staff, **and Manager** (`manageCollections` is Admin-only, `role.ts:72`) | `createGroup`/`updateGroup`/`deleteGroup` | `:manager` — **a Manager can call these** |
| Saved-search save/update | `ChatConversations.tsx:210` | Staff, Manager | `createSavedSearch`/`updateSavedSearch` | `:manager` |
| Simulator panel | `ChatInterface.tsx:72-74` | Staff | `simulatorGet`/`simulatorRelease` | `:staff` — **staff can call these directly** |
| "Make primary" phone | `PhonesPanel.tsx:36,89` | non-Admin | `setPrimaryPhone` | `:admin` — backend holds |
| Reconnect / sync phone | `PhoneManagement.tsx:50,119` | non-Manager | `reconnectWaManagedPhone` | `:admin` / `:manager` |
| Roles multi-select on every form | `FormLayout.tsx:533-546` | non-Admin — and **Glific_admin too**, since `.includes('Admin')` doesn't match `'Glific_admin'` | `addRoleIds`/`deleteRoleIds` on many mutations | varies |

The `simulatorGet` and collections rows are the notable ones: the UI is the *only* thing preventing
a staff/manager user from performing an action the API permits.

### F5. Client-side role state is fully attacker-controlled and never refreshed

Verified (`AuthService.tsx:108-122`, `role.ts:4-24`): roles come from a `GET_CURRENT_USER` response
at login, are written to **`localStorage.glific_user`** as plaintext JSON, and are memoized into a
module-level `role` array on first read.

Editing that key to `{"roles":[{"label":"Glific_admin"}]}` and reloading yields the full admin tree
and the Glific_admin menu **with the original, legitimately-issued token still attached**. This is
expected for any SPA and is *not itself* the finding — it is the reason every row in F1/F4 must be
judged solely on its backend gate.

**No role refresh exists.** `setUserSession` is called from exactly one place (`Login.tsx:68`).
`MyAccount.tsx:286` re-reads the current user but writes only to the Apollo cache. So when an admin
changes a user's role, that user keeps their old route tree and menus **until they log out and back
in** — which compounds backend finding B (the server-side session cache also isn't invalidated on a
bare `roles` write). Demotion is not enforced on either side until the user voluntarily re-logs in.

### F6. Feature flags are not authorization

`/ticket`, `/certificates`, `/whatsapp-forms/*`, `/group/*`, `/ai-evaluations` are hidden from the
menu by `getOrganizationServices(...)` flags but remain **registered routes**. `organizationServices`
is likewise localStorage-backed with a one-write lifecycle (`Login.tsx:53`). Only
`/ai-evaluation-v2` has an actual element-level guard (`AIEvaluationGuard.tsx:12`) — the single
route in the app that guards itself.

Backend-side, `RequireFeatureFlag` gates ~13 fields (`ai_evaluation_types.ex`,
`session_template_type.ex:218`, `prompt_generator_types.ex:72`). These are toggles layered *on top
of* an `Authorize` gate, not a substitute — correct as used, worth stating because the frontend
treats flags and roles interchangeably.

### F7. Summary — where page and API disagree

| Category | Count | Risk |
|---|---|---|
| Pages reachable by a role the backend rejects | 8 routes | Low — UX bug; backend holds (`:glific_admin`/`:admin`) |
| **Pages reachable by a role the backend *accepts*, hidden only by menu** | **3** (`contact-management`, `staff-management`, `role`) | **High — real bypass for Manager/dynamic** |
| Controls hidden client-side but permitted by API | 6 classes | Medium — `simulatorGet`, collections CRUD |
| Client-side escalation guards that don't work | 1 (`StaffManagement.tsx:150`) | **High — raises finding 1's exploitability** |
| Routes with element-level guards | **1 of ~70** | Structural |

**The one-line answer to "if the API blocks staff, is the page also hidden?"** — mostly yes for
`staff`, because staff get a physically different 8-route tree. But the question doesn't generalize:
there is no per-page role declaration anywhere, so for the ~70 admin-tree routes the frontend makes
**no distinction at all** between Manager, Admin, Glific_admin, and arbitrary dynamic roles. Menu
filtering is the only differentiator, and it is cosmetic.
