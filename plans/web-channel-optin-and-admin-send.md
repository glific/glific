# Web channel: separate opt-in, and let staff reply from the inbox

Implements [#5713](https://github.com/glific/glific/issues/5713) plus the staff-side send it
depends on. Three repositories, three stacked branches, all named
`web-channel-optin-admin-send`:

| Repository | Base branch | Why |
|---|---|---|
| `glific` | `web-channel-send-messages` | needs `messages.channel`, the socket and the auth controller |
| `glific-web-channel` | `web-channel-send-messages` | needs the phone-entry step this adds copy to |
| `glific-frontend` | `master` | no earlier web-channel branch exists here, so nothing to stack on |

Everything below is gated on `:web_channel_enabled`. Nothing in this plan changes behaviour for
an organization with the flag off.

## Scope

In: separating web opt-in from WhatsApp opt-in; recording it per channel; staff replying to a
web contact from the inbox; filtering the inbox by channel; showing presence instead of a
session window for web; the consent notice in the widget.

Out: flows replying on web (the flow engine still never sees a web inbound message); HSM to web;
any web opt-out surface; migrating WhatsApp opt-in into the new table; the explicit WhatsApp
opt-in checkbox from US3.

## Tickets

| # | Ticket | Repo | Depends on |
|---|---|---|---|
| T1 | Migration: `contact_histories.channel` and `contact_channel_optins` | glific | — |
| T2 | `ContactChannelOptin` schema and the `Contacts` API that writes it | glific | T1 |
| T3 | Thread the flow context's channel into `capture_history/3` | glific | T1 |
| T4 | Web login records a web opt-in and never a WhatsApp one | glific | T2 |
| T5 | Let the OTP HSM reach a contact who has never opted in | glific | T4 |
| T6 | Expose `channel` on contact history over GraphQL and BigQuery | glific | T1 |
| T7 | `Providers.Web.Message`: deliver a staff reply to the browser | glific | — |
| T8 | Channel-aware sendability: no HSM, no session window, interactive allowed | glific | T7 |
| T9 | Presence: track joined contacts and expose `contact.isWebOnline` | glific | — |
| T10 | Filter conversations by channel | glific | — |
| T11 | Expose `webChannelEnabled` in `organizationServices` | glific | — |
| T12 | Widget: consent notice on the phone-entry step | glific-web-channel | — |
| T13 | Inbox: channel selector above Contacts / Collections / Searches | glific-frontend | T10, T11 |
| T14 | Inbox: presence for web, session timer for WhatsApp | glific-frontend | T9 |
| T15 | Inbox: composer without templates or flows on a web conversation | glific-frontend | T8 |
| T16 | Inbox: web conversation theming | glific-frontend | T13 |

---

## T1 — Migration

`priv/repo/migrations/20260907000000_add_channel_to_contact_histories.exs`

- `contact_histories.channel`: `message_channel_enum`, `default: "whatsapp"`, `null: false`. No
  backfill — every existing row predates the web channel, so the default is the backfill.
- `contact_channel_optins`: `contact_id`, `organization_id`, `channel`, `optin_time`,
  `optin_method`, `optout_time`, `optout_method`, timestamps. Unique index on
  `(contact_id, channel)`; index on `(organization_id, channel)`.

`optout_time` and `optout_method` exist for symmetry and for the later "stop messaging me here"
story. Nothing in this plan writes them.

Regenerate `priv/repo/structure.sql`.

## T2 — Schema and context

`lib/glific/contacts/contact_channel_optin.ex` — standard schema module, mirroring
`Glific.Contacts.ContactHistory`.

`Glific.Contacts`:

```elixir
@spec record_channel_optin(Contact.t(), atom(), Keyword.t()) ::
        {:ok, ContactChannelOptin.t()} | {:error, Ecto.Changeset.t()}
def record_channel_optin(contact, channel, opts \\ [])
```

Idempotent: the first call inserts the row and captures one `:contact_opted_in` history event
with `channel: channel`; later calls return the existing row and capture nothing. Use
`on_conflict: :nothing` with `conflict_target: [:contact_id, :channel]` and decide whether to
capture history from whether a row came back, so two concurrent first logins produce one event
rather than two.

`channel_opted_in?/2` for reads.

## T3 — Channel on flow-generated history

`capture_history/3` gains an optional `channel` in `attrs`, defaulting to the column default.
Every call site that has a `FlowContext` must pass `context.channel`:
`flow_context.ex:283,621,798`, `action.ex:975,1011,1033`, `contact_field.ex:82,110`,
`contact_setting.ex:30,87`, `profiles.ex:203`.

This is the part most likely to be quietly wrong. If a call site is missed the row still looks
valid — it just says WhatsApp. The test for it must build a real `:web` `FlowContext` and assert
the row, never pass a channel literal into `capture_history/3` itself.

`flow_context.ex:621` (`contact_flow_ended_all`) has a contact id but no single context; leave it
at the default and say so in the PR.

## T4 — Web login

`web_channel_auth_controller.ex`:

- `request_otp` still creates the contact if it does not exist, via `Contacts.maybe_create_contact/1`
  — but no `optin_*` fields. Delete `optin_contact/2`.
- `verify_otp`, on success only, calls
  `Contacts.record_channel_optin(contact, :web, method: "web_channel")`.

Nothing here may touch `contacts.optin_time`, `optin_status`, `optin_method`,
`optin_message_id`, `status`, `optout_time`, or call `set_session_status/2`.

Recording at `verify_otp` and not at `request_otp` is the point: anyone can type any number into
a public form, and a consent record that can be manufactured for a number the caller does not
control is worse than none.

## T5 — OTP to a contact who has never opted in

Removing the opt-in makes `Contacts.can_send_message_to?(contact, true)` fail on both
`optin_time == nil` and `bsp_status == :none`, and the OTP HSM is the entire login mechanism.

Add a third clause, narrow and named for exactly what it is:

```elixir
def can_send_message_to?(contact, _is_hsm, %{is_web_channel_otp: true}),
  do: if(contact.status == :blocked, do: {:error, ...}, else: {:ok, nil})
```

The OTP is transactional — the person asked for it by typing their own number — so it is not
covered by the marketing opt-in and must not create one. A blocked contact is still refused.

**This must be verified against a real BSP on staging before the PR merges.** Glific's
`optin_time` is local bookkeeping the BSP does not enforce, so this is very likely to work, but
if Meta or Gupshup rejects it then new-contact web login breaks entirely and the approach has to
change. That is a product decision, not an implementation one: stop and escalate rather than
quietly reinstating the WhatsApp opt-in.

## T6 — Reads

- `contact_types.ex`: `channel` on `:contact_history`, and on `:contacts_history_filter`.
- `Contacts.list_contact_history/1`: filter on channel.
- BigQuery: `bigquery_schema.ex` `contact_history_schema`, the `get_query` select at
  `bigquery_worker.ex:1902`, and the row mapping at `:1114`.

`contact_channel_optins` is **not** synced to BigQuery. Say so in the PR so it reads as a
decision.

## T7 — Delivering a staff reply

`Communications.Message.send_message/2` currently dispatches to
`Communications.provider_handler/1`, which is the organization's WhatsApp BSP. A web message must
never reach it. Branch on `message.channel` before that call and hand `:web` to a new
`Glific.Providers.Web.Message`.

`lib/glific/providers/web/message.ex` implements the same `send_text/2`, `send_image/2`,
`send_audio/2`, `send_video/2`, `send_document/2`, `send_interactive/2` token functions the BSP
modules expose, and for each:

1. marks the message `bsp_status: :sent`, `status: :sent`, `sent_at`,
2. broadcasts `GlificWeb.Endpoint.broadcast("web_channel:#{contact_id}", "new_message", serialized)`
   using `MessageSerializer.serialize/1`,
3. publishes `:sent_message` to the staff subscription the way the BSP path does.

The widget already subscribes to `new_message` on that topic, so nothing changes there.

Delivery is best-effort by design: if the contact has no socket open the message is still
persisted and shows in the inbox, and the widget picks it up from the join history next time.
There is no offline queue and no `:delivered` — say that in the PR rather than leaving a
reviewer to infer it.

Delete the temporary `check_for_hsm_message/2` guard in `messages.ex:333` and its comment.

## T8 — What staff may send on web

In `Messages.create_and_send_message/1`, for `channel: :web`:

- `is_hsm: true` or a `template_id` → `{:error, "HSM templates cannot be sent on the web channel"}`.
  There is no BSP to bill or to approve a template against.
- interactive templates are allowed and go through the existing `check_for_interactive/2`.
- `flow_id` is untouched — staff cannot start a flow on a web contact yet (T15 hides the control;
  this is the server-side half).

`Contacts.can_send_message_to?/2` gates on `bsp_status`, which is a WhatsApp session concept and
is `:none` for a web-only contact. Add a channel-aware entry point so a web send checks only that
the contact is not blocked. Do **not** relax the existing two clauses — they guard every WhatsApp
send in the system.

## T9 — Presence

`GlificWeb.WebChannel.Presence`, a `Phoenix.Presence` tracking `"web_channel:<contact_id>"` on
join, keyed by contact id in a per-organization topic so a lookup does not have to know the
socket topic.

Expose `is_web_online` on the `:contact` object, resolved from Presence. Presence is node-local
state synchronised across a connected cluster by Phoenix's own CRDT; nothing extra is needed, but
it is not durable and must never be persisted or reported on.

The field is resolved per query, so the inbox sees presence as of the last fetch rather than
live. A presence subscription is out of scope; note the limitation in the PR.

## T10 — Filter by channel

`:search_filter` gains `channel: :message_channel_enum`. `Glific.Search.Full.apply_filters/2`
gains `{:channel, channel}, query -> where([m: m], m.channel == ^channel)`.

The grain is right: a conversation appears under a channel when it has a message on that channel.

## T11 — Feature flag to the inbox

`web_channel_enabled` already comes back from `Partners.get_organization_services/0`
(`partners.ex:1505`). Add the field to `:organization_services_result` and to the frontend's
`organizationServices` query.

## T12 — Widget consent notice

On the phone-entry step, visible **before** the number can be submitted:

> By continuing, you agree to receive messages from {organisation} on this chat.

A notice, not a checkbox — consent is implied by continuing. The organisation name comes from the
`ORGANIZATION_NAME` the widget already fetches. No i18n layer exists in the widget yet, so this is
plain copy.

## T13 — Channel selector

A two-option selector — WhatsApp, Web — sits **above** the Contacts / Collections / Searches
tabs, because the channel scopes what those tabs search rather than being a peer of them. Both
options are exactly equal width regardless of label length.

It writes `channel` into the search filter (T10) and is only rendered when
`webChannelEnabled` is on; with the flag off the inbox looks exactly as it does today.

## T14 — Header

For a WhatsApp conversation the session timer stays exactly as it is.

For a web conversation there is no 24-hour window and showing one would be a lie, so it is
replaced by an online / offline indicator driven by `isWebOnline` (T9).

## T15 — Composer

On a web conversation: hide the templates (HSM) control and the Start Flow control; keep
interactive templates, attachments, voice notes and emoji.

## T16 — Theming

The web conversation surface uses the web channel's own colour scheme rather than the WhatsApp
green, so staff can tell at a glance which channel they are replying on. Take the colours from
existing design tokens; do not introduce literals.

---

## Acceptance criteria

- [ ] A brand-new number completing web login has `contacts.optin_time`, `optin_status`,
      `optin_method` and `optin_message_id` unchanged from their defaults.
- [ ] That contact has one `contact_channel_optins` row for `:web` with an `optin_time`.
- [ ] The OTP HSM was delivered to that number against a real BSP on staging.
- [ ] A contact already opted in to WhatsApp who then signs in on the web keeps their WhatsApp
      opt-in byte for byte — same `optin_time`, same `optin_method`, not refreshed.
- [ ] Web login does not change `contacts.status` or clear `optout_time`.
- [ ] A web-only contact appears in no WhatsApp opted-in count: `searches.ex:216`,
      `collection_count.ex:129`, `reports.ex:93`, `stats.ex:377`.
- [ ] Ten logins produce one opt-in row and one history event.
- [ ] `contact_histories.channel` is `web` for events raised by a web flow context and
      `whatsapp` everywhere else.
- [ ] A staff reply to a web contact appears in the open widget within a second and never
      reaches the BSP.
- [ ] A staff reply to a web contact with no socket open is persisted, appears in the inbox, and
      is in the widget's history on next join.
- [ ] Sending an HSM to a web contact is refused with a message naming the reason.
- [ ] An interactive template sends to a web contact and renders in the widget.
- [ ] The channel selector filters the contact list, and both options are the same width.
- [ ] A web conversation header shows online / offline; a WhatsApp one shows the session timer.
- [ ] With `:web_channel_enabled` off, the inbox is unchanged in every respect.

## Reviewer must verify personally

- [ ] **The OTP HSM really was sent to a real, never-opted-in number.** Not mocked. Everything in
      T4 and T5 rests on it; if it was not done the ticket is not done.
- [ ] **No path writes `contacts.optin_*` from a web login**, including indirectly through
      `contact_opted_in/4`, `set_session_status/2`, or a flow action reached from the web.
- [ ] **The channel on flow-generated history rows comes from the flow context**, not the column
      default. Read the call sites — a green test proves nothing if it supplies the value itself.
- [ ] **No web message can reach the BSP.** Read the dispatch branch in
      `Communications.Message.send_message/2` and satisfy yourself there is no path around it.
- [ ] The existing WhatsApp send path is untouched: the two original `can_send_message_to?/2`
      clauses still gate on `bsp_status` exactly as before.
- [ ] The dashboard's opted-in count is numerically identical before and after a web login.
