# Contact identities — end-to-end design

Issue #5703 · Epic #5702 · Tickets: #5836 (nil-phone safety), #5837 (schema), #5838 (username login), #5839 (inbox + console)

## 1. Model

- **`contacts`** = the person. One row per person per org. Holds name, language, fields and
  `status` (blocked / valid / invalid, split later, §12.1). **`phone` becomes nullable.**
- **`contact_identities`** = how that person is identified on a channel (a WhatsApp phone, an NGO
  username, later a Telegram chat id), and the person's consent and session state **on that
  channel**: opt-in and opt-out, and for WhatsApp the BSP status and the last inbound message. One
  row per login, so a contact can have several (§6, §12.3).
- Everything else (messages, flow contexts, flow results, tags, groups, tickets) stays keyed on
  `contact_id`. Nothing else changes.

```
contacts                        contact_identities
id | name | phone               contact_id | channel  | identifier
42 | Asha | 919876543210        42         | whatsapp | 919876543210  (WhatsApp)
                                42         | web      | asha_07       (NGO username, linked via phone)
57 | Ravi | NULL                57         | web      | ravi_12       (username only)
```

## 2. Schema

```sql
-- new table
CREATE TABLE contact_identities (
  id              bigserial PRIMARY KEY,
  contact_id      bigint NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id bigint NOT NULL REFERENCES organizations(id),
  channel         message_channel_enum NOT NULL,
  identifier      varchar(255) NOT NULL,
  inserted_at     timestamp NOT NULL,
  updated_at      timestamp NOT NULL
);
CREATE UNIQUE INDEX contact_identities_organization_id_channel_identifier_index
  ON contact_identities (organization_id, channel, identifier);   -- no duplicates within a channel
CREATE INDEX contact_identities_contact_id_index ON contact_identities (contact_id);
-- identifier: web usernames are letters, digits, _ @ . only, stored lowercase (case-insensitive);
--             WhatsApp identifiers are the contact's phone as stored.
-- Enforced by ContactIdentity.changeset/2 (`^[a-z0-9_@.]+$` after downcasing), not by the database.

-- contacts
ALTER TABLE contacts ALTER COLUMN phone DROP NOT NULL;           -- catalog-only
-- keep the unique index (phone, organization_id): NULLs don't collide
```

Not added: `contacts.channels`, per-channel username columns. No backfill. `contact_type` is left alone.

## 3. Rules

1. **The entry point decides the lookup.** It never falls back from one to the other.
2. **Within a channel:** never a duplicate (unique index).
3. **Across channels:** duplicates are OK when nothing links them.
4. **Linking is one insert (or one row update), never a merge.** No history is rewritten.
5. **Never look up a contact by a nil phone.**
6. **A token is only trusted if it's signed with the JWT signature secret (or previous secret) of the org it's used in.**

## 4. Flows

### 4.1 WhatsApp inbound (unchanged)
```
Gupshup/Maytapi webhook {phone}
→ maybe_create_contact: find/create by contacts.phone
→ contact
```
The contact's `(whatsapp, phone, <phone>)` identity is written when it's created (or on its first
lookup, so existing contacts keep working until the WhatsApp identities are backfilled in the next PR).
Every channel creates a contact through `Contacts.create_contact(attrs, channel \\ :whatsapp, identifier \\ nil)`
(the identifier defaults to the phone), which inserts the contact and its identity in one transaction: a contact never exists
without its identity.

Identities are only reached through `Glific.Contacts`: an identity is part of a contact, so nothing outside
`lib/glific/contacts/` calls `Glific.Contacts.ContactIdentities` or queries `ContactIdentity`. `ContactIdentities` is internal to the
context; callers use `Contacts.create_contact/1`, `fetch_by_identity/2`, `maybe_create_contact/3`,
`add_identity/3` and `insert_contacts/2` (bulk import). `set_whatsapp_identity/1`
keeps the WhatsApp identity in step with the phone.

### 4.2 Web, phone + OTP
```
request-otp(phone) → code over WhatsApp → verify-otp(phone, code)
→ find/create the contact by phone   (same contact as WhatsApp; that's the web↔WhatsApp link)
→ record (web, <phone>) on that contact if missing   (it signed in on the web with its phone)
→ Glific signs its own token {sub: contact_id}
```
OTP contacts also get their `(whatsapp, <phone>)` identity when created (the phone is verified by the
code sent over WhatsApp). Web identities share one namespace for phones and NGO usernames, so an NGO
username equal to an OTP user's phone resolves to that user: NGOs must never use another person's
phone number as a username (NGO contract, §5).

