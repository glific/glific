# #5663 — Web channel sends text, audio, image, file and location

**Branches:** `web-channel-send-messages` in both repos, cut from `web-channel-otp-auth`
(which stacks on `add-channel-columns`). Merge order: #5660 → #5662 → #5663.

**Reference:** the prototype, `origin/web-channel-prototype` in both repos. It is a working
implementation of most of this and should be read before writing anything — but it predates auth,
predates the channel enum, and carries Blocks/flow-gating/theming work that is **not** in this
ticket.

---

## Scope decision: inbound only, and the flow engine is not wired

The ticket says "the user can talk. Being replied to is separate — admin replies and flow replies
are later tickets," and that the inbox story is #5664.

The prototype's `WebMessage.receive_message/2` ends in `publish_and_process/2`, which both publishes
to the staff inbox subscription **and** hands the message to the flow engine via
`Communications.Message.process_message/1`. **We keep the publish and drop the flow handoff.**

The reason is not tidiness. Today the only outbound send path is the BSP. If a web inbound message
reaches the flow engine, the flow replies — over WhatsApp, to a person who typed into a browser and
may not even be WhatsApp-opted-in after #5713. That is worse than no reply. So:

- Persist the message, publish `:received_message` to the existing subscription. That is one line,
  matches every other inbound path, and is what #5664 will consume.
- **Do not call `process_message/1`.**
- Add a guard so an outbound send on `channel: "web"` fails loudly instead of falling through to the
  BSP. It should be impossible for this ticket's code to put a message on WhatsApp.

Flow replies land with the "flows reply on web" ticket, which is where `Providers.Web.Message`,
`Presence` and presence-gated delivery belong. **Do not port `Presence` here** — it exists solely to
decide outbound delivery.

## Also out of scope, deliberately

