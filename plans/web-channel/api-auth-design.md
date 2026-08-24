# Glific Web Channel — API Authentication

**Status:** Draft for review · **Author:** Vignesh Rajasekaran

How a partner organization's own application authenticates its end users against the Glific web
channel, how those end users are identified when they have no phone number, and how access is
revoked. Contact identity (§3) is channel-general and outlives the web channel. This replaces the prototype's phone-plus-OTP-only auth with **two modes** that share one
socket.

- **Mode A — Glific's own widget.** Phone + OTP, verified by Glific, exactly as today. Glific
  mints the token.
- **Mode B — API clients.** The NGO's backend mints an **HS256 JWT** locally, signed with a secret
  Glific issued it. The browser presents that JWT **directly** to the socket. Glific only verifies;
  it never mints and never sees the token before it is used.

Mode is a **per-organization configuration choice, not a runtime fallback** — Glific must never
silently downgrade to a weaker mode when a credential is missing.

---

## 1. Why the NGO mints locally

The alternative — the NGO's server calls Glific to exchange a long-lived API key for a client
token — puts a synchronous dependency on Glific inside the NGO's own login flow. For deployments on
poor connectivity that is the wrong trade.

Local minting is also what the market does. Intercom, Zendesk Messaging / Sunshine Conversations,
Stream Chat and Twilio Conversations all have the customer's backend sign a JWT with a shared
secret; only Sendbird uses a server-to-server exchange.

**No token exchange endpoint.** An earlier draft had the browser swap the NGO's JWT for a
Glific-issued session token so the socket would see a single credential type. That bought very
little — `connect/3` can branch on credential type in a few lines — and cost an endpoint, a second
token format and a second TTL. Dropped.

---

## 2. Token contract

### 2.1 The JWT

```
Header   { "alg": "HS256", "typ": "JWT", "kid": "gws_7f3a91c4" }

Claims   {
  "sub":   "member_4471",       // REQUIRED — the web identity. Opaque, max 255 chars.
  "org":   42,                  // REQUIRED — organization_id, cross-checked against kid
  "iat":   1755590400,          // REQUIRED — precondition for revoke-before-iat (§4.2)
  "exp":   1755591300,          // REQUIRED — short, see §2.4
  "phone": "+919876543210",     // OPTIONAL and dangerous — see §2.3
  "name":  "Asha",              // OPTIONAL enrichment
  "email": "asha@example.org"   // OPTIONAL enrichment
}
```

`iat` and `exp` are **required by Glific's verifier even though JWT makes them optional.** Intercom
and Zendesk both leave `exp` optional and then advise customers to set it, which makes the insecure
configuration the default. Stream makes `iat` mandatory only once revocation is configured. We
require both from day one, so no token can ever escape the revocation lever.

### 2.2 Verification rules

Each rule maps to a known failure mode.

1. **Pin the algorithm.** Reject unless the header says `HS256`. Never use the token's own `alg` to
   *select* the verification algorithm — that is `alg: none` and HS/RS confusion.
2. **Resolve the secret strictly by `kid`.** Never "try every key for this org"; that silently
   defeats rotation and keeps a revoked key alive.
3. **Reject a revoked key** (`revoked_at IS NOT NULL`).
4. **Require `sub`, `org`, `iat`, `exp`.** Clock leeway ≤ 60s.
5. **Cap the TTL server-side.** Reject `exp - iat` greater than one hour even if the NGO set it, so
   an integrator cannot ship year-long tokens.
6. **Cross-check three org values**: the `org` claim, the org owning the `kid`, and the org
   `SubdomainPlug` resolved from the Host header. Any mismatch → reject and log; it means key misuse
   or a cross-tenant attempt.
7. **Cap `sub` at 255 chars**, treat as opaque, unique per organization only.

### 2.3 The `phone` claim is the sharpest risk here

Because a human on WhatsApp and on web is **one contact** (§3), a JWT asserting `phone` binds the
web session to an existing contact — including its entire WhatsApp history. If the NGO's mint
endpoint derives `phone` from a request parameter rather than its own server-side session, anyone
can mint a token for someone else's number and take over that contact.

