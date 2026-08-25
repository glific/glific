# Glific Web Channel — API Authentication

> ## Decisions superseded since the first draft
>
> This document was written before the partner-facing proposal
> (`ngo-api-integration.md`). Where the two disagree, **the NGO doc is current.** Everything below
> has been corrected inline; the table records what moved and why, so the reasoning is not lost.
>
> | # | Was | Now | Why |
> |---|---|---|---|
> | 1 | Max 10 signing keys per org (§4.1) | **5** | Product call. Prod + staging + rotation spare is enough. |
> | 2 | `org` claim required (§2.1, §2.2 rule 6) | **Dropped** | `kid` resolves to exactly one org and the signature proves key possession, so the claim adds no security — only a way for an integrator to misconfigure. The `kid`-org ↔ Host-org check is retained; it is the load-bearing half. |
> | 3 | First-link OTP gates a `phone` binding (§2.3) | **Trusted `phone` claim**, no OTP | An OTP to a phone the user does not own is not a workable flow for the target population. Verification is **delegated** to the NGO, stated as their obligation. `allow_jwt_phone_binding` is not being built. |
> | 4 | No in-place renewal; `session_expired` then reconnect (§2.4) | **`renew_token` inbound event** + `token_expiring` warning | Twilio's `updateToken()` precedent. Renewal must re-verify in full **and resolve to the same contact**, else it is an identity-switch primitive on an already-joined channel. |
> | 5 | Topic `web_channel:<contact_id>` | **`web_channel:me`** | Under JWT auth the client knows `sub`, not the Glific `contact_id`. Join reply returns `contact_id`. |
> | 6 | Per-contact revocation "later" (§4.2) | **v1, via logout** | `POST /api/v1/web_channel/logout` sets `contacts.tokens_valid_after` and drops the socket. Driven by shared-device use (one school tablet, many students). |
> | 7 | — | **`web_message_id`** | Client-supplied opaque idempotency key, mirrors `bsp_message_id`. A duplicate inbound message can advance a flow twice — state corruption, not a double bubble. |
> | 8 | Display name written to `contacts.name` | **Scoped to the web login** | A shared household number is one contact; a per-login name must not overwrite the WhatsApp-facing name or `contact.fields.name`. Storage (identity row vs `profile.name`) is still open — see §10.3. |
>
> **Also corrected:** §3 called Maytapi a candidate identity channel. It is not — its identifier is
> an E.164 phone, the same namespace as Gupshup WhatsApp. It is a *provider*, not a namespace. The
> same applies to RCS. Telegram and SwiftChat are the genuinely new namespaces.


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
  "sub":     "member_4471",     // REQUIRED — the web identity. Opaque, max 255 chars.
  "channel": "web",             // REQUIRED — namespace of `sub`. Must be "web".
  "iat":     1755590400,        // REQUIRED — precondition for revoke-before-iat (§4.2)
  "exp":     1755591300,        // REQUIRED — short, see §2.4
  "phone":   "+919876543210",   // OPTIONAL — NGO-verified linking claim, see §2.3
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
4. **Require `sub`, `channel`, `iat`, `exp`.** Clock leeway ≤ 60s. (`org` dropped — changelog #2.)
5. **Cap the TTL server-side.** Reject `exp - iat` greater than one hour even if the NGO set it, so
   an integrator cannot ship year-long tokens.
6. **Cross-check two org values**: the org owning the `kid`, and the org `SubdomainPlug` resolved
   from the Host header. Mismatch → reject and log; it means key misuse or a cross-tenant attempt.
   (Was three; the `org` claim was redundant — changelog #2.)
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

**SUPERSEDED — see changelog #3.** The analysis above stands; the conclusion changed.

An OTP to a phone the end user does not own — a parent's handset, a shared school device — is not a
workable flow for the target population, so the first-link OTP was dropped. Verification is
**delegated to the NGO** and stated as their obligation: *include `phone` only if you verified it.*
`allow_jwt_phone_binding` was proposed as a default-off org gate and **not adopted**; it remains the
cheapest available backstop if this is revisited.

Two containments make the delegation defensible, and both must hold:

1. **Web history is channel-scoped.** `Messages.list_conversation_messages/3` filters
   `where m.channel == ^channel`, and `messages.channel` defaults to `"whatsapp"`. So a linked web
   session replays only `channel = "web"` rows — it does **not** expose the contact's WhatsApp
   history. This is load-bearing for the whole delegation argument and must not regress; it needs a
   test that fails loudly if the filter is ever dropped.
2. **One phone never attaches to two web identities.** If the claimed phone resolves to a contact
   that already carries a different `web` identity, the claim is **ignored** and the session proceeds
   web-only. Likewise a changed `phone` on a later token for an existing `sub` is ignored: once
   attached, the link is fixed. Re-pointing an established identity would move a live session onto
   another person's contact.

**Open consequence:** for a population where several people legitimately share one number, #2 means
all but the first are unlinked. Glific's existing `profiles` feature is the intended answer — see
§10.3.

### 2.4 TTL, expiry mid-connection, and renewal

There is no industry consensus on TTL — Zendesk recommends "a few minutes", Twilio defaults to 1h
with a 24h cap and warns that under 300s is unreliable, Sendbird defaults to 7 days, Stream and
Intercom default to *no expiry at all*. We keep the renew period **short** and cap it at one hour.

A short TTL is only meaningful if something re-checks a **live** socket, since auth otherwise happens
once at `connect/3` and the effective session length becomes the connection length.

**SUPERSEDED — see changelog #4.** In-place renewal was rejected here and later adopted. The
sweep below still runs; what changed is that expiry now *warns* before it *kills*:

```
exp − warning_window  →  push `token_expiring`   → client mints, sends `renew_token`
exp + grace, no renew →  push `session_expired`  → stop the channel
```

`renew_token` must re-verify in full (kid → key → revoked? → HS256 pinned → claims → TTL cap →
org cross-check) **and assert the new token resolves to the same `contact_id` already on the
socket.** `join/3` authorizes the topic exactly once and never re-checks it, so a renewal permitted
to swap `current_contact` is an identity-switch primitive that bypasses the join guard entirely.
Reject on mismatch; never swap.

It must be a **channel** handler — `Phoenix.Socket` exposes no user hook, and a channel's `assign`
does not propagate to the socket process.

The original decision, still accurate for the terminal case:

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
- **Max 5 per organization** (non-revoked) — prod, staging, and a rotation spare (changelog #1).
- **Secret displayed in full exactly once**, at creation.
- **`kid` is what makes rotation tractable**: add a new key, migrate the NGO's minting, revoke the
  old one. Stream has one secret per app and no `kid`, so its only rotation is "regenerate and every
  outstanding token dies at once" — unacceptable when the secret lives on a partner's server.

### 4.2 Revocation levers

| Lever | Who | Mechanism | Blast radius | Phase |
|---|---|---|---|---|
| Revoke a signing key | Org admin | `revoked_at` | every JWT signed with that `kid` | v1 |
| Drop live sockets | either | `Endpoint.broadcast("web_socket:#{contact_id}", "disconnect", %{})` | one contact's connections | v1 |
| **Log out one end user** | the end user / NGO app | `POST /api/v1/web_channel/logout` → `contacts.tokens_valid_after` vs `iat`, plus socket drop | that contact's tokens, all devices | **v1** (changelog #6) |
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
     :ok <- require_claims(claims, ~w(sub channel iat exp)),
     :ok <- check_ttl(claims, max: 3600, leeway: 60),
     :ok <- check_org(key.organization_id, conn_org),
     :ok <- check_not_logged_out(claims, contact) do
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
- `contacts.tokens_valid_after` `:utc_datetime` — **v1 now**, backs logout (changelog #6)
- `messages.web_message_id` `:string`, nullable, `unique_constraint([:web_message_id,
  :organization_id])` — mirrors `bsp_message_id` exactly. **Its own column**: `room_channel.ex`
  deliberately leaves `bsp_message_id` nil because a client-supplied value could collide with a real
  BSP id, and that reasoning applies unchanged here
- *Later:* `organizations.web_tokens_valid_after`

**Nil-phone fixes** — blocking, see §3.5: `simulator_contact?(nil)`, `populate_masked_phone/1`,
`maybe_create_contact/1`, the two `searches.ex` filters.

**New modules**
- `Glific.WebChannel.SigningKeys` — create (cap **5** active), list, revoke, `fetch_active_by_kid/1`
  (cached; it runs on every connect)
- `GlificWeb.WebChannel.JWT` — the §5 pipeline
- `Glific.Contacts.Identities` — resolve-or-create a contact from `(channel, identifier)`; the
  channel-general context behind §3.3, cached on the inbound hot path
- `Glific.WebChannel.Identity` — map JWT claims to a `('web', sub)` identity. `phone` binding is
  trusted (changelog #3) and must implement both containments in §2.3: refuse to attach when the
  phone's contact already carries a different `web` identity, and ignore a changed `phone` for an
  existing `sub`

**Socket / channel**
- `WebChannelSocket.connect/3` — accept either credential; assign `token_exp` and `auth_mode`; keep
  `id/1` unchanged (it is the forced-disconnect hook logout depends on)
- `RoomChannel.join/3` — accept topic **`web_channel:me`** resolving to the socket's contact
  (changelog #5), keep `web_channel:<id>` for the OTP widget, return `contact_id` in the reply,
  re-verify the credential, start the sweep timer
- `RoomChannel.handle_info(:check_expiry, …)` — at `exp − warning` push `token_expiring`; at
  `exp + grace` push `session_expired` → stop
- `RoomChannel.handle_in("renew_token", …)` — full re-verification **plus the same-contact
  assertion** (§2.4); reschedule the timer; reply `{expires_at}`
- `RoomChannel.handle_in("new_message", …)` — accept `web_message_id`; on a duplicate return the
  original `{id, inserted_at}` rather than inserting; reply now carries `{id, inserted_at}` in all
  cases so a client can reconcile after a rejoin replay
- `MessageSerializer.media/1` — emit `content_type`, `caption`, `thumbnail` (currently drops all
  three); keep `gcs_url` internal

**REST**
- New `:web_channel_authenticated` pipeline + plug assigning `current_contact`
- `POST /api/v1/web_channel/logout` behind it — set `contacts.tokens_valid_after = now`, then
  `Endpoint.broadcast("web_socket:#{contact_id}", "disconnect", %{})`. Compare with **`iat <=
  tokens_valid_after`**, not `<`: `iat` is second-granularity, so a token minted in the same second
  as the logout would otherwise survive it — precisely the shared-device race this exists to close
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
- ~~Org setting `allow_jwt_phone_binding`~~ — proposed, **not adopted** (changelog #3)
- Constants: max TTL, clock leeway, sweep interval

**Tests**
- Verifier matrix: `alg: none`, `alg: RS256`, unknown `kid`, revoked `kid`, cross-org `kid`, missing
  `iat`, missing `exp`, expired, skew in and out of leeway, TTL over cap
- Identity: the same identifier may exist on two different channels; the same
  `(org, channel, identifier)` may not exist twice; two contacts with `phone IS NULL` coexist;
  `maybe_create_contact` with a nil phone does not return an unrelated contact; a web-only contact
  appears in inbox search; deleting a contact cascades its identities
- Socket: expired token → `token_expiring` then `session_expired`, channel stopped by the sweep
- **Renewal: a valid token for a *different* contact is rejected and does not swap `current_contact`**
  — the §2.4 identity-switch guard; this is the highest-value single test in the suite
- **Logout: a token minted in the same second as the logout is rejected** (the `<=` boundary)
- **Channel scoping: a contact with both a `whatsapp` and a `web` identity replays only `channel =
  "web"` rows on join** — §2.3 containment #1; must fail loudly if the filter regresses
- Idempotency: the same `web_message_id` twice yields one message row and two identical replies
- Identity: a phone whose contact already carries a different `web` identity is ignored, not attached

---

## 7. Phasing

| Phase | Scope |
|---|---|
| **0a** | Nil-safety fixes (§3.5) + widen `searches.ex`. No schema change — ship today |
| **0b** | Create `contact_identities`, backfill `('whatsapp', phone)` for every contact. **Nothing reads it.** Additive and reversible |
| **0c** | Dual-read: identity lookups go through the table, falling back to `contacts.phone`; verify parity in production. Requires §3.7 settled |
| **0d** | Drop `NOT NULL` on `phone`; add `contacts.channels`; allow web-only contacts |
| **1** | `web_channel_signing_keys`: schema, context, GraphQL, console UI, **5**-key cap, show-once |
| **2** | JWT verifier, `:web_channel_authenticated` pipeline, socket/join verification, `web_channel:me`, expiry sweep, `token_expiring` + `renew_token` |
| **3** | Revocation: logout endpoint, `tokens_valid_after`, live socket disconnect |
| **3b** | `web_message_id` idempotency + media serializer fields. Independent of auth; ship whenever |
| **4** | Real OTP for Mode A (Glific's own widget only — the NGO path has no OTP) |
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

---

## 10. Review findings and open questions

Two adversarial reviews, August 2026: a security review (§10.1) and a scalability / multi-replica
review (§10.2). **Read this triage first.**

### 10.0 What must be decided before any implementation

| # | Finding | Where | Why it blocks |
|---|---|---|---|
| 1 | **`web_channel:me` puts every contact in every tenant on one PubSub topic** | §10.1 | My design error. Cross-tenant presence leak + org-wide silent message loss. Already published in the NGO doc — must be corrected there. Fix: revert to `web_channel:<contact_id>` + `GET /api/v1/web_channel/me` |
| 2 | **Glific has no clustering; `Endpoint.broadcast`, Presence and forced-disconnect are all node-local** | §10.2 | The web channel silently depends on all three. Passes manual testing on N replicas and fails for staff replies, `flow_wakeup`, broadcasts and triggers. **Also breaks the logout promise already published in NGO §3.5** |
| 3 | **`update_name` contradicts the name guarantee published in NGO §1.3/§2.4, and the handler is still reachable** | §10.1 | Doc and code say opposite things. "Not in the docs" is not an access control |
| 4 | **`web_message_id` scoped per-org is an attack primitive** | §10.1 | Supersedes changelog #7. Cross-contact message suppression + metadata oracle. Must be `(org, contact, web_message_id)` |
| 5 | **The `phone` claim ships with neither specified mitigation** | §10.1 | A recorded decision (changelog #3), **not reversed here.** The reviewer's blast-radius analysis is sharper than the original and works around the channel-scoping containment. Three cheap restorations proposed — the audit event I would ship regardless |
| 6 | **Presence-gated delivery is unsound even on one node** | §10.2 | Records never-delivered messages as delivered. Fix is a deletion: broadcast unconditionally |
| 7 | **Confirm the Gigalixir/GCP ingress WebSocket max connection duration** | §10.2 | If it is near GCP's 30s default, every socket dies every 30s and much of this design is moot. One support ticket, do it first |

Cheap and unambiguous, worth doing regardless of the above: the `(contact_id, channel,
message_number DESC)` index; `RemoteIp` restricted to `x-forwarded-for`; a per-socket rate limit;
`is_binary` guards and no hard `{:ok, _} =` matches in channel handlers; uncomment `+Q` in
`rel/vm.args.eex`; delete the `"9999"` OTP bypass from shipped code.


### 10.1 Security review

Adversarial review against both documents and the branch implementation. Claims below were
spot-checked against the repo; where a finding contradicts a decision already taken, it is recorded
as a finding with an assessment — **not** silently applied to §2.3.

#### CRITICAL — `web_channel:me` collapses every contact in every tenant onto one PubSub topic

**This is my error, introduced when solving "the client doesn't know its `contact_id`".** A Phoenix
channel topic *is* the PubSub topic string. If every browser joins the literal `"web_channel:me"`,
they all land in **one global topic**, and `join/3` cannot rename its own topic.

Three consequences, none needing exploit code:

- `Presence.track(socket, "contact:#{contact_id}", …)` (`room_channel.ex:71`) tracks under
  `socket.topic`. Every joined browser would receive `presence_state`/`presence_diff` enumerating
  **every online contact id across every organization**, with timestamps. A passive, continuous
  cross-tenant leak.
- `Providers.Web.Message.deliver/2` gates on `Presence.list(topic) != %{}`. Under a shared topic that
  is non-empty whenever *anyone anywhere* is online, so every message is marked
  `status: :sent, bsp_status: :delivered` — while the actual broadcast goes to
  `"web_channel:#{contact_id}"`, which nobody is subscribed to. **Messages marked delivered and
  silently lost, org-wide, for as long as one attacker stays connected.**
- The two halves don't compose at all: `me` for subscription, `<contact_id>` for delivery.

**Fix — take the boring option.** Revert the wire topic to `web_channel:<contact_id>` and add
`GET /api/v1/web_channel/me` (JWT-authenticated, returns `contact_id` and display name), which the
client calls once per session. It is one extra request at connect and it removes the whole class of
problem. We are already adding `/logout` to the same authenticated pipeline, so this is consistent
rather than novel.

*Alternative if the round trip is unacceptable:* keep `web_channel:me` as a dumb channel that never
carries Presence or broadcasts, and have `join/3` explicitly
`Phoenix.PubSub.subscribe(Glific.PubSub, "web_channel:#{id}")` with a `handle_info` forwarder, and
`Presence.track(self(), private_topic, …)`. Workable, but note `intercept/1` + `handle_out/3` no
longer fire for forwarded messages, so `maybe_push_display_name/1` has to move. More moving parts for
one saved request — not recommended.

**Either way: add a regression test asserting two contacts in two organizations never observe each
other's presence diffs.** The NGO doc (§3.2, §6) must be corrected before it is acted on.

#### CRITICAL — the trusted `phone` claim: both specified mitigations were dropped

**This is a recorded decision (changelog #3), not an oversight. Presented for review, not reversed.**

§2.3 originally said *"ship 1 and 2"* — first-link OTP **and** `allow_jwt_phone_binding` default-off.
The shipped proposal has neither; only mitigation 3 (documentation), which this doc itself calls
"not a control", survived. §4.1's `verified_at` column exists precisely to distinguish OTP-proven
from NGO-asserted links and is currently never written or surfaced.

The reviewer's blast-radius analysis is **more precise than mine was**, and correctly works *around*
the channel-scoping containment rather than through it:

- **Contact-field read-out via the flow engine.** Inbound web messages run the org's flows against
  the *victim's* contact. Every `@contact.fields.*` the victim supplied over WhatsApp — registration
  id, school, loan status, health data — is readable by walking any flow that echoes a field. This is
  the history leak, laundered through the bot. **Channel scoping does not contain it.**
- **Staff-mediated disclosure.** The attacker's messages appear in the staff inbox *as the victim*;
  staff answer the victim's account questions to the attacker.
- **Write access to the victim's record**, including outbound WhatsApp through the org's verified
  WABA — `contacts.phone` is untouched by the link. Harassment or phishing carrying the NGO's sender
  identity.
- **Permanent pre-emptive squat.** Per §2.3 the *first* claimant wins forever and a later phone
  change is silently ignored. An attacker who binds before the real owner ever logs in owns that
  contact permanently, and the real owner's later login **fails silently** into a fresh web-only
  contact, alerting nobody.

**Assessment.** The delegation argument still holds *if* the NGO's number is genuinely verified — the
question already asked in NGO §8. What is missing is any backstop for when it isn't. Cheapest
restorations, in order:

1. **`allow_jwt_phone_binding`, default off** — proposed and not adopted. It is one boolean, and it
   means an org must consciously assert "our numbers are verified" before the claim does anything.
   Recommend restoring.
2. **Write `contact_identities.verified_at` only on an OTP path; leave NULL for NGO-asserted**, and
   surface it in the console. Costs nothing now, makes the exposure auditable later.
3. **Audit-event every link attempt, including the "ignored, already bound" case**, so a squat is
   detectable rather than silent. This one is cheap and I would ship it regardless.

#### HIGH — `update_name` contradicts a guarantee already published, and the handler is still live

NGO §1.3 and §2.4 promise the name is *"scoped to the login — never overwrites the contact's
WhatsApp-facing name"*. The code does exactly the opposite in **both** stores:
`room_channel.ex:216` writes `contacts.name`, and `:225` writes `contact.fields["name"]` — the
value every flow reads as `@contact.fields.name` and the staff inbox displays. On a shared family
number this renames the parent's contact across all channels.

**Compounding: `update_name` was declared out of the public API, but nothing removes the handler.**
Any client can still send the event. "Not in the docs" is not an access control.

**Fix:** implement the guarantee (store on the identity row, resolve only in the web serializer /
`DisplayName`), **and delete or authorize the `update_name` handler**. Cap length, reject control
characters. Do not ship doc and code as they stand.

#### HIGH — `web_message_id` scoped per *organization* is an attack primitive

Changelog #7 specified it mirroring `bsp_message_id`, i.e. `(web_message_id, organization_id)`. That
was my recommendation and the reviewer is right that it is wrong:

- **(a) Cross-contact message suppression.** Attacker in org X pre-claims a set of keys. Victim's
  client later generates a colliding value — trivial if their integrator used a counter, a timestamp,
  or `"#{member_id}-#{seq}"`. Glific returns the *original* `{id, inserted_at}` and creates nothing.
  The victim's message never persists, never reaches staff, never advances the flow — and their
  client renders it as sent, because the reply was a success. Silent, deniable censorship.
- **(b) Metadata oracle.** The dedup reply hands back `{id, inserted_at}` belonging to *another
  contact's* message. Iterate for an existence oracle plus ids and timestamps.
- **(c)** And if implemented on `bsp_message_id` itself, a client can pre-claim a value a real Gupshup
  inbound will later carry, dropping a genuine **WhatsApp** message. `room_channel.ex:113-117`
  already warns about exactly this.

**Fix:** unique on `(organization_id, contact_id, web_message_id)` in a dedicated column; return the
cached reply **only when the existing row's `contact_id` matches the caller**; cap length; expire
after a bounded window. Note `blocks_response` already gets this right
(`web_message.ex:151-167`: scoped `receiver_id`, uniform not-found error) — copy that discipline.
**Supersedes changelog #7's "mirrors `bsp_message_id` exactly".**

#### HIGH — the `"9999"` OTP bypass, and a phasing that ships Mode A fake

`web_channel_auth_controller.ex:75`. If `:web_channel_otp_bypass` is ever true in production, anyone
can POST `/verify-otp` with any phone and `"9999"` and receive a valid contact token — **for any
contact in the org resolved from the Host header**, on an unauthenticated public route. Total org-wide
account takeover, silent, and the response returns `name` and `phone`, making it a PII oracle too.
`Application.put_env/3` is runtime-mutable, so the config comment is not a guarantee.

Aggravating: §7 puts real OTP in **Phase 4**, after JWT (2) and revocation (3) — i.e. the plan ships
to production with Mode A fake for two phases.

**Fix:** delete the bypass from shipped code; make it a test-only stub injected via a behaviour/Mox.
Add a boot assertion in `runtime.exs` refusing to start `:prod` if the key is set. Re-order §7 so
Mode A cannot reach production before real OTP, or drop Mode A from v1.

#### HIGH — rate limiting keyed on a spoofable IP, and none at all on the socket

**[verified]** `endpoint.ex:89` is `plug(RemoteIp)` with **defaults and no trusted-proxy list**.
Glific's own `bsp_webhook_ip_filter.ex:31-34` documents the consequence: defaults also trust
`forwarded`, `x-client-ip` and `x-real-ip`, while the proxy only rewrites `x-forwarded-for`, so a
caller sending one of the other three wins. An attacker sends a fresh `X-Real-IP` per request and has
an unbounded budget on `/request-otp`, `/verify-otp` and `/upload`. **NGO §7.2's "rate limited per
client IP" is not true as implemented.** It is also per-node (ExRated/ETS), so the real ceiling is
50 × nodes.

The socket has **no limit at all**. One authenticated socket can pump frames; each does a DB insert,
an Absinthe fan-out, and a poolboy checkout — and a flow node may call webhooks, OpenAI or Kaapi, so
the attacker spends the NGO's third-party budget per frame and **starves WhatsApp inbound for the
whole org** (see §10.2's poolboy analysis — 20 workers per node). `load_more` passes an
attacker-chosen `offset` straight to `offset(^offset)` with no validation.

**Fix:** configure `RemoteIp` with `headers: ["x-forwarded-for"]` and an explicit `proxies:` list;
move the limiter to a shared store or document `limit × nodes`; add a per-socket token bucket in
`handle_in/3` replying `{:error, %{reason: "rate_limited"}}`; validate `offset` as bounded
non-negative.

#### HIGH — `renew_token`: resolve-or-create, and the same-contact check tests the wrong thing

Two defects beyond what §2.4 specifies:

- **Identity creation from inside a session.** §6's sequence verifies then *resolves* `sub` before
  the equality test — and resolution is resolve-**or-create**. Anyone holding a signing key can loop
  `renew_token` with a fresh `sub`, minting unbounded contacts, each firing the org's `newcontact`
  flow and consuming inbox and reporting quota. The renewal is rejected; the side effect already
  happened.
- **The invariant is wrong.** Compare the **`sub` string** bound at connect, not the resolved
  `contact_id`. Two `sub`s can resolve to one contact (the nil-phone hazard below), and comparing
  `contact_id` would then permit exactly the person-swap §2.4 promises to prevent.

Also: nothing on a live channel re-checks contact blocked/opted-out, org suspended/soft-deleted, or
`organizations.web_tokens_valid_after`. Chained renewals keep such a session alive indefinitely.

**Fix:** rate-limit renewal (≤2/min per channel); compare `claims["sub"]` and `kid`'s org **before
any identity resolution**; resolve read-only (`fetch`, never `resolve_or_create`); re-check
`tokens_valid_after`, contact status and org status; ignore `phone`/`name`/`email` on renewal
entirely — renewal extends a session, it must not be an attribute-write channel.

#### HIGH — 60s of clock leeway is 60s of logout bypass

Rule 4 grants ±60s leeway; leeway on `iat` means accepting tokens stamped up to 60s in the **future**,
and the NGO controls its clock. A minting server running 45s fast issues `iat = T+35`; a logout at
wall-clock `T` writes `tokens_valid_after = T`; the token survives it. **The shared-classroom-tablet
case §3.5 exists for is defeated by ordinary NTP drift the NGO owns and Glific never sees.** A
malicious partner sets `iat = now + 59` on every mint and logout never works at all.

Also: the `<=` boundary (already specified in §6) must be stated in the NGO doc; `tokens_valid_after`
must be read **uncached** or invalidated cluster-wide (Glific's Cachex is node-local — see §10.2);
and the write must commit **before** the socket drop, else the client's auto-reconnect re-establishes
on a still-accepted token.

**Fix:** stamp `tokens_valid_after = now + max_leeway`, so every token inside the skew window dies.
Store sub-second. Never apply forward tolerance to `iat` in the revocation comparison — better,
reject `iat > now` outright. Rate-limit `/logout`, or a leaked-token holder can loop it to lock the
victim out.

#### HIGH — the end-user socket runs as the organization's root user

**[verified]** `repo_helpers.ex:442-446`: `put_process_state/1` does `put_organization_id/1` **and**
`put_current_user(Partners.organization(org_id).root_user)`. It is called in `connect/3`
(`web_channel_socket.ex:24`), `join/3` (`room_channel.ex:44`) and the upload controller. So every
frame an anonymous browser sends is processed with `skip_permission?/1` returning **true**.

The least-privileged surface in the product carries the most privileged principal. Today the blast
radius is bounded by which handlers exist — and `update_name` already exploits it: a `:staff` user
cannot even *read* `contact.phone`, while this surface writes `contacts.name` org-wide. The risk is
structural: every handler anyone adds to `RoomChannel` inherits admin. The code comment justifies it
as "same requirement as an Oban worker" — but an Oban worker is trusted internal code and a channel
is a remote attacker's input loop.

**Fix:** set `put_organization_id/1` without `put_current_user/1`, and give the channel explicit
contact-scoped context functions; or synthesize a restricted principal so the permission clauses
actually run.

#### MEDIUM — the rest

- **Rule 6 is not a security control.** The org is derived from `kid`, so replaying at another
  subdomain grants nothing either way; and the Host header is attacker-controlled, so the
  "cross-check" is satisfiable by the attacker in the one case it is meant to catch. Keep it as a
  **logged anomaly** and describe it that way, so nobody builds on it. **[verified]** Also
  `endpoint.ex:28` declares the socket with **no `connect_info`**, so `connect/3` cannot see the host
  or peer at all — rule 6 and any IP-based handshake limit require
  `connect_info: [:uri, :peer_data, :x_headers]` first.
- **The inbound path resolves the sender by phone.** `room_channel.ex:110-129` passes
  `sender: %{phone: contact.phone}` → `maybe_create_contact/1` → `Repo.get_by(Contact, %{phone: …})`.
  Once phone is nullable (phase 0d) this is `WHERE phone IS NULL` on the **hot path of every web
  message** — an arbitrary contact, or `Ecto.MultipleResultsError`. §3.5 flags the function; it does
  not flag that the web channel calls it per message. **Fix: pass `contact_id` through; the identity
  was already established at connect.** Gate 0d on this.
- **Token in the query string.** Less bad than the classic case (upgrades bypass the plug logger,
  no `Referer`, no history, `longpoll: false`). What remains: ingress/LB access logs, APM transaction
  names, and browser error reporters shipping WS URLs as breadcrumbs to a third party. **Preferred
  fix: move the token into the join payload** — we already need an inbound token handler for
  `renew_token`, so it is nearly free; keep the socket unauthenticated until join and drop
  un-joined sockets after a few seconds. Otherwise a 30-second single-use ticket.
- **Untyped payloads + hard `{:ok, _} =` matches.** `handle_in("new_message", %{"body" => body})` has
  no `is_binary` guard; a non-binary body fails the hard match and **kills the channel**, which
  auto-rejoins and re-runs the 100-row history query — a free crash loop that also writes
  attacker-chosen content into AppSignal stacktraces. `new_location_message` interpolates unvalidated
  lat/lng into a maps URL, so a crafted value renders as a plausible link plus a phishing URL in the
  staff inbox. No length validation on `messages.body` anywhere.
- **`new_media_message` trusts a client-supplied `url` and `content_type`.** Nothing checks the URL
  came from `/upload` or points at the org's bucket. It renders in staff browsers, and it becomes
  `@results…media.url` which several flow paths fetch **server-side** (`Messages.validate_media/2` is
  a bare `Tesla.get`; `Glific.URI.cast/1` accepts IP literals). That is SSRF and AI-spend
  amplification reachable by an anonymous web login. **Fix: `/upload` returns an opaque media id;
  `new_media_message` references that.**
- **Revocation vs a node-local cache.** §6 specifies `fetch_active_by_kid/1` cached; Cachex is
  node-local. On multi-node, revoking on one node leaves others accepting the key until TTL — while
  NGO §1.6 promises "immediate". Invalidate via PubSub, cap TTL ≤60s, and state the real window.
- **Phone format is unspecified, and one range collides with the simulator.** Glific stores E.164
  **without** `+` (Gupshup's `wa_id`); the documented example `"+9198…"` therefore matches nothing and
  silently creates a duplicate — permanently, per §2.3. Worse, `@simulator_phone_prefix` is
  `"9876543210"` matched by `String.starts_with?/2`, so a real number in that range is classified as
  an internal simulator across 14 call sites, including a web-delivery branch that marks messages
  delivered **without broadcasting**. Specify the format; normalize server-side; reject the simulator
  prefix.
- **`check_origin` is endpoint-global**, shared with the staff GraphQL and LiveDashboard sockets.
  Onboarding partner origins widens all three, or invites `check_origin: false`. Move `/web_socket`
  to an MFA form now (§8 already documents the pattern), even if it initially reads one list.

#### Partner-doc issues that will lead a careful integrator astray

1. **§2.4's name guarantee is false against the code** — stated twice, as a positive security
   property, with a shared-family worked example.
2. **§2.3 defines no way to observe the link outcome.** Add `identity_link: "created" | "attached" |
   "ignored_conflict"` to the join reply, define what "verified" means, and state the phone format.
3. **§4.4 names `msg-1` as a "risk" rather than forbidden**, and describes org-scoped uniqueness.
4. **§3.5's shared-device ordering advice is a client requirement with no server enforcement**, and
   §5.2's copy-pasteable snippet auto-reconnects with the caveat *below* it. **Put the guard inside
   the sample code.**
5. **"Recommended 15 minutes" next to a 1h ceiling** — some integrators will raise it to the cap.
   Consider enforcing 15m and letting orgs request more.
6. **§7.2 states a rate limit that is not real** (above).
7. **§1.5's sample has no `kid` fallback**, so §1.2's zero-downtime rotation needs a code change and
   a deploy at exactly the moment an org is responding to a leak. Show two keys and a switch.
8. **No error catalogue.** A rejected token, revoked key, cross-org mismatch and rate limit all look
   identical, so the integrator's only debugging tool is retrying — which is how hot reconnect loops
   get built. Publish stable non-oracular close codes plus an admin-readable audit log.

#### Checked and cleared

`WebChannelSocket.id/1` — contact ids are globally unique bigserials, so the forced-disconnect topic
cannot collide across tenants. `join/3`'s topic authorization is correct **as written today**; the
flaw is the `me` redesign, not the check. **History is genuinely channel-scoped** — `messages.ex:70`
filters `m.channel == ^channel` and both call sites pass `"web"`, so a web session cannot read
WhatsApp rows; the phone-claim findings are written around that containment, not through it.
`blocks_response` is correctly scoped with a uniform not-found error and a guarded `update_all`.
`prepare_query/3` raises rather than defaulting when no org is set. Media upload takes its org from
the token, never the body. `longpoll: false` keeps `?token=` out of the plug pipeline. Algorithm
pinning via `verify_strict/3` is right, and the `guardian_db` analysis needs no changes. **Dropping
the `org` claim is an improvement** — it removes an attacker-controlled input from the decision.


### 10.2 Scalability and multi-replica review

Reviewed against the branch code, `mix.lock`, `config/`, `rel/` and `structure.sql`. Claims marked
**[verified]** were confirmed directly against the repo; **[inferred]** are the reviewer's reasoning
and need checking before they are acted on.

#### The headline: Glific has no clustering, and the web channel silently depends on it

**[verified]** `mix.lock` contains no `libcluster` and no Redis PubSub adapter.
`lib/glific/application.ex` starts `{Phoenix.PubSub, name: Glific.PubSub}` with **no adapter** — the
default `Phoenix.PubSub.PG2`, which delivers only to nodes in `Node.list()`. `rel/env.sh.eex` has
`RELEASE_DISTRIBUTION` and `RELEASE_NODE` **commented out**. So `Node.list()` is empty.

Every cross-node mechanism the web channel needs therefore returns "no" — not an error, a `false`
and a log line:

| Mechanism | Cross-node today | Consequence |
|---|---|---|
| `Endpoint.broadcast/3` | **No** | outbound message never reaches the socket |
| `Presence.list/1` → `connected?/1` | **No** | delivery gate says "offline" for an online user |
| Forced disconnect via socket id | **No** | **logout does not drop the socket** — see below |
| `Absinthe.Subscription.publish` | **No** | staff inbox live updates — **already broken today if >1 pod** |
| ExRated rate limiting | **No** | effective limit is N × configured |
| Per-channel expiry timers | n/a — process-local by design | fine, no action |
| Oban (Pro Smart engine, Postgres notifier) | **Yes** | already multi-replica-ready |

**Why this will pass manual testing.** The inbound-triggered reply path is entirely node-local:
browser → `RoomChannel` (node A) → `receive_message` → poolboy worker (node A) → flow (node A) →
`deliver` → `Presence.list` finds the local entry → broadcast → delivered. A tester opens the widget,
types, gets a reply, and everything looks correct on any number of replicas.

What breaks is every sender that *doesn't* originate on the user's node — **staff replies from the
inbox, `flow_wakeup` resumptions, broadcasts, triggers, crontab flows, webhook-resumed flows.** On 3
replicas those fail roughly 2/3 of the time, at random, per message. That is the bulk of Glific's
proactive messaging. The demo works; the product doesn't.

#### This breaks a promise already published to the NGO

The NGO doc §3.5 states that logout "**drops their live socket** immediately", and motivates it with
the shared-classroom-tablet handover. Splitting that promise on multi-replica:

- `tokens_valid_after` is a DB write → **works cross-node.** New connections and renewals are
  correctly blocked everywhere.
- `Endpoint.broadcast("web_socket:#{contact_id}", "disconnect", %{})` → **does not work cross-node.**

So on N replicas the previous student's socket stays open, streaming, until their token expires — up
to a full token lifetime. **This is a correctness gap against a published commitment, and it is the
reason clustering is a blocker for logout rather than a later optimisation.**

#### Presence-gated delivery is the load-bearing design mistake

`Providers.Web.Message.deliver/2` gates on `connected?(topic)` before broadcasting. Four independent
problems:

1. **The gate is weaker than the thing it guards.** `Phoenix.Channel.Server` subscribes the channel
   to its topic *before* `join/3` runs; `Presence.track` happens later in `handle_info(:after_join)`.
   There is a window where the channel would receive a broadcast but `connected?` says false. A
   broadcast to a topic with no subscribers is an ETS lookup that matches nothing — **the check costs
   more than not checking, and is less accurate.**
2. **Cross-node propagation makes it wrong in both directions.** `Phoenix.Tracker` defaults are
   `broadcast_period: 1500ms`, `down_period: 30s`, `permdown_period: 20min`. False negative: a
   just-connected user is marked `:error` for ~1.5 s — a window that opens on *every* reconnect.
   False positive, and worse: a just-disconnected user is broadcast into the void and the message is
   recorded **`status: :sent, bsp_status: :delivered`.** A message that was never delivered is
   recorded as delivered, which defeats the rejoin catch-up that would otherwise have saved it.
3. **Wrong tool for a per-user topic.** The topic is one-per-user, never shared. Tracker's CRDT and
   heartbeats exist for shared-room fan-out; here you pay full distributed-set replication to answer
   "is this pid alive".
4. **It implies session affinity that no LB can deliver.** Stickiness routes *a client's own*
   requests consistently. The senders that break are staff replies and Oban jobs — not that client's
   requests. **Sticky sessions cannot fix this; clustering can.** Worth stating explicitly so
   "just turn on sticky sessions" doesn't get proposed — it would make testing look *better* while
   fixing nothing.

**Recommended:** delete `connected?/1` and broadcast unconditionally. Derive delivery from a client
ack, not from presence. Keep Presence only if a genuine "who's online" indicator is wanted for staff,
decoupled from the send path.

#### The real capacity ceiling is poolboy, not WebSockets

**[verified]** `application.ex` starts one pool: `size: 10, max_overflow: 10` — **20 concurrent flow
executions per node, shared across every organization**, with `@poolboy_checkout_timeout 25_000`.
Every inbound message, WhatsApp and web alike, funnels through it.

Little's law: 800 concurrent users at 2 msg/min = 26.7 inbound/s, which needs every flow step under
**750 ms**. Pure-Elixir steps manage that. Any step calling a webhook, Dialogflow or an LLM takes
1–10 s — at 3 s mean, the pool sustains ~6.7 msg/s, i.e. **roughly 200 concurrent web users**, before
a single WhatsApp message from any other tenant. On saturation, callers block 25 s then error.

**A busy web-channel org starves WhatsApp processing for every other tenant on that pod.** This is
the number to measure first, and it has nothing to do with sockets. 800 concurrent WebSockets is a
small number for the BEAM; this is a worker-pool problem wearing a WebSocket costume.

#### Join replay: a missing index and a thundering herd

**[verified]** The branch adds `messages_contact_id_channel_index (contact_id, channel)` — but **not
`message_number`.** So the join query index-scans `(contact_id, channel)`, heap-fetches *every* row
for that contact, sorts by `message_number DESC`, then takes 100. **Cost is linear in the contact's
total history**, not constant, and grows until the 2-month purge trims it — which NGO §7.1 says is
not on a guaranteed schedule.

Reconnect storm: 800 sockets die together, `phoenix.js` retries on an **unrandomised** ladder, so all
800 reconnect inside ~10 ms. ≈3 queries each (contact fetch, message list, media preload) = **2,400
queries into a pool of 20** (`POOL_SIZE` default 20). Under saturation `DBConnection` halves its
queue target and starts **dropping** requests — hitting every caller on the pod, including Oban and
BSP webhooks. Dropped joins crash the channel, `phoenix.js` retries on the also-unrandomised
`rejoinAfterMs`, and the herd re-forms. Transient allocation ~80–150 MB. **Every rolling deploy is a
guaranteed instance of this.**

Fixes, in order: (1) index `(contact_id, channel, message_number DESC)` CONCURRENTLY; (2) **replay by
cursor** — client sends its highest known `message_number`, server returns only the delta, which for
a 3-second blip is zero rows; (3) client jitter, which the docs already call for — but treat it as
defence in depth, since **it cannot be enforced on third-party integrators**. Cheap joins are the
fix; jitter is the mitigation.

#### Token renewal: mostly a non-issue, with one real edge

**Non-issues, and the design should not be contorted to avoid them:** BEAM timers are ~50–100 bytes
and O(1); 100k of them is unremarkable. HMAC verification is 1–2 µs, so 800 simultaneous renewals is
~1.6 ms of CPU. The HS256-vs-RS256 reasoning in the docs holds, though *operational simplicity* is
the stronger argument than verification cost — both are microseconds.

**The real edge:** if `kid → secret` resolution is a Postgres read plus a Cloak decrypt **per
verification**, every connect and renewal is a DB round trip, and the §4 storm hands 800 users tokens
in the same millisecond — so they all renew in the same millisecond, forever, on a 15-minute cycle.
Cache the per-org `kid → secret` map, invalidated on create/revoke, and **add ±10% jitter to the
`token_expiring` push time** (server-side, so it applies regardless of integrator quality).

Also: a sweep is unnecessary. `exp` is known at connect, so `Process.send_after` for exactly two
timers per session gives exact granularity with no polling — strictly better than §2.4's periodic
check, and no more code.

**[verified] Prototype/doc mismatch:** `WebChannel.Token` has `@max_age 86_400`. The shipped token
lives **24 hours**, not 15 minutes. The entire renewal apparatus is designed around a lifetime the
code does not implement.

#### Undelivered-with-no-retry, at the target scale

At 20,000 users with 800 concurrent, **96% of contacts are disconnected at any moment**, so almost
every outbound message takes the `bsp_status: :error` branch. A broadcast to 20,000 web users
generates ~19,200 error rows. Staff see failed-looking messages for ordinary offline users, and
delivery-rate reporting stops distinguishing "the send broke" from "their laptop is shut" — so nobody
can alert on the former. Add multi-replica and even *connected* users' messages land there ~(N−1)/N
of the time.

An Oban retry is the wrong shape — delivery is event-driven (the user reconnects), not time-driven.
The pattern is an **outbox with a client-acked cursor**: persist as `:pending` not `:error`;
broadcast unconditionally; client acks its highest rendered `message_number`; on join the client
sends its cursor and gets everything since. **This one change subsumes four problems** — the presence
gate, the undelivered gap, the expensive join, and the silent data loss when a user accumulates more
than 100 messages offline.

#### Check this before writing any more code

**[inferred — not confirmable from the repo]** On GCP HTTP(S) load balancers the backend
`timeoutSec` (**default 30 s**) applies to WebSockets as a *maximum connection duration*, not an idle
timeout. Gigalixir runs on GKE. If their ingress is anywhere near the default, **every socket in the
fleet is killed every 30 seconds**, producing a permanent, globally-synchronised reconnect storm.
Confirm with Gigalixir before further design work — it validates or invalidates a large part of this.

Also **[verified]** `check_origin` is built from `REQUEST_ORIGIN` / `REQUEST_ORIGIN_WILDCARD`, and
the widget is served from a different origin than the API. If it is not in that list, every
WebSocket connection is refused.

#### Ranked actions

**Blockers for multi-replica**

| # | Action | Effort |
|---|---|---|
| 1 | Delete the `connected?` gate; broadcast unconditionally | ~5 lines |
| 2 | Index `messages (contact_id, channel, message_number DESC)` CONCURRENTLY | 1 migration |
| 3 | Confirm the Gigalixir/GCP ingress WebSocket max connection duration | 1 support ticket |
| 4 | Cluster the nodes — libcluster + K8s/DNS + `RELEASE_DISTRIBUTION=name`. **Alternative worth preferring:** swap `Phoenix.PubSub` for a Redis or Postgres adapter — `Phoenix.Tracker` works over any adapter, so it fixes broadcast, Presence *and* forced disconnect without distributed Erlang or open dist ports | 1 dep + config |
| 5 | Confirm `check_origin` includes the widget origin | 1 env var |
| 6 | Replay-by-cursor + `last_delivered_message_number` + client ack; `:error` → `:pending` for offline | medium |
| 7 | **[verified]** Uncomment `+Q 65536` and set `+P` in `rel/vm.args.eex` — 65k ports is a hard per-node ceiling that fails as `emfile`, not as degradation | 2 lines |

**Matters at 10×**

Size or partition the poolboy pool (this is the actual ceiling); remove
`maybe_push_display_name/1`'s per-message `Contacts.get_contact!/1` (~40 wasted queries/s at 800
users × 3 msg/min); cache `kid → secret` and jitter the expiry push; per-connection socket rate limit
held in channel state (node-local by nature — do **not** build it on ExRated); move security-relevant
HTTP limits off ExRated; hibernate the channel after join; slim the socket assigns (two copies of a
full `%Contact{}` plus a root `%User{}` in the process dictionary).

**Premature — do not spend time here**

Replacing Phoenix.Presence with a custom tracker; worrying about BEAM process or timer counts;
cursor paging for `load_more` (decide on UX grounds, not scaling — though #6 makes it nearly free);
socket write-path backpressure; splitting the WebSocket layer into its own deployment.

#### Confirmed sound

One socket + one channel per user is the correct Phoenix shape. Per-channel timers are a non-issue.
HS256 is the right call. Media over HTTP rather than the socket avoids head-of-line blocking on an
interactive connection. The `params`-must-be-a-function finding is correct and non-obvious. Oban is
already multi-replica-ready. `RemoteIp` is correctly positioned so rate-limit buckets key on real
client IPs. The `bsp_message_id`-stays-nil reasoning is sound. **800 concurrent WebSockets is a small
number for the BEAM** — if anyone frames this as a connection-scaling problem, they are looking in
the wrong place.


### 10.3 Open: profiles, and several people sharing one phone

§2.3 containment #2 means that when several people legitimately share one number, all but the first
are unlinked. For the population this API is aimed at — students using a parent's handset, or a
shared classroom device — that is the common case, not the edge case.

**Glific already has the mechanism.** `profiles` is live and maintained (commits through #5460), and
`lib/glific/clients/bandhu.ex` runs exactly this flow in production: `fetch_user_profiles` builds a
numbered menu of the people on a phone, the user picks one, `set_contact_profile` → `switch_profile`.
It is not a name label — `Profiles.switch_profile/2` swaps `contact.fields` to `profile.fields` and
sets `language_id`, and both `messages.profile_id` and `flow_results.profile_id` exist. Per-person
flow variables, language, history and results are all already modelled.

Three things must be settled before wiring the web channel into it:

1. **Does it apply at all?** Profiles switch *inside a flow*, via a menu — a WhatsApp-shaped
   interaction. On the web it only makes sense if an adult manages several people and switches
   between them without signing out: a parent with several children, or a teacher with a classroom
   device. **Asked as an open question in the NGO doc (§8 q4).** If the answer is no, one login per
   student stands and this section closes.
2. **`active_profile_id` is a single column on the contact — the model assumes one active person at
   a time.** True for WhatsApp; false for the web, where two students on two devices can be connected
   at once. Whoever connects last wins, and the other's flow reads the wrong `fields`. Making this
   work means resolving the profile **per session**, not per contact — a real change to how
   `FlowContext` picks up fields, not a doc edit.
3. **Profile rows are created lazily.** `maybe_setup_default_profile/2` is a `defp` reached only from
   `handle_flow_action(:create_profile, …)`, so a contact in an org that never uses profiles has no
   profile row at all. This is why changelog #8 is still open: `profile.name` has nowhere to land
   today. The NGO doc states the *property* (the name is scoped to the web login and never overwrites
   the contact's WhatsApp-facing name) without naming a table, so it stays correct either way — but
   the storage decision, identity row vs `profile.name`, has to be made before implementation.