### 4.3 Web, NGO token with username only
```
WebSocket connect with token {sub:"ravi_12", channel:"web", iat, exp}
→ verify token (§5)
→ lookup contact_identities (org, web, "ravi_12")
   found     → that contact
   not found → transaction: insert contact (phone NULL) → insert identity → that contact
               unique conflict (two tabs) → re-read, return existing
```

### 4.4 Web, NGO token with username + phone
```
token {sub:"asha_07", phone:"919876543210"}
→ verify token (§5)
→ (org, web, "asha_07") already exists → that contact; phone IGNORED
→ not found:
     phone is a WhatsApp contact's phone → add (web, "asha_07") to that contact: one person, one
                                           contact across channels
     otherwise → create a new contact (4.3), keeping the phone in contacts.phone but writing NO
                 (whatsapp, phone) identity: the phone was not verified (no OTP), so the WhatsApp
                 identity is only written when that number first messages on WhatsApp (the
                 contacts.phone fallback in fetch_by_identity)
     unique conflict on (org, web, "asha_07") (two tabs) → re-read, return the existing identity's contact
```
The token has no `contact_id` claim; staff can also link a username to any contact with
`addContactIdentity`.

A phone sent in the token is treated as the user's own: the username joins that number's
conversation, or the new contact owns it, so NGOs must only send phones they have verified belong
to the user (NGO-trust assumption).

Guards: the organization's own contact and simulator contacts are never linked to, and their phones
are never stored on a new contact · an identifier that already exists is never moved by a token ·
an identity always takes its `organization_id` from its contact.

### 4.5 Telegram / RCS / SwiftChat (later)
Same as 4.3 with `channel = :telegram` etc. That only needs a new enum value, not a new table.

### 4.6 After resolution (all paths)
```
contact_id → internal PubSub topic web_channel:<contact_id>, relayed to the client's `web_channel:conversation` join
           → messages(channel=web)   (no contact_identity_id: messages record the channel, not the login)
           → flows / flow_results / tags / inbox exactly as today
```
The web socket handlers pass the resolved contact straight through. They do **not** look it up
again by phone.

### 4.7 Outbound
| `messages.channel` | Delivered via | Needs |
|---|---|---|
| whatsapp | BSP | `contacts.phone`; refuse if NULL |
| web | Socket broadcast | `contact_id` only |