This is Stream's documented warning — *"an endpoint that returns a token for any user ID it is given
lets any caller impersonate any user"* — applied to an identifier with real history behind it. It is
also, in essence, the Chatwoot contact-merge vulnerability: with identity validation off, a browser
asserts an arbitrary identifier and the merge action repoints the attacker's session onto the
victim's contact.

**Mitigations, in order of strength:**

1. **First-link OTP.** The first time a `web` identity is bound to a contact that already carries a
   `whatsapp` identity, require a one-time OTP to that phone. Subsequent logins need none. Friction once per user, ever.
2. **Org-level opt-in** `allow_jwt_phone_binding`, default `false`. Without it a `phone` claim is
   ignored and a web-only contact is created.
3. **Integrator documentation** carrying Stream's warning verbatim, with a worked example deriving
   both `sub` and `phone` from the server-side session.

Ship 1 and 2. 3 is not a control, but omitting it guarantees the failure.

### 2.4 TTL, expiry mid-connection, and renewal

There is no industry consensus on TTL — Zendesk recommends "a few minutes", Twilio defaults to 1h
with a 24h cap and warns that under 300s is unreliable, Sendbird defaults to 7 days, Stream and
Intercom default to *no expiry at all*. We keep the renew period **short** and cap it at one hour.

A short TTL is only meaningful if something re-checks a **live** socket, since auth otherwise happens
once at `connect/3` and the effective session length becomes the connection length.

**Decision — periodic server-side sweep, then reconnect:**

- The socket stores `token_exp` in assigns at connect.
- `RoomChannel` runs a periodic check (`Process.send_after` → `handle_info/2`). Past `exp`, it
  pushes a **`session_expired`** event and stops the channel.
- The client re-mints from its **own** backend and reconnects. No in-place credential swap on a live
  socket, and no inbound re-auth message.
- If the user was offline longer than the TTL, this is the same path: the app regenerates a token
  before reconnecting.

Two consequences worth recording:

- **The sweep belongs in the channel, not the socket.** `Phoenix.Channel` gives `handle_info/2`;
  `Phoenix.Socket` has no equivalent user callback. A socket that connected but never joined is
  therefore never swept — acceptable, because no messages flow before a join.
- **The sweep interval, not the TTL, is the real granularity.** A token expiring at T dies at
  T + interval. Choose the interval deliberately.

### 2.5 Reconnect mechanics (client-side, recorded here because the backend depends on it)

`phoenix.js` takes `params` as *either* an object or a function (`utils.js` `closure/1`), and calls
`this.params()` on **every** connect attempt when building the endpoint URL. The prototype passes a
plain object, so the token is frozen at construction and every automatic reconnect replays a dead
credential forever. It must become a function reading current storage.

`params()` is synchronous, so it cannot itself perform a mint — the resume handler must
`disconnect()`, await a fresh token, then `connect()`.

Note also that phoenix.js reconnects **eagerly and without jitter**: `visibilitychange → visible`
calls `teardown(() => this.connect())` immediately, and the default `reconnectAfterMs` ladder ends at
a flat 5000 ms with no randomisation. Jitter must be added by us, including on the first attempt
after coming back online.

---

## 3. Contact identity

A human reaching an NGO on WhatsApp, on the web, and later on Telegram is **one contact** carrying
**one identity row per channel**.

Identity has to be per-channel because the namespaces are disjoint: a phone number, a web username
and a Telegram id are three different things, and one column can hold only one of them. This section
is therefore **channel-general, not web-specific** — the web channel is simply its first consumer,
and Telegram should arrive as a data migration rather than a schema migration.

### 3.1 Rejected: overloading `phone`

`phone` is already an opaque string in practice — simulator contacts hold values like
`"9876543210_1"` behind `@simulator_phone_prefix`. So storing `krish1231` there would "work".

The cost is already visible in the codebase. `Contacts.simulator_contact?/1` exists **only** to
answer "is this string a real reachable number?", and it is called in **14 places** across
`contacts.ex`, `messages.ex`, `consumer_tagger.ex`, `communications/message.ex`,
`bigquery_worker.ex` and both Gupshup workers. Each is a site where someone had to remember that
`phone` might be a lie. A second class of non-phone value means revisiting all fourteen with a
different predicate.