`blocks` / `blocks_response` and `ChannelCapability` (Phase 2, #5702) · `update_name` (the design
flags it as contradicting a published guarantee — the widget's existing rename stays on whatever it
uses today, do not add a socket handler for it) · `flow_contexts.channel` schema wiring (no flow runs
here) · the `bsp_message_id` → `channel_message_id` rename and its re-scoped unique index (design
§4.2 #12, its own change) · theming (#5661).

---

## Tickets

| # | Title | Repo | Depends on |
|---|---|---|---|
| 1 | Channel test harness and fixtures for an authenticated web socket | glific | — |
| 2 | `Message.channel` schema field and the outbound BSP guard | glific | — |
| 3 | `WebChannelSocket` — connect, verify the JWT, gate on the feature flag | glific | 1, 2 |
| 4 | `RoomChannel` — join, history, and the mid-session token sweep | glific | 3 |
| 5 | `WebMessage` inbound — text, media, location | glific | 2 |
| 6 | Socket handlers for the three inbound types, with a per-contact send limit | glific | 4, 5 |
| 7 | Authenticated, flag-gated media upload with an allowlist and a size cap | glific | 2 |
| 8 | Widget: push `renew_token` on the channel after a REST renewal | glific-web-channel | 4 |
| 9 | Widget: attachment picker, voice note, location share | glific-web-channel | 6, 7 |
| 10 | Widget: upload-then-send, with upload and send failures told apart | glific-web-channel | 9 |
| 11 | End-to-end verification, happy and failure paths | both | all |

---

## 1 — Channel test harness and fixtures

`test/support/channel_case.ex` already exists. What is missing is a way to get an **authenticated**
web socket in a test without repeating the JWT dance in every file.

Add to `test/support/fixtures.ex` (or a `test/support/web_channel_fixtures.ex` if that file is
already crowded):

- `web_channel_socket_fixture(contact, opts \\ [])` — mints a real token via
  `GlificWeb.WebChannel.Token.sign_contact_token/1` and returns a connected
  `GlificWeb.WebChannelSocket`. `opts[:token]` overrides the token so forgery cases can be tested
  through the same door.
- `join_web_channel(socket, contact)` — joins `web_channel:<id>` and returns `{:ok, reply, socket}`.

**Mint real tokens. Do not stub `Token.verify_contact_token/1`.** The whole point of the socket is
that it rejects bad credentials, and a stubbed verifier tests nothing. `token_test.exs` already
covers the forgeries; these fixtures make it cheap to prove the *socket* honours them.

Every web channel test must carry the FunWithFlags setup block that
`web_channel_auth_controller_test.exs` uses — disable the flag, `FunWithFlags.Store.Cache.flush()`,
re-`fill_cache`. The flag cache is not sandbox-scoped and without it roughly one run in five fails.
Put it in a shared setup helper rather than copying it a fourth time.

## 2 — `Message.channel` and the outbound BSP guard

`add-channel-columns` added the column and the `Glific.Enums.MessageChannel` Ecto enum but
deliberately left the schemas undeclared, so the field is invisible to the app today. Its commit
message says "schema fields, changeset wiring and reply-channel propagation land with the feature
tickets" — this is that ticket for `messages`.

- `lib/glific/messages/message.ex`: `field(:channel, MessageChannel, default: :whatsapp)`, add
  `:channel` to `@optional_fields`, add it to `@type t()`.
- Match the DB default exactly. Every existing create path will now write `whatsapp` explicitly
  where it previously fell through to the column default; that must be a no-op.

**The guard.** In `Glific.Messages`, before the generic outbound clause, reject a send on a
non-WhatsApp channel:

```elixir
defp check_for_hsm_message(%{channel: channel}, _contact) when channel in [:web, "web"],
  do: {:error, "web channel sends are not implemented yet"}
```

This is temporary and is replaced by the real web provider in the flow-reply ticket. It exists so
that nothing in this ticket can silently deliver a web message over WhatsApp. Say so in a one-line
comment naming the ticket that removes it.

## 3 — `WebChannelSocket`

`lib/glific_web/channels/web_channel_socket.ex`, mounted in `endpoint.ex`:

```elixir
socket("/web_socket", GlificWeb.WebChannelSocket, websocket: true, longpoll: false)
```

Start from the prototype's version, which is close to right, and change three things.

**Assign the token's expiry and session id.** `connect/3` must put `token_exp` and `session_id`
(the `jti`) into socket assigns — ticket 4's sweep has no other way to know when the credential
dies. `Token.verify_contact_token/1` returns `session_started_at` too; carry it, the absolute
session bound is enforced inside `verify_contact_token/1` but the channel may want to report it.

**Gate on the feature flag.** Every other new surface is flag-gated and the socket is the largest
one. Read it **live**:

```elixir
organization_id |> Partners.organization() |> then(&Flags.get_flag_enabled(:web_channel_enabled, &1))
```

Not `organization.web_channel_enabled` — that virtual field is only stamped during
`Partners.fill_cache/1`, so enabling the flag does not update it and the socket would keep refusing
connections. That exact bug already shipped once in #5662.

Factor the helper out of `web_channel_auth_controller.ex` into `GlificWeb.WebChannel.Flag` with
`enabled?/1`, and repoint the auth controller at it. Three copies of this is how the next one drifts.

**Process context.** `Repo.put_process_state(org_id)` before any permission-checked context call, as
the prototype does — the connect process is fresh. Keep the `rescue Ecto.NoResultsError -> :error`.

`id/1` stays `"web_socket:#{contact.id}"`, which is what makes
`Endpoint.disconnect(...)`-style eviction possible later.

**Return `:error` for every failure, undifferentiated.** No logging of the token, no distinguishing
expired from forged in the response.

## 4 — `RoomChannel`: join, history, and the mid-session sweep

`lib/glific_web/channels/web_channel/room_channel.ex`. Port the prototype's `join/3`, `load_more`
and history serialization; drop `update_name`, `handle_out`, `maybe_push_display_name`, `Presence`
and the blocks handler.

- Topic guard: `contact_id == to_string(socket.assigns.current_contact.id)`, else
  `{:error, %{reason: "unauthorized"}}`. This is the only place topic ownership is checked.
- `Repo.put_process_state(socket.assigns.organization_id)` in `join/3` — the channel is a different
  process from connect.
- History: port `Messages.list_conversation_messages/3` and `MessageSerializer` verbatim. Newest
  last. `@page_size 100`.

**The sweep** — this is the part the user called out and the part the prototype has none of.
`api-auth-design.md` §2.4:

```
exp − @warning_window  →  push "token_expiring"   (once)
exp + @grace, no renew →  push "session_expired"  → stop the channel
```

- `Process.send_after(self(), :sweep_token, @sweep_interval_ms)` from `join/3`, rescheduled from
  `handle_info(:sweep_token, socket)`.
- `@sweep_interval_ms 60_000`. The design warns that the sweep interval, not the TTL, is the real
  granularity: a token expiring at T dies at T + interval. 60s against a 3600s TTL is fine, and the
  widget renews ten minutes early anyway, so the sweep is a backstop rather than the mechanism.
- `@warning_window_seconds 600` — matches `WEB_CHANNEL_TOKEN_REFRESH_THRESHOLD_SECONDS` in the
  widget so the two agree about when renewal is due.
- `@grace_seconds 60` — the same 60s `Token` already allows as clock leeway. Killing at exactly
  `exp` while the verifier still accepts a 60s-old token would be two components disagreeing.
- Push `token_expiring` **once** per token; assign a flag and clear it on renewal, or the client
  gets one push a minute for ten minutes.

**`handle_in("renew_token", %{"token" => token})`** — a channel handler, not a socket one:
`Phoenix.Socket` has no user hook and a channel's `assign` does not reach the socket process.

Re-verify in full through `Token.verify_contact_token/1`, then **assert the new token resolves to
the same `contact_id` and the same `org_id` already on the socket**. `join/3` authorizes the topic
exactly once and never re-checks it, so a renewal permitted to swap `current_contact` is an
identity-switch primitive that bypasses the join guard entirely. On mismatch reply
`{:error, %{reason: "invalid_token"}}` and change nothing. **Never swap `current_contact`** — the
only assigns a renewal may touch are `token_exp` and the warning flag.

Keep the `handle_info(:received_message_to_process, socket)` no-op clause: the test-env consumer
mock notifies the calling process and would otherwise crash the channel.

## 5 — `WebMessage` inbound

`lib/glific/communications/web_message.ex`. Port from the prototype, keeping `receive_message/2`,
`receive_text/1`, `receive_media/1`, `receive_location/1`, `create_message_metadata/2` and
`publish_data/3`. Drop `send_message/2`, everything blocks-related, and the `@type_to_token` map.

Changes from the prototype:

- `publish_and_process/2` becomes publish-only. Name it `publish/2`, so nobody re-adds the handoff
  by pattern-matching on a familiar name.
- `channel: :web` as an atom now that the Ecto enum is declared, not the string `"web"`.
- Keep the transaction in `receive_media/1` — media row and message in one transaction, so a failed
  message insert cannot orphan a `messages_media` row.
- Keep `receive_location/1`'s ordering: the message must exist before the `locations` row, because
  `Location.changeset` requires `message_id`.
- **Do not accept a client-supplied `bsp_message_id`.** Leave it nil. The unique index is currently
  `(bsp_message_id, organization_id)`; a client-chosen value under that index lets one contact
  suppress another's message and doubles as an existence oracle. The design's re-scoped index is a
  separate change.
- The prototype never calls `Contacts.set_session_status/2` on this path and that is correct — it is
  a WhatsApp 24-hour-window concept. Preserve the omission and say why in a comment, or someone will
  "fix" it.

## 6 — Socket handlers for the three inbound types

In `RoomChannel`:

- `handle_in("new_message", %{"body" => body}, socket)` — reject a blank or oversized body before
  persisting. Cap the body at the same length `messages.body` accepts.
- `handle_in("new_media_message", %{"type" => type, "url" => url} = params, socket)` guarded on
  `type in ~w(image audio video document)`, with a fallback clause replying
  `{:error, %{reason: "unsupported media type"}}`. The payload carries a URL, never bytes.
- `handle_in("new_location_message", %{"latitude" => lat, "longitude" => lng}, socket)` — validate
  both are numbers in range (−90..90, −180..180) before persisting; the prototype does not, and a
  string here reaches the database.

**The url must be one we issued.** A raw client can push any URL into `new_media_message` and it
becomes a message the staff inbox will render and an admin will click. Verify the host matches the
org's configured GCS bucket host or the local-media base URL before accepting it. This is not in the
ticket text; it is the direct consequence of moving upload behind auth while leaving the socket
willing to reference anything.

**Rate limit inbound socket messages per contact.** `api-auth-design.md` §10.1 ranks "no rate
limiting at all on the socket" as HIGH, and this ticket is what opens the write surface. Use
`ExRated.check_rate/3`, the existing pattern, keyed `web_channel_message:<contact_id>`, configured in
`config/config.exs` as `:web_channel_message_rate_limit` with a generous test override — the same
shape as `:web_channel_otp_rate_limit`. Reply `{:error, %{reason: "rate_limited"}}`. *Flagged as an
addition beyond the ticket text; cut it if the team would rather it were its own ticket.*

Every handler replies `:ok` or `{:error, %{reason: ...}}` — the widget needs to tell a send failure
from an upload failure, so the reason must be machine-readable, not prose.

## 7 — Media upload, authenticated and flag-gated

The prototype's `web_channel_media_controller.ex` and `Providers.Web.Upload` port over nearly whole.
What changes is everything around the door.

**Move it behind a plug.** The prototype authenticates inside the action, which works but leaves the
route on the open `:api` pipeline where the next action added to it inherits nothing. Add
`GlificWeb.Plugs.WebChannelAuth`:

- reads `authorization: Bearer <token>`, verifies via `Token.verify_contact_token/1`
- on success assigns `:web_channel_contact_id` and `:web_channel_organization_id` and calls
  `Repo.put_process_state/1`
- on failure `401` and `halt`
- then checks `GlificWeb.WebChannel.Flag.enabled?/1` and `404`s if off, matching the auth
  controller's behaviour for a disabled org

Add a `:web_channel_api` pipeline using it, and put the upload route in a scope through that
pipeline. Delete the "should be behind a protected scope" comment along with the condition it
described.

**`org_id` comes from the verified token, never the request body.** The prototype gets this right;
keep it.

**Allowlist and cap.** Reject before uploading anything:

- content type against an explicit allowlist per media type. Reuse the same families
  `Messages.do_validate_headers/3` accepts, so a file that uploads here cannot fail validation later
  — including its exclusion of `audio/ogg`.
- size against `Glific.Messages`'s existing `@size_limit` (image 5 MB, video 16 MB, audio 16 MB,
  document 100 MB, in KB). Expose it as a public `Messages.media_size_limit/1` rather than
  duplicating the numbers; one source of truth or they diverge.