A reply goes out on the channel the conversation/flow came in on (already built in #5660).

## 5. Token verification (NGO-signed)
- Signed with any of the organization's JWT signature secrets: one list, `jwt_signature_secrets`, of
  at most two `{name, secret}` entries (none is "current" or "previous"), kept in the org's `web_channel`
  credential (set on the Settings page). To rotate, add the new secret, switch the backend, then
  remove the old one. The organization comes from the
  subdomain; there is no `kid`.
- Algorithm pinned to HS256. Valid signature. A secret shorter than 32 characters is ignored (a token cannot verify against it).
- A `phone` claim is trusted as the user's own (see §4.4): the NGO must only send verified phones.
- `sub`, `channel = "web"`, `iat`, `exp` required. `exp - iat ≤ 24h` (the NGO may issue shorter
  tokens, e.g. 6h). ≤ 60s clock leeway. `sub` ≤ 255.
- Any failure refuses the connection the same way.
- No session layer: the NGO token itself authenticates the WebSocket connect; Glific issues no token
  of its own. Before it expires the client sends a fresh NGO token as a `renew_token` message on the
  socket, which must resolve to the same contact; the expiry is updated in memory. A background sweep
  closes any socket whose token has expired. Reissuing tokens is the NGO's job.
- Glific's own web channel (phone + OTP) keeps its platform-issued token and `renew-token`.
- A contact is created on the first connect with a new username (`Contacts.maybe_create_contact(claims, :web, username)`), or
  ahead of time by staff through the GraphQL `createContact` mutation with `channel: WEB` and an `identifier`, or by
  adding a username to an existing contact with `addContactIdentity(contactId, channel: WEB, identifier)`. There is no REST
  provisioning endpoint.
- NGO contract: `sub` must be unique across every system the NGO signs tokens from. A `sub` must never be another person's phone number: web identities from phone + OTP logins
  share the namespace, so such a `sub` would sign in as that person. Identities are
  unique per organization, so two systems issuing the same `sub` would log in as one contact.
- Phones (in the `phone` claim and in identifiers) are digits with country code and no `+`, the format
  `Contacts.parse_phone_number/1` stores. Identifiers may only contain letters, digits, `_`, `@` and
  `.`, and are case-insensitive: they are stored lowercase, so a token `sub` of `Ravi_Web` and one of
  `ravi_web` are the same identity.

## 6. Per-channel state
| State | Lives on |
|---|---|
| name, language, fields, status, `last_communication_at` | `contacts` |
| WhatsApp opt-in / opt-out, `bsp_status`, `last_message_at` | The contact's **`(whatsapp, phone)` identity row** (moved off `contacts` in one release, §12.3) |
| Web consent (and later Telegram opt-in…) | The identity row the contact logs in with: `(web, username)` for an NGO token, `(web, phone)` for an OTP |

**Contact variables (`contacts.fields`, `@contact.fields.*`, name, language) stay on `contacts`.**
They describe the person, so a linked contact shares one set across channels, and a flow on any
channel reads the same values. Unlinked contacts have separate variables because they're separate
contacts. Several people on one phone is a `profiles` concern, not an identity one.

Rule: the same value for this person on every channel → `contacts`. Only meaningful for one
channel (consent, reachability, session) → the identity row for that channel. A contact can hold
several identities on one channel (two NGO usernames), so each carries its own consent; the
WhatsApp channel has exactly one, the contact's phone, so its row is "the contact's WhatsApp state".
There is no separate per-channel table.

`@contact.phone` is blank for web-only contacts. Document this for NGOs (webhooks, client modules).

## 7. Nil-phone safety
A phone-less contact still runs through code that reads `contact.phone`. Make it safe:
- `simulator_contact?(nil) → false`, `populate_masked_phone(nil) → nil`, `mask_phone_number(nil)`
- `Contact.changeset`: phone optional. "Phone or an identity" can't be checked there (the identity is
  inserted after the contact), so the phone-less creation path (§4.3) inserts both in one transaction,
  and phone-based creation (`create_contact`, `upsert`) still requires a phone
- Phone lookups with nil → `{:error, _}`
- WhatsApp send / opt-in / opt-out nodes → refuse when phone is NULL
- `reports.ex` simulator filter → include NULL phones
- OTP key refuses nil

## 8. Console / admin
- **Inbox:** `contact_type in [...] OR EXISTS (identity for c.id)`
- **Contact:** `identities` field, hidden from `:staff` like `phone`
- **JWT signature secret:** set and rotated on the Web Channel settings page (the `web_channel` credential); no separate key management
- **Move identity** (optional follow-up instead of merge): re-point one identity row to another contact; history stays where it is