It also leaks downstream: `bigquery_schema.ex` exports `phone`, `sender_phone`, `receiver_phone`,
`contact_phone` and `user_phone`. NGOs query those. Putting usernames in them is a data-contract
change to systems we do not control.

### 3.2 Rejected: a single `username` column

An earlier draft of this document proposed one nullable `username` column beside `phone`. It fails
at the third channel: a web username and a Telegram id cannot share a column, so channel three
forces either an overloaded column (3.1 again) or a second column — and then a third, each with its
own unique index and its own branch in every lookup.

### 3.3 The model

```sql
CREATE TABLE contact_identities (
  id              bigserial PRIMARY KEY,
  contact_id      bigint NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id bigint NOT NULL REFERENCES organizations(id),
  channel         varchar(50)  NOT NULL,   -- 'whatsapp' | 'web' | 'telegram' | …
  identifier      varchar(255) NOT NULL,   -- phone | username | telegram id
  verified_at     timestamp,               -- how the link was proven (§2.3 first-link OTP)
  inserted_at     timestamp NOT NULL,
  updated_at      timestamp NOT NULL
);

CREATE UNIQUE INDEX contact_identities_org_channel_identifier_index
  ON contact_identities (organization_id, channel, identifier);
CREATE INDEX contact_identities_contact_id_index ON contact_identities (contact_id);
```

`organization_id` sits on the row so `Repo.prepare_query/3` auto-scopes it like every other table.
Uniqueness is scoped **per organization and per channel**, never globally — matching how Zendesk
scopes `external_id` per workspace.

Three deliberate choices around it:

**`contacts.phone` stays, as the reachability field.** It is not the identity field. The BSP send
path, opt-in/opt-out, exports, reports and the BigQuery schema all want "how do I reach this person
on WhatsApp", and that is a different question from "who is this". This is the same split described
in §3.6 — the difference is that it is now enforced by *which table you query* rather than by
discipline across 34 call sites. `phone` becomes nullable, but never synthetic.

**`contacts.channels` as a denormalized index only.** A contact's channel set is derivable
(`SELECT DISTINCT channel FROM contact_identities WHERE contact_id = ?`), but the staff inbox query
filters on it, so carry a `{:array, :string}` column with a GIN index. This is the same shape
`flows.channels` already uses, so the two models match.

**`contact_type` is left alone.** It is written by the Gupshup (`"WABA"`) and Maytapi (`"WA"`)
controllers and consumed by `reports.ex` and the `stats_live` pie charts. Adding `channels` is
additive; replacing `contact_type` is a downstream break for no present gain. Deprecate it later.

### 3.4 Linking identities is additive, not a merge

This is a security property, not only a modelling preference.

With a single identity column, linking Asha's web login to her existing WhatsApp contact means
rewriting the contact row — or, if two contacts already exist, a genuine merge that repoints
messages, groups and flow results. Irreversible, and done carelessly it is exactly the Chatwoot
vulnerability: `ContactMergeAction#merge_contact_inboxes` repoints the attacker's session, carrying
its auth token, onto the victim's contact record.

With `contact_identities`, the same link is one insert. It is reversible by deleting the row, and it
touches neither the WhatsApp identity nor any message history. The first-link OTP of §2.3 becomes a
gate on that insert rather than a gate on a destructive rewrite.

`verified_at` records **how** each identity was proven — OTP versus NGO-asserted JWT — which an
auditor, and possibly a flow author, will legitimately want to distinguish.

### 3.5 Making `phone` nullable breaks running code

Note this cost belongs to **supporting non-phone contacts at all**, not to any particular schema
choice: a web-only contact has no phone under any of the three models above.

