# Web Channel — Backend Change Breakdown

A file-by-file map of what the backend touches, grounded in the **actual prototype diff** (20
modified files, 272 insertions; 7 new source modules; 3 migrations) reconciled against the
**design decisions locked this session**. It exists so the tech design can state precisely what is
additive, what is a modification to shared code (blast-radius risk), and what still has to be
built or reworked to match the agreed behaviour.

**Legend**
- **[A] Additive** — net-new file/field; existing code paths untouched. Low risk.
- **[M] Modification** — edits shared code that WhatsApp also runs through. Needs regression care.
- **[R] Rework** — the prototype does something the locked design has since superseded; must change.
- **[N] Net-new (not yet built)** — required by the design, absent from the prototype.

---

## 1. Data model & migrations

| File | Kind | Change |
|---|---|---|
| `priv/repo/migrations/20260715000000_add_channel_to_messages.exs` | [M] | `messages.channel :string default "whatsapp" null: false` + index `[:contact_id, :channel]`. |
| `priv/repo/migrations/20260715085302_add_channel_to_flow_contexts.exs` | [M] | `flow_contexts.channel` — pins a context to its triggering channel. |
| `priv/repo/migrations/20260715085249_add_web_message_flow_type.exs` | [M] | `ALTER TYPE flow_type_enum ADD VALUE 'web_message'` (non-transactional). |
| `lib/glific/messages/message.ex` | [M] | `field :channel`, `@type`, optional-cast list, `validate_inclusion` against the enum. |
| `lib/glific/flows/flow_context.ex` | [M] | `field :channel default "whatsapp"`, `@type`, `init_context` reads `:channel` opt. |
| `lib/glific/enums/constants/enums.ex` | [M] | `@flow_type_const` gains `:web_message`; new `@message_channel_const` (7 channels). |
| `lib/glific/enums/enums.ex` | [A] | `message_channel_const/0` macro + doctest. |

**Two migration-safety findings the doc must call out:**

1. **`add :channel, ... null: false` on `messages` rewrites the whole table.** `messages` is one of
   the largest production tables; per `priv/repo/migrations/CLAUDE.md` a non-null-default add is a
   full rewrite and lock. **Rework to:** add the column **nullable, no default**; backfill
   `"whatsapp"` in a batched follow-up (or Oban job); then set the default. The application already
   defaults `channel` to `"whatsapp"` at the schema layer, so reads are safe during the window.
   This finding is the hinge of the BigQuery-compatibility question (see the schema/BigQuery doc).

2. **`flow_type` is a real Postgres enum type**, not a string (the `ALTER TYPE` proves it). That
   makes the `flow_type` → `supported_channels`-array question (below) a **non-trivial migration**,
   not a field rename. Decide before building, because reversing an enum value is impossible
   (`down` is a documented no-op).

---

## 2. Transport (net-new infra — all additive)

| File | Kind | Change |
|---|---|---|
| `lib/glific_web/channels/web_channel_socket.ex` | [A] | `WebChannelSocket` — verifies contact token, sets org+root-user context, assigns `current_contact`. |
| `lib/glific_web/channels/web_channel/room_channel.ex` | [A] | `RoomChannel` topic `web_channel:<contact_id>`: join→last 100, `load_more`, `new_message`, `update_name`, presence track. |
| `lib/glific_web/channels/web_channel/presence.ex` | [A] | `WebChannel.Presence` (`use Phoenix.Presence`). |
| `lib/glific_web/channels/web_channel/token.ex` | [A]→[R] | Contact token. **Rework:** see §4 (Phoenix.Token → JWT + refresh). |
| `lib/glific_web/endpoint.ex` | [M] | Mounts `socket("/web_socket", …)` beside `/socket` and `/live`. One line; isolated. |
| `lib/glific/application.ex` | [M] | Adds `WebChannel.Presence` to the supervision tree. |