- Check the size from `File.stat!/1` on the uploaded temp file, not from a client-supplied header.

**Typed errors.** The widget has to render these, so return a code as well as a message:
`%{error: %{status: 413, code: "file_too_large", message: "..."}}`,
`code: "unsupported_type"` (415), `code: "upload_failed"` (422), `code: "unauthorized"` (401).
Prose alone forces the widget to string-match.

Note the endpoint's `Plug.Parsers` multipart length is a global cap that applies before the action
runs; if it is lower than 100 MB a large document dies as a parser error rather than a typed 413.
Check it and either raise it for this scope or lower the document cap to match. Do not leave the two
disagreeing.

## 8 — Widget: renew the socket's view of the token

`src/hooks/useSessionRefresh.ts` renews over REST and writes the new token to storage. The socket
does not notice: its `token_exp` was fixed at connect, so the channel's sweep will push
`session_expired` and stop the channel while the client is holding a perfectly good token.

- After a successful REST renewal, push `renew_token` on the live channel with the new token.
- Handle the server's `token_expiring` push by triggering a renewal immediately rather than waiting
  for the next 30s tick.
- Handle `session_expired` by clearing the session and routing to `/login`.

`webChannelSocket.ts` already passes `params` as a function, so reconnects pick up the current token
from storage — that part is done and should not be re-litigated.

