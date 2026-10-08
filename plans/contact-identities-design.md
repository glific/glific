# Contact identities — end-to-end design

Issue #5703 · Epic #5702 · Tickets: #5836 (nil-phone safety), #5837 (schema), #5838 (username login), #5839 (inbox + console)

## 1. Model

- **`contacts`** = the person. One row per person per org. Holds name, language, fields, status,
  and (for now) WhatsApp state. **`phone` becomes nullable.**
- **`contact_identities`** = how that person logs in on a channel. One row per (contact, channel).
- Everything else (messages, flow contexts, flow results, tags, groups, tickets) stays keyed on
  `contact_id`. Nothing else changes.

```
contacts                        contact_identities
id | name | phone               contact_id | channel | identifier
42 | Asha | +919876543210       42         | web     | asha_07       (Tap linked via phone)
57 | Ravi | NULL                57         | web     | ravi_12       (username only)
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
CREATE UNIQUE INDEX contact_identities_org_channel_identifier_index
  ON contact_identities (organization_id, channel, identifier);   -- no duplicates within a channel
CREATE INDEX contact_identities_contact_id_index ON contact_identities (contact_id);

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
6. **A token is only trusted if it's signed with a non-revoked key of the org it's used in.**

## 4. Flows

### 4.1 WhatsApp inbound (unchanged)
```
Gupshup/Maytapi webhook {phone}
→ maybe_create_contact: find/create by contacts.phone
→ contact
```
No identity row is written.

### 4.2 Web, phone + OTP (unchanged)
```
request-otp(phone) → code over WhatsApp → verify-otp(phone, code)
→ find/create by contacts.phone   (same contact as WhatsApp; that's the web↔WhatsApp link)
→ Glific signs its own token {sub: contact_id}
```

### 4.3 Web, NGO token with username only
```
token {kid, sub:"ravi_12", channel:"web", iat, exp}
→ verify token (§5)
→ lookup contact_identities (org, web, "ravi_12")
   found     → that contact
   not found → transaction: insert contact (phone NULL) → insert identity → that contact
               unique conflict (two tabs) → re-read, return existing
```

### 4.4 Web, NGO token with username + phone / contact_id (Tap)
```
token {sub:"asha_07", phone:"+91…"}  or  {sub:"asha_07", contact_id: 42}
→ verify token (§5)
→ (org, web, "asha_07") already exists → that contact; phone/contact_id IGNORED
→ not found:
     target = contact by phone, or contact by contact_id (must be in this org)
     target found AND target has no web identity → insert identity on target (link)
     otherwise                                   → create new contact (4.3)
```
Guards: a `contact_id` from another org is treated as not found · one web identity per contact ·
once linked, never moved by a token.

### 4.5 Telegram / RCS / SwiftChat (later)
Same as 4.3 with `channel = :telegram` etc. That only needs a new enum value, not a new table.

### 4.6 After resolution (all paths)
```
contact_id → socket topic web_channel:<contact_id>
           → messages(channel=web, contact_identity_id=…)
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
- Header `kid`: look up `web_channel_signing_keys` (cached). Must exist, not be revoked, and belong to the
  org resolved from the subdomain.
- Algorithm pinned to HS256. Valid signature.
- `sub`, `channel = "web"`, `iat`, `exp` required. `exp - iat ≤ 1h`. ≤ 60s clock leeway. `sub` ≤ 255.
- Any failure returns the same 401.
- Glific's own post-OTP token (no `kid`) keeps working.

## 6. Per-channel state
| State | Lives on |
|---|---|
| name, language, fields, status, `last_communication_at` | `contacts` |
| WhatsApp opt-in, `bsp_status`, `last_message_at` | `contacts` **for now** |
| New channel state (web consent, Telegram opt-in…) | **columns on `contact_identities`** when needed |
| Moving WhatsApp state onto identity rows | Later, with #5765; needs a backfill |

**Contact variables (`contacts.fields`, `@contact.fields.*`, name, language) stay on `contacts`.**
They describe the person, so a linked contact shares one set across channels, and a flow on any
channel reads the same values. Unlinked contacts have separate variables because they're separate
contacts. Several people on one phone is a `profiles` concern, not an identity one.

Rule: the same value for this person on every channel → `contacts`. Only meaningful for one
channel (consent, reachability, session, per-login display name) → `contact_identities`.

`@contact.phone` is blank for web-only contacts. Document this for NGOs (webhooks, client modules).

## 7. Nil-phone safety
A phone-less contact still runs through code that reads `contact.phone`. Make it safe:
- `simulator_contact?(nil) → false`, `populate_masked_phone(nil) → nil`, `mask_phone_number(nil)`
- `Contact.changeset`: phone optional; require phone **or** an identity
- Phone lookups with nil → `{:error, _}`
- WhatsApp send / opt-in / opt-out nodes → refuse when phone is NULL
- `reports.ex` simulator filter → include NULL phones
- OTP key refuses nil

## 8. Console / admin
- **Inbox:** `contact_type in [...] OR EXISTS (identity for c.id)`
- **Contact:** `identities` field, hidden from `:staff` like `phone`
- **Signing keys:** list / create (secret shown once, max 5) / revoke, `:admin` only
- **Move identity** (optional follow-up instead of merge): re-point one identity row to another contact; history stays where it is

## 9. Not doing
- Merge contacts (the issue forbids it)
- `contacts.channels` or per-channel username columns
- Backfilling WhatsApp identity rows
- BigQuery export of identities (phone-less rows must not break REQUIRED phone columns; handle in #5759)
- CSV import by username
- Dropping `contact_type`

## 10. Delivery
| PR | Content |
|---|---|
| 1 | Nil-phone safety (§7) |
| 2 | Migrations + schemas (§2) |
| 3 | Signing keys, verifier, resolve/link (§4.3–4.4, §5), web send path fix |
| 4 | Inbox + GraphQL (§8) |

## 11. Open
1. Can the NGO rename or reassign a username? (update row / forbid)
2. Display name for a username-only contact: take a `name` claim, or leave blank?
3. Per-user logout (`tokens_valid_after`): now or later?
4. Acceptance criterion "unknown username is rejected" must be reworded. Unknown + validly signed means create.

---

## 12. `contacts` column analysis

For each column: what it does, whether it's written on every message (hot path), whether it
belongs to the **person** or to a **channel**, and what to do with it.
"Move" means to `contact_identities`. **Nothing moves in #5703.** Moves happen in the next PR
(opt-in migration), which also does the WhatsApp backfill.

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
| **Move to `contact_identities` (next PR)** | bsp_status, optin_time, optin_method, optout_time, optout_method, last_message_at, `status` valid/invalid part |
| **Becomes the WhatsApp identifier (next PR)** | phone |
| **Retire / derive** | optin_status, optin_message_id, first_message_number, is_contact_replied (later is_org_replied) |
| **Leave untouched, retire later** | contact_type |

### 12.3 What `contact_identities` grows into (next PR, not #5703)

```
contact_identities
  id, contact_id, organization_id, channel, identifier, inserted_at, updated_at   ← #5703
  bsp_status, delivery_status (valid/invalid)                                     ← reachability
  optin_time, optin_method, optout_time, optout_method                            ← consent
  last_message_at                                                                 ← session window
  metadata jsonb   (e.g. provider: gupshup / maytapi = today's WABA / WA)
```
Needs: a backfilled `(whatsapp, phone)` row per contact, and a unique `(contact_id, channel)` so the
trigger and `can_send_message_to?` can find "this contact's WhatsApp row" in one indexed lookup.

### 12.4 Hot path today: what runs on every message

`message_before_insert_callback` (BEFORE INSERT on messages, 1:1 messages only):
- Reads `contacts.last_message_number`, `active_profile_id` → stamps `message_number`, `profile_id`.
- **Inbound:** `UPDATE contacts SET last_communication_at, last_message_at (skipped for web),
  last_message_number, is_org_read=false, is_org_replied=false, is_contact_replied=true, updated_at`.
- **Outbound:** `UPDATE contacts SET last_communication_at, last_message_number, is_org_replied=true,
  is_contact_replied=false, updated_at`.

Plus `set_session_status` from Elixir on every WA inbound (`bsp_status`).

Implications:
- Moving `last_message_at` / `bsp_status` to identities means the trigger / `set_session_status`
  update the identity row instead, so the `(contact_id, channel)` index is needed.
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