The transport is the cleanest part of the prototype — genuinely additive, no WhatsApp path
touched. **Net-new still needed:** `room_channel.ex` must gain a **presence-driven resume** hook
(§5) — on `:after_join`, wake any context that presence-parked while the contact was away.

---

## 3. Send path (channel-aware fork)

| File | Kind | Change |
|---|---|---|
| `lib/glific/providers/web/message.ex` | [A]→[R] | `Providers.Web.Message` (`@behaviour MessageBehaviour`). Text/media = synchronous socket broadcast, no Oban/HTTP. `send_interactive`/`send_sticker` → `{:error, …}`. **Rework `deliver/2`:** see §5. |
| `lib/glific/communications/web_message.ex` | [A] | `Communications.WebMessage` — mirrors `WAGroupMessage`. `send_message/2`, `receive_message/2`. Correctly **does not** call `set_session_status` (avoids the 24h-window landmine). Publishes `:sent_message`/`:received_message` to staff inbox. |
| `lib/glific/messages.ex` | [M] | `list_conversation_messages/3` (per-contact per-channel history, [A]); `check_for_hsm_message(%{channel:"web"}, _)` clause routing outbound to `WebMessage`, bypassing HSM/interactive/session gates ([M], ordered before the generic clause). |
| `lib/glific/providers/message_behaviour.ex` | [M] | Return-type union widened to `{:ok, Oban.Job.t()} | {:ok, Message.t()}` so synchronous channels satisfy the same behaviour. Every provider sees the wider spec (dialyzer-only impact). |
| `lib/glific/communications/message.ex` | [M] | `process_message/1` made public so `WebMessage.receive_message` reuses the poolboy dispatch. Low risk (visibility only). |

---

## 4. Auth (prototype is a stub — largest [R]/[N] gap vs the locked design)

| File | Kind | Change |
|---|---|---|
| `lib/glific_web/controllers/api/v1/web_channel_auth_controller.ex` | [A]→[R] | `request_otp`/`verify_otp`. Prototype: no SMS, accepts `"9999"` behind `:web_channel_otp_bypass`. |
| `lib/glific_web/channels/web_channel/token.ex` | [R] | Prototype signs an opaque `Phoenix.Token` (`max_age 86_400`). |
| `lib/glific_web/router.ex` | [M] | Two public routes in the non-authed pipeline. |
| `config/dev.exs`, `config/test.exs` | [M] | `web_channel_otp_bypass: true` (must stay unset in prod/runtime). |

**Rework/net-new to match the auth decisions (see `web-channel-auth-research.md`):**

- **[R] JWT (HS256), per-org signing secret** replacing the opaque Phoenix.Token — so a future
  NGO-minted delegated token verifies through the same path (embeddable-later hedge). Claims:
  `contact_id`/`phone`, `org`, short `exp`.
- **[N] Short access token + long refresh token.** The "30-day session" = refresh-token lifetime,
  **not** a 30-day bearer. Needs a **new `web_channel_sessions` (or device) table** (migration +
  schema + context) to make refresh revocable and support logout/DPDP erasure.
- **[N] Real SMS OTP** (India provider — pending research) replacing the `9999` bypass, with the
  bypass hard-failing under `MIX_ENV=prod`.