## 9 — Widget: the three new composers

`src/routes/Chat.tsx` and new components under `src/components/chat/`.

- **Attachment picker** — `<input type="file">` with an `accept` matching the server allowlist,
  mapping the chosen file to `image | video | document` by MIME type. Optional caption.
- **Voice note** — `MediaRecorder`. Chrome yields `audio/webm;codecs=opus`, Safari `audio/mp4`;
  feature-detect with `MediaRecorder.isTypeSupported` and pick a supported type rather than
  hardcoding one. Handle a denied microphone permission as a visible, recoverable state.
- **Location** — `navigator.geolocation.getCurrentPosition`, with denied permission and timeout
  both surfaced. Send `{latitude, longitude}`; the body is derived server-side.

Every one of these needs a permission-denied and a not-supported path in the UI, not a silent
no-op.

## 10 — Widget: upload then send, with the two failures told apart

The order is fixed: `POST /api/v1/web_channel/upload` with `Authorization: Bearer <token>`, then
`channel.push('new_media_message', {type, url, content_type, caption})`. **No bytes over the
socket.**

The ticket's acceptance criterion is that a failed upload can be retried *without re-composing the
message*. So the composer must hold the selected file and caption in state until the send is
acknowledged, and clear only then. Three distinct states:

- upload failed → the file is still held, retry re-uploads
- upload succeeded, socket push failed → the URL is held, retry re-pushes without re-uploading
- both succeeded → clear