## 9. Not doing
- Merge contacts (the issue forbids it)
- `contacts.channels` or per-channel username columns
- Backfilling WhatsApp identity rows in this PR (done in the next PR with web opt-in)
- BigQuery export of identities (phone-less rows must not break REQUIRED phone columns; handle in #5759)
- CSV import by username
- Dropping `contact_type`

## 10. Delivery
| PR | Content |
|---|---|
| 1 | Nil-phone safety (§7) |
| 2 | Migrations + schemas (§2) |
| 3 | JWT signature secret, verifier, WebSocket connect + renewal with the NGO token, find-or-create (§4.3–4.4, §5), WhatsApp identities written on create and phone change, with a lookup fallback to `contacts.phone` |
| 4 | Inbox + GraphQL (§8) |

## 11. Open
1. Can the NGO rename or reassign a username? Deferred until after these PRs: either the NGO's backend calls the existing GraphQL API, or a username change is sent over the WebSocket.
2. Display name for a username-only contact: take a `name` claim, or leave blank?
3. Per-user logout (`tokens_valid_after`): now or later?
4. Acceptance criterion "unknown username is rejected" must be reworded. Unknown + validly signed means create.

---

## 12. `contacts` column analysis

For each column: what it does, whether it's written on every message (hot path), whether it
belongs to the **person** or to a **channel**, and what to do with it.
"Move" means to `contact_identities`. **Nothing moves in #5703.** The moves ship together in one
later release (§12.3), whose backfill also creates the WhatsApp identity of every existing contact
with a phone. The web channel isn't open to end users before it runs, so no existing phone came from
an NGO token. The `contacts.phone` fallback in `fetch_by_identity` stays for phones an NGO token
stores on a new contact after that.

Enums: `status` = blocked / failed / invalid / processing / valid ·
`bsp_status` = none / session / session_and_hsm / hsm.

### 12.1 Column by column

| Column | What it does | Hot path? | Belongs to | Recommendation |
|---|---|---|---|---|
| `id` | PK; everything (messages, flows, results, histories, socket topic) points at it | — | Person | **Keep** |
| `organization_id` | Tenant | — | Person | **Keep** (also on identities) |
| `name` | Display name. **Overwritten by the WhatsApp push-name** on inbound when it changes (`contacts.ex:1076-1100`); flows/GraphQL also set it. Web never writes it | WA inbound, on change | Person (but WA-sourced) | **Keep.** Later, optionally a per-login display name on the identity so WA push-name changes don't clobber a web name |
| `phone` | WhatsApp number; unique per org; lookup key for every WA inbound and the web OTP; BSP send destination; BQ `REQUIRED` + dedupe key | read on every WA inbound | **Channel identifier (WhatsApp)** | **#5703: keep, make nullable.** Next PR: becomes `(whatsapp, phone)` identity rows (backfill); decide then whether `contacts.phone` is dropped or kept as a cached copy |
| `contact_type` | `WABA` (business number, Gupshup) / `WA` (Maytapi groups) / `WABA+WA`. Inbox shows only WABA/WABA+WA (`searches.ex:179,259`) | WA inbound, on change | Channel (WhatsApp sub-route) | **Keep untouched** (meeting decision). Username contacts: NULL, visible via the inbox `EXISTS`. Retire later in favour of whatsapp identity + provider metadata |
| `status` | Only 3 values are ever set: `valid` (opt-in, `contacts.ex:512`), `invalid` (**every opt-out** and BSP "number does not exist", both via `opted_out_attrs`, `contacts.ex:571,614`), `blocked` (staff). `failed`/`processing` are never set on contacts. WhatsApp sends require `valid` (`can_send_message_to?`); web checks only `blocked`. Group broadcasts filter `status == :valid` (`groups.ex:358`), so a WA opt-out also excludes the contact from web broadcasts | no | **Mixed** | **Split later:** `blocked` stays on contacts (person); `valid`/`invalid` becomes the WhatsApp identity's reachability (cause in `optout_method`) |
| `bsp_status` | WA reachability (session / hsm / both / none). Set on every WA inbound (`set_session_status`), reset by cron after 24h. Gates `can_send_message_to?`. Web never writes it and bypasses it | **yes** (WA inbound, Elixir) | Channel (WhatsApp) | **Move** → whatsapp identity |
| `language_id` | Preferred language; flow localization, templates, `@contact.language`. Overridden by the active profile | no | Person | **Keep** |
| `optin_time` | When WhatsApp consent was given. HSM gate (`contacts.ex:644`), session status, stats, reports | no | Channel (WA consent, #5713) | **Move** → whatsapp identity |
| `optin_status` | "Currently opted in"; inbox Optin tab, collection counts | no | Channel (WA) | **Move, or retire**: derivable from `optin_time` vs `optout_time` |
| `optin_method` | BSP / WA / Import / registration / Glific Flows… | no | Channel (WA) | **Move** |
| `optin_message_id` | BSP message id that triggered opt-in; only used in history meta; not in BQ/GraphQL | no | Channel (WA/BSP) | **Retire** (history already records it) |
| `optout_time` | When they opted out; inbox Optout tab, **group broadcast eligibility** (`groups.ex:388`, so a WA optout also blocks web broadcasts today), stats | no | Channel (WA) | **Move** (fixes the cross-channel broadcast block) |
| `optout_method` | How they opted out | no | Channel (WA) | **Move** |
| `last_message_at` | Last **WhatsApp** inbound = 24h session window. Trigger already skips web (migration `20260910000000_scope_last_message_at_to_whatsapp`). Also used for stats "daily active" and search ordering | **yes** (trigger) | Channel (WhatsApp) | **Move** → whatsapp identity. Web needs no window |
| `last_communication_at` | Last message any direction, any channel → **inbox ordering** (indexed) | **yes** (trigger) | Person | **Keep** (derivable, but it's the inbox sort key) |
| `is_org_read` | Staff read the latest inbound; "Unread" tab. Staff action, not derivable | **yes** (trigger) | Person (inbox) | **Keep** |
| `is_org_replied` | Last message was outbound; "Not replied" tab | **yes** (trigger) | Person (inbox) | **Keep for now** (combined view); per-channel for channel views, see §12.7; retire candidate in a perf ticket |
| `is_contact_replied` | Last message was inbound; "Not Responded" tab. Effectively `!is_org_replied` | **yes** (trigger) | Person (inbox) | **Keep for now** (combined view); per-channel for channel views, see §12.7; retire candidate in a perf ticket |
| `first_message_number` | Lowest retained message number after pruning; only used by `Erase` | no | Person | **Retire** (derive `min(message_number)`) |
| `last_message_number` | Per-contact message counter **shared across channels**; trigger stamps `messages.message_number`; conversation pagination windows (`conversations.ex:83-84`) | **yes** (trigger, row lock) | Person (sequence) | **Keep.** Changing it is #5708 territory |
| `settings` | jsonb; only `"preferences"` (flow-set booleans). BQ exports nil | no | Person | **Keep**; low use, fold into `fields` someday |
| `fields` | Custom contact variables (`@contact.fields.*`); mirrored to the active profile | only when flows set fields | Person | **Keep**: shared across channels (§6) |
| `active_profile_id` | Which profile (person behind a shared number) is acting; trigger stamps `profile_id` on messages, flow contexts, results, histories | read on every message | Person (sub-person) | **Keep for now.** Open: two people on two devices at once need it per session/identity (design §10.3) |
| `inserted_at` | Created | no | Person | **Keep** |
| `updated_at` | Bumped **on every message** by the trigger, and on tag/group changes; **drives BigQuery incremental sync** of contacts | **yes** (trigger) | Person | **Keep.** Moving message state off `contacts` would reduce BQ re-exports |

### 12.2 Summary

| Bucket | Columns |
|---|---|
| **Keep on `contacts` (person)** | id, organization_id, name, language_id, fields, settings, active_profile_id, last_communication_at, is_org_read, last_message_number, inserted_at, updated_at |
| **Move to `contact_identities` (§12.3)** | bsp_status, optin_time, optin_method, optout_time, optout_method, last_message_at, `status` valid/invalid part |
| **Becomes the WhatsApp identifier** | phone |
| **Retire / derive** | optin_status, optin_message_id, first_message_number, is_contact_replied (later is_org_replied) |
| **Leave untouched, retire later** | contact_type |

### 12.3 Where per-channel state goes: the identity row (one release)

`contact_identities` gains the moved columns, with the types they had on `contacts`:

```
contact_identities (existing: contact_id, organization_id, channel, identifier, timestamps)
  optin_time, optin_status (default false), optin_method          ← consent
  optout_time, optout_method
  bsp_status (default none), last_message_at                      ← WhatsApp session
```

Not moved: `optin_message_id` (nothing reads it; the opt-in history event records the message id),
and `status` (valid / invalid / blocked), which stays on `contacts` until it is split (§12.1).

**Where each event writes**
- A WhatsApp event (BSP opt-in/opt-out, flows, GraphQL, imports, the 24 hour session reset,
  Maytapi, "number does not exist") writes the contact's `(whatsapp, phone)` row.
- A web consent writes the web identity the contact logged in with, never the WhatsApp row:
  `(web, username)` on an NGO token connect, `(web, phone)` on an OTP verify. The first opt-in is
  kept, a repeat login changes nothing, and a login after an opt-out clears the opt-out.
- `message_before_insert_callback` sets `last_message_at` on the WhatsApp row for an inbound
  non-web message, found through the `contact_id` index. The other columns it maintains on
  `contacts` (`last_communication_at`, `last_message_number`, the read and replied flags) stay.

**Single release, backfill afterwards.** Nothing writes the old `contacts` columns once the release
is out, and the backfill (`Glific.Contacts.IdentityBackfill`) runs from the console afterwards. Until
a contact's WhatsApp row exists:
- reads use the row when present and otherwise the contact's own columns, which are still current
  because nothing writes them. The rule is per row, never per field: an opt-out sets `optin_time`
  to null on the row, and that null must not fall back to the stale value on `contacts`;
- a write first creates the row from the contact's current columns, then applies the change;
- the backfill only inserts missing rows, copying the contact's current columns, so it never
  overwrites a row the application created.

The whole fallback lives in `Glific.Contacts.WhatsAppState` (reads, seeding, and the SQL used by
inbox, stats and broadcast filters). The trigger inserts a missing row the same way. Once the
backfill is complete these are deleted in one change, along with the `contacts` columns.

**Rollback.** `Glific.Scripts.RestoreContactWhatsappState` copies the rows back onto `contacts`, so a
rolled-back release sees the opt-ins, opt-outs and sessions recorded since.

### 12.4 Hot path today: what runs on every message

`message_before_insert_callback` (BEFORE INSERT on messages, 1:1 messages only):
- Reads `contacts.last_message_number`, `active_profile_id` → stamps `message_number`, `profile_id`.
- **Inbound:** `UPDATE contacts SET last_communication_at, last_message_at (skipped for web),
  last_message_number, is_org_read=false, is_org_replied=false, is_contact_replied=true, updated_at`.
- **Outbound:** `UPDATE contacts SET last_communication_at, last_message_number, is_org_replied=true,
  is_contact_replied=false, updated_at`.

Plus `set_session_status` from Elixir on every WA inbound (`bsp_status`).

Implications:
- `last_message_at` / `bsp_status` live on the WhatsApp identity row, so the trigger and
  `set_session_status` update that row instead, through the `contact_id` index (§12.3).
- The goal from the meeting ("message insert should be simple, derived fields in background") is
  the separate perf ticket covering `is_*`, `last_message_number` and `updated_at`. Not #5703.

### 12.5 Things the analysis found (outside #5703, worth tickets)

| Finding | Where | Impact |
|---|---|---|
| **Web inbound skips the blocked check.** WhatsApp inbound calls `contact_blocked?`; `WebMessage.receive_message` doesn't | `communications/message.ex:218` vs `web_message.ex` | A blocked contact can still send over the web |
| **A WhatsApp optout blocks web group broadcasts** | `groups.ex:388` `is_nil(optout_time)` | Fixed by moving consent to identities |
| **`session_uuid` is effectively always new.** `var_message_at` is declared but never assigned, so `current_diff` is NULL | `message_after_insert_callback`, `structure.sql` | Message sessions never group (pre-existing bug) |
| **`structure.sql` is stale**: no `contact_type`, `first_message_number`, `messages.channel` | `priv/repo/structure.sql` | Regenerate in PR 2 |
| `update_profile_id_*` triggers exist only in `structure.sql`, not in any migration | `structure.sql:680-730` | A DB built from migrations alone may lack them; check |
| `last_message_at` now means "last WhatsApp activity", but stats "daily active" and search ordering still read it as general activity | `stats.ex:365`, `searches.ex:542,556` | Web-only users don't count as active |
| WhatsApp push-name overwrites `name` | `contacts.ex:1076-1100` | A linked person's web name can be replaced by their WA name |

### 12.6 BigQuery (option B: keep the schema, fill it internally)
- After the move, the contacts row builder (`bigquery_worker.ex:~989`) reads consent / bsp_status /
  last_message_at from the whatsapp identity and writes the same BQ columns, so there's no downstream change.
- **`phone` (and `status`, `provider_status`) are `REQUIRED` in BQ.** Phone-less contacts exist from
  #5703 on, so relax `phone` to `NULLABLE` (BigQuery allows REQUIRED → NULLABLE) before the first one,
  or skip phone-less rows. Decide in #5703.

### 12.7 Inbox "Not Responded" / "Not replied" per channel (with #5708, not #5703)

When the inbox gets WhatsApp-only and web-only views, each view uses only that channel's messages:

| Inbox view | "Not Responded" (`is_contact_replied`) / "Not replied" (`is_org_replied`) uses |
|---|---|
| All channels (default; sends no channel filter) | Latest message on **any** channel: today's contact-level flags, unchanged |
| WhatsApp only | Latest **WhatsApp** message |
| Web only | Latest **web** message |

Example: NGO messages Asha on WhatsApp, she replies on web → combined view: replied · WhatsApp
view: not responded · web view: replied.

Per-channel is **added on top of** the contact-level flags, not a replacement. Two ways to get it,
decided in #5708:

| Option | How | Cost |
|---|---|---|
| Store | Per-channel flags on the channel state row; the trigger updates them on every message | One more write per message (hot path) |
| Compute | "Latest message on this channel for this contact is inbound/outbound" from `messages` | Heavier inbox query; needs index `(contact_id, channel, message_number)` (#5660 deferred it to the ticket that adds the query) |

No change in #5703.