- **[N] `request_otp` rate limiting per-phone AND per-IP.** Prototype defers to a generic
  `RateLimitPlug`; the design requires phone+IP limits specifically, since this endpoint runs
  before a contact exists (per-contact limiting can't protect it) and each call will cost an SMS.

---

## 5. Flow gating & the presence/switch-over reworks

| File | Kind | Change |
|---|---|---|
| `lib/glific/flows/action.ex` | [M]→[R] | 3 guard clauses reject `send_interactive_msg`/`send_broadcast`/templated `send_msg` under `%{channel:"web"}` via `notification` + continue. |
| `lib/glific/flows/flow.ex` | [M] | `web_channel_capability_errors/2` — publish-time validation walks nodes for unsupported types on a `:web_message` flow. Also surfaces `flow_type` in the cached flow map. |
| `lib/glific/flows/contact_action.ex` | [M] | Propagates `context.channel` into outbound send attrs so replies route back over the origin channel. |
| `lib/glific/processor/consumer_flow.ex` | [M]→[N] | Threads `message.channel` into `init_context` (both start paths). |

**Three deltas from the locked design — the important part of this doc:**

1. **[R] Presence: drop-and-continue → pause-and-resume.** Prototype `Providers.Web.Message.deliver/2`
   sends anyway when the contact is absent and marks `bsp_status: :error`, and the **flow keeps
   running**. The locked design (scenarios §4) is the opposite: if absent, **do not send — pause
   the flow at that node**, and deliver + resume on reconnect. This requires:
   - `deliver/2` to signal "not delivered / absent" rather than persist-as-error;
   - the flow send path to **park the context** on that signal (reuse the `wakeup_at`/parking
     machinery, but event-driven);
   - `room_channel.ex` `:after_join` to **resume** parked contexts via `wakeup_one/2`.
   Also drop the `bsp_status: :error` semantics — `bsp_status` is WhatsApp vocabulary and an absent
   web contact is not a delivery failure (naming debt noted separately).

2. **[N] Channel-scoped continuation (switch-over rule, scenarios §1).** Prototype only *propagates*
   channel; it does **not** make continuation channel-aware. `active_context`/`continue_the_context?`
   in `consumer_flow.ex`/`flow_context.ex` must only continue a context when the inbound message's
   channel equals the context's pinned channel; a mismatch is treated as no active context (falls
   through to fresh routing). This is the fix for the accidental cross-channel takeover and is
   currently unbuilt.

3. **[R] Capability gating is scattered, not a registry.** The rules live in 3 places (action.ex
   guards, flow.ex validation, and the frontend `setConfig`). The extensibility decision is a
   single `Glific.Channels.capabilities/1` source of truth all gates consume. Recommended refactor
   **now**, while there are only two channels — the RCS research feeds its shape.

---

## 6. GraphQL / staff inbox (additive)

| File | Kind | Change |
|---|---|---|
| `lib/glific_web/schema/message_types.ex` | [M] | `channel :string` on the message object **and** the send-message input (staff reply routing). |
| `lib/glific_web/schema/flow_types.ex` | [M] | `flow_type` on `:flow_input` (create/edit picks channel). |
| `assets/gql/messages/fields.frag.gql` | [M] | `channel` in the message fragment. |

The unified staff inbox is mostly frontend; the backend contract is just the `channel` field
(read) + accepting `channel` on the send input (write → routes via the §3 fork). **Net-new not in
the prototype:** the daily **metrics rollup table** (`org_id, channel, date, active_contacts,
messages_in/out, peak_connections`) that DAU-based pricing and scalability reporting need.

---

## 7. Summary — where the prototype stands vs the design

- **Solid & additive (keep):** transport (socket/channel/presence), the `messages.channel`
  discriminator + schema/enum, `WebMessage` context shape, the `MessageBehaviour` union widening,
  the correct omission of `set_session_status`, GraphQL `channel` fields.
- **Rework to match locked decisions:** presence drop→pause (§5.1); auth Phoenix.Token→JWT +
  refresh/session table (§4); migration made table-rewrite-safe (§1.1); capability gating →
  registry (§5.3).
- **Net-new still to build:** channel-scoped continuation (§5.2); SMS OTP + phone/IP rate limits
  (§4); presence-resume-on-join (§2/§5.1); metrics rollup (§6); `web_channel_sessions` table (§4).
- **Open reconciliation:** `flow_type` enum (built) vs `supported_channels` array (extensibility
  direction) — a real enum migration, decide before building further (§1.2).

Cross-references: data/BigQuery compatibility → `web-channel-schema-and-bigquery.md`; channel
framework + RCS worked example → `web-channel-framework-and-rcs.md`; behaviour → `web-channel-scenarios.md`.