Render the server's error `code`, not its `message`, so the copy is the widget's and one of them can
be translated later.

## 11 — End-to-end verification

Two suites green is not the finish line; both sides mock the other and can agree with each other
while disagreeing with reality. Run it.

Backend on its own port under `MIX_ENV=test` — the test env sets `Tesla.Mock` and manual Oban, so a
live run cannot make a real BSP call or message a real person, and it keeps `_build/dev` out of the
way of any long-running dev server on 4000/4001.

**Happy:** log in → socket connects → send text → row in `messages` with `channel: :web`,
`flow: :inbound`, correct `sender_id`/`receiver_id`/`contact_id` → upload each of image, audio, video
and document, send each, confirm the `messages_media` row and the message → send a location, confirm
the `locations` row.

**Failure, each one actually exercised:**

- upload with no `Authorization` header → 401, and no file reaches storage
- upload with another org's token → 401/404, and nothing is written under this org
- oversized file → 413 with the typed code, and the widget renders it
- disallowed content type → 415
- `new_media_message` with a URL we did not issue → rejected
- `new_location_message` with a string latitude → rejected, no row
- socket connect with an expired token → refused
- socket connect with the feature flag off → refused
- **token expiry mid-session** → wind `@warning_window` or mint a short-lived token, confirm
  `token_expiring` arrives, confirm `renew_token` extends the session, confirm that *not* renewing
  produces `session_expired` and a stopped channel
- **`renew_token` carrying another contact's valid token** → rejected, and `current_contact` is
  unchanged. Confirm by mutation: remove the identity assertion and this must start passing a
  cross-contact swap.

---

## Review checklist — verify these personally

- [ ] **Attempt an unauthenticated upload yourself.** Ticket #5663 asks for this by name. An open
      write surface should not meet real users.
- [ ] **No path can send a WhatsApp message as a result of a web inbound message.** Read the
      `process_message/1` call sites, not just the tests.
- [ ] **`renew_token` cannot change which contact the socket speaks for.** Mutate the assertion away
      and confirm a test fails.
- [ ] The feature flag is read live, not off the cached org struct — the #5662 bug, in a new place.
- [ ] The media URL accepted over the socket is one the server issued.
- [ ] The multipart parser limit and the document size cap agree.
- [ ] A voice note recorded on a real iPhone, in Safari, actually plays back. Browser audio capture
      behaves differently there than anywhere else and no test in either repo will catch it.