| Location | Break | Fix |
|---|---|---|
| `Contacts.simulator_contact?/1` (`contacts.ex:971`) | `String.starts_with?(nil, _)` raises. 14 call sites; these pass `contact.phone` straight in: `contacts.ex:328,355,582,808`, `messages.ex:1197`, `consumer_tagger.ex:36`, `communications/message.ex:380`, `bigquery_worker.ex:976,1241` | add `def simulator_contact?(nil), do: false` — one clause covers all |
| `Contact.populate_masked_phone/1` (`contact.ex:151`) | `String.split_at(nil, 4)` raises. Reached from the GraphQL `maskedPhone` resolver, so any console query selecting it on a web-only contact 500s | nil clause returning `nil` |
| `Contacts.maybe_create_contact/1` (`contacts.ex:450`) | `Repo.get_by(Contact, %{phone: nil})` compiles to `WHERE phone IS NULL` — returns **an arbitrary** contact, or raises `Ecto.MultipleResultsError` once there are two. A cross-contact leak, not just a crash | resolve through `contact_identities`; never `get_by` a nil identity |
| `searches.ex:179`, `:259` | `where c.contact_type in ["WABA","WABA+WA"]` — a web contact is **silently absent from the staff inbox** | widen to consult `channels` in the same commit that adds it |
| GraphQL `contact_types.ex:50-54` | `phone` returns `""` for `:staff`, and `masked_phone` exists — a deliberate privacy control. An NGO identifier is often an email or member ID | gate identity fields identically |
| Flows | `@contact.phone` resolves empty for web-only contacts | document for NGOs |

### 3.6 The 34 lookup sites are a semantic audit, not a rename

There are 34 contact lookups keyed on phone in `lib/`, several inside per-NGO modules
(`clients/digital_green.ex`, `sol.ex`, `tap.ex`, `mukkamaar.ex`, `arogya_world.ex`) — thin test
coverage, so they break quietly. Each currently uses `phone` to mean one of two things and only a
human can tell which:

- *"who is this"* → resolve through `contact_identities`
- *"how do I reach them on WhatsApp"* → stays `contacts.phone`

`Contacts.contact_opted_in/4` is the second kind. `maybe_create_contact/1` and `Glific.Erase`
deleting by phone are the first. A mechanical substitution produces code that compiles and is wrong.

Identity-specific consequences beyond that audit:

- **`maybe_create_contact/1` is the hot path** for every inbound message and becomes an identities
  lookup. It needs the same on-conflict handling it has today for the opt-in / first-message race
  (issue #850), and it should be cached.
- **`contacts/import.ex`** (3 phone lookups) — CSV import stays phone-only in v1.
- **BigQuery** — identities are not exported in v1; decide later whether they get their own table.
- **`Glific.Erase`** deletes by phone and must become identity-aware, or it silently misses web
  contacts.
- **`Contact` gains `has_many :identities`**, alongside the existing `has_one :user`, three
  `many_to_many` and `belongs_to :active_profile`. Preloading matters on the inbox query.

### 3.7 Open question: can an identity move between contacts?

If an NGO reassigns `member_4471` to a different person, is that an update, a delete-and-insert, or
forbidden? This must be settled before dual-read (phase 0c, §7) — getting it wrong is how identity
tables accumulate orphaned history.

### 3.8 Prior art in the codebase

- **`phone` already holds non-dialable values** (§3.1) — the `simulator_contact?/1` tax is the
  measured cost of that pattern, and the reason a real identity model is worth the migration.
- **`contact_type`** already discriminates `"WABA"` / `"WA"` / `"WABA+WA"` with merge logic at
  `contacts.ex:1052-1067` — an early, string-concatenated attempt at exactly the channel set that
  `contacts.channels` now models properly.
- **`profiles`** is a persona switcher (one contact, many personas), **not** a second login. It is
  orthogonal to identities and should stay out of this design.

## 4. Signing keys and revocation

### 4.1 `web_channel_signing_keys`

```elixir
schema "web_channel_signing_keys" do
  field :kid,          :string                    # public, globally unique, e.g. "gws_7f3a91c4"
  field :secret,       Glific.Encrypted.Binary    # Cloak, via Glific.Vault
  field :label,        :string                    # "production", "staging"
  field :prefix,       :string                    # "gws_7f3a…" for the console list
  field :last_used_at, :utc_datetime
  field :revoked_at,   :utc_datetime
  belongs_to :organization, Organization
  timestamps(type: :utc_datetime)
end

@derive {ExAudit.Tracker, except: [:secret]}
```

Both the encryption type and the audit exclusion mirror `Glific.Partners.Credential`, which already
does exactly this for BSP secrets.

- **Who can mint:** role `:admin` (or `:glific_admin`). Not `:manager`, not `:staff` — a signing key
  mints a token for *any* contact in the org, strictly more powerful than the `phone` field `:staff`
  already cannot see.
- **Max 10 per organization** (non-revoked), so integrators can hold separate keys for staging and
  production while testing.
- **Secret displayed in full exactly once**, at creation.
- **`kid` is what makes rotation tractable**: add a new key, migrate the NGO's minting, revoke the
  old one. Stream has one secret per app and no `kid`, so its only rotation is "regenerate and every
  outstanding token dies at once" — unacceptable when the secret lives on a partner's server.

### 4.2 Revocation levers

| Lever | Who | Mechanism | Blast radius | Phase |
|---|---|---|---|---|
| Revoke a signing key | Org admin | `revoked_at` | every JWT signed with that `kid` | v1 |
| Drop live sockets | either | `Endpoint.broadcast("web_socket:#{contact_id}", "disconnect", %{})` | one contact's connections | v1 |
| Revoke one end user | Org admin / API | `contacts.tokens_valid_after` vs `iat` | that contact's tokens | later |
| Revoke an organization | Glific admin | `organizations.web_tokens_valid_after` | kill switch for a tenant | later |

Forced disconnect already works: `WebChannelSocket.id/1` returns a stable `"web_socket:#{contact.id}"`,
which is precisely Phoenix's hook for it.

**No table of issued tokens.** Glific never witnesses issuance — the NGO mints locally — so such a
table has no insert point except first *use*, at which point it only contains tokens that happened to
be presented. At a short TTL each active user mints 4–12 tokens an hour, and every reconnect adds
another, so it would be a high-churn table whose rows are worthless minutes later. Operationally, an
admin never wants to revoke *token `a3f9c1`*; they want to revoke a person or a key.

`tokens_valid_after` compared against a mandatory `iat` does the same job with one column, no writes,
and covers tokens Glific has **never seen**. This is exactly Stream's `revoke_tokens_issued_before`,
and their docs are explicit that *"tokens which have no `iat` will be considered invalid."* Zendesk
and Twilio offer key-level revocation only.

Do **not** copy Zendesk's `logoutUser` semantics: a client-side state reset is not revocation.

---

## 5. Library choice

**Use `erlang-jose` directly. Not Joken, not Guardian, not `guardian_db`.**

- **`guardian_db` cannot work here.** It is an allow-list: rows are written only by
  `after_encode_and_sign/4` (Guardian issuing) and `on_refresh/2`; `on_verify/2` only reads. A JWT
  Glific never minted has no row and fails with `{:error, :token_not_found}`. It also requires `jti`
  and `aud`. It is built for the exact inverse of this architecture.
- **Joken** fits the shape well — `Joken.peek_header/1` for `kid`, a runtime `Joken.Signer`, and
  algorithm pinning that is structural (the signer's `alg` is passed to `JOSE.JWT.verify_strict/3` as
  a one-element allow-list). But its last release is **2.6.2, August 2024**, and its claim validation
  has a trap: `reduce_validations/3` iterates over the claims *present in the token*, so a configured
  validator for `exp` or `iat` is skipped when the claim is absent. Since §2.2 requires presence
  checks, max-TTL bounds and the `iat` comparison to be hand-written anyway, the wrapper's remaining
  value is roughly twenty lines.
- **Guardian** is actively maintained (2.5.0, Aug 2026) and *can* do per-tenant resolution via a
  custom `SecretFetcher.fetch_verifying_secret/3`, but it is an issuing framework: its default
  `allowed_algos` is `["HS512"]`, and pinning and `kid` lookup are two independent knobs. Reasonable
  fallback if the team prefers a maintained dependency over hand-rolled.
- **`jose` is already in the tree** transitively via `goth` (pinned 1.11.10; 1.11.12 is current), and
  is the layer both wrappers sit on.

```elixir
with {:ok, %{"kid" => kid}} <- peek_kid(token),                    # JOSE.JWS.peek_protected/1
     {:ok, key}             <- SigningKeys.fetch_active(kid),      # DB; rejects revoked
     jwk                    =  JOSE.JWK.from_oct(key.secret),
     {true, %JOSE.JWT{fields: claims}, _jws} <-
       JOSE.JWT.verify_strict(jwk, ["HS256"], token),              # algorithm pinned HERE
     :ok <- require_claims(claims, ~w(sub org iat exp)),
     :ok <- check_ttl(claims, max: 3600, leeway: 60),
     :ok <- check_org(claims, key.organization_id, conn_org) do
  {:ok, claims}
end
```

**One line carries the whole algorithm defence.** `verify_strict/3` takes an explicit allow-list;
plain `JOSE.JWT.verify/2` does **not** pin the algorithm, and it is the more obvious-looking call.
That line needs a comment saying so.

---

## 6. Backend changes

**Migrations**
- `web_channel_signing_keys` (§4.1)
- `contact_identities` (§3.3) + backfill one `('whatsapp', phone)` row per existing contact
- `contacts.channels` `{:array, :string}` with a GIN index; `contacts.phone` drop `NOT NULL` and
  rebuild its unique index as partial (`WHERE phone IS NOT NULL`)
- *Later:* `contacts.tokens_valid_after`, `organizations.web_tokens_valid_after`

**Nil-phone fixes** — blocking, see §3.5: `simulator_contact?(nil)`, `populate_masked_phone/1`,
`maybe_create_contact/1`, the two `searches.ex` filters.

**New modules**
- `Glific.WebChannel.SigningKeys` — create (cap 10 active), list, revoke, `fetch_active_by_kid/1`
  (cached; it runs on every connect)
- `GlificWeb.WebChannel.JWT` — the §5 pipeline
- `Glific.Contacts.Identities` — resolve-or-create a contact from `(channel, identifier)`; the
  channel-general context behind §3.3, cached on the inbound hot path
- `Glific.WebChannel.Identity` — map JWT claims to a `('web', sub)` identity; `phone` binding only
  behind `allow_jwt_phone_binding`

**Socket / channel**
- `WebChannelSocket.connect/3` — accept either credential; assign `token_exp` and `auth_mode`; keep
  `id/1` unchanged
- `RoomChannel.join/3` — re-verify the credential, start the sweep timer
- `RoomChannel.handle_info(:check_expiry, …)` — past `exp` → push `session_expired` → stop

**REST**
- New `:web_channel_authenticated` pipeline + plug assigning `current_contact`
- Move `/api/v1/web_channel/upload` behind it — it currently sits in the public scope with a
  hand-rolled bearer check and a comment saying it shouldn't
- Tighter `RateLimitPlug` bucket for `/api/v1/web_channel/*`, keyed `(org, ip)`. Note the existing
  plug is ExRated/ETS and therefore **per-node** — 50 req/60s becomes 50 × nodes in production

**GraphQL (console)**
- `webChannelSigningKeys` / `createWebChannelSigningKey` / `revokeWebChannelSigningKey`, `:admin` only,
  secret returned once
- `addContactIdentity` / `removeContactIdentity` (channel + identifier)
- `identities` on `Contact`, gated for `:staff` exactly like `phone`

**Config / deps**
- Promote `jose` to an explicit `mix.exs` dependency
- Org setting `allow_jwt_phone_binding`, default `false`
- Constants: max TTL, clock leeway, sweep interval

**Tests**
- Verifier matrix: `alg: none`, `alg: RS256`, unknown `kid`, revoked `kid`, cross-org `kid`, missing
  `iat`, missing `exp`, expired, skew in and out of leeway, TTL over cap
- Identity: the same identifier may exist on two different channels; the same
  `(org, channel, identifier)` may not exist twice; two contacts with `phone IS NULL` coexist;
  `maybe_create_contact` with a nil phone does not return an unrelated contact; a web-only contact
  appears in inbox search; deleting a contact cascades its identities
- Socket: expired token → `session_expired` pushed and the channel stopped by the sweep

---

## 7. Phasing

| Phase | Scope |
|---|---|
| **0a** | Nil-safety fixes (§3.5) + widen `searches.ex`. No schema change — ship today |
| **0b** | Create `contact_identities`, backfill `('whatsapp', phone)` for every contact. **Nothing reads it.** Additive and reversible |
| **0c** | Dual-read: identity lookups go through the table, falling back to `contacts.phone`; verify parity in production. Requires §3.7 settled |
| **0d** | Drop `NOT NULL` on `phone`; add `contacts.channels`; allow web-only contacts |
| **1** | `web_channel_signing_keys`: schema, context, GraphQL, console UI, 10-key cap, show-once |
| **2** | JWT verifier, `:web_channel_authenticated` pipeline, socket/join verification, expiry sweep |
| **3** | Revocation: `tokens_valid_after` markers, mutations, live socket disconnect |
| **4** | Real OTP for Mode A, refresh tokens, first-link OTP (§2.3) |
| **5** | Origin allowlist + embeddable widget (§8) |

---

## 8. Deferred: origin allowlisting and the embeddable widget

Not in v1, by decision. Recorded because **the order in which these two are built matters.**

Today the widget is a standalone app on its own origin, and Intercom/Zendesk-style embedded widgets
open their socket **from the host page's browsing context** — so the `Origin` header arriving at the
server is the customer's real site origin, exactly the signal a per-tenant allowlist validates.

Move the widget into a **true cross-origin iframe** on a Glific-controlled origin and that signal
disappears: the socket's `Origin` becomes Glific's own, identically for every tenant. The NGO's real
origin then has to be conveyed separately, and a client-supplied value is worthless because the whole
threat is a client lying about where it is embedded. Candidates: `Sec-Fetch-Site` + `Referer` on the
widget-document `GET`, or binding the parent origin into a short-lived server-issued handshake token
minted during that document load. This is precisely the problem Chatwoot's author abandoned.

Implementation notes for later:

- `Phoenix.Socket`'s `check_origin` accepts an **MFA** — `check_origin: {GlificWeb.WidgetOrigin,
  :check, []}` — so the tenant allowlist can be resolved dynamically at handshake time, rather than
  the compile-time global `CHECK_ORIGIN` env var in use today.
- Enforce server-side at three points (socket handshake, anonymous REST, CORS headers), plus
  `frame-ancestors` as defence in depth. Chatwoot enforces **only** `frame-ancestors`, leaving a
  copied public token fully usable from `curl`.
- Exact-origin string equality. Never `indexOf`/`endsWith`: `https://x.glific.org.attacker.com`
  defeats `indexOf('.glific.org')`, `https://evil-glific.org` defeats `indexOf('glific.org')`.
- An `Origin` allowlist is **never authentication** — spoofable by non-browser clients, so always
  paired with the bearer credential.
- CHIPS keys a partitioned cookie as *(vendor host, top-level registrable domain)*, so an iframe
  session cannot span customer domains. That is correct tenant semantics, not a bug.
- postMessage: explicit `targetOrigin`, never `'*'`; exact-FQDN check on receive; data only, never
  `eval`, never `innerHTML`; **no inbound handler may ever write a session credential** — that is
  Chatwoot's `setAuthCookie` fixation bug, still live on `develop` after the fix in PR #8879 was
  reverted. Validating `event.source` *instead of* `event.origin` is itself exploitable, because
  `WindowProxy` identity survives cross-origin navigation.

---

## 9. Known gaps

- **Abuse controls on anonymous chat endpoints are unresearched** — rate limiting, CAPTCHA,
  proof-of-work and email gates produced no verified findings for any vendor. §6 leaves a hook point
  rather than inventing a scheme.
- **No vendor evidence exists for how long an anonymous/OTP session should stay re-mintable** when
  there is no upstream identity provider. Mode A's refresh TTL is a judgement call, not a copy.
- **Vendor coverage is uneven.** Findings rest on Intercom, Zendesk, Chatwoot, Stream, Twilio and
  Sendbird. Crisp, Drift, Front, Tawk.to, HubSpot and LiveChat produced nothing.
- **No OAuth 2.0 / OWASP revocation guidance was gathered** — §4.2 is inferred from vendor behaviour,
  not from standards.
