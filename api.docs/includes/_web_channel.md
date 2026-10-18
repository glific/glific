# Web Channel Login

The web channel lets people chat with your organization's Glific from your own website or app,
logged in with **your** login system. Your backend signs a short-lived token (a JWT) for each
logged-in user. The user's browser opens a WebSocket to your organization's Glific host with that
token, joins the conversation and sends and receives messages. Glific never sees your users'
passwords.

This guide is for the developers who build that integration. It covers setup, the token, the
socket protocol, every event and error, and how Glific maps your users to contacts.

## Web channel integration overview

The moving parts:

1. **Your backend** holds a JWT signature secret and signs a token for the logged-in user.
2. **Your web app** asks your backend for that token.
3. **Your web app** opens a WebSocket to your organization's Glific host with the token.
4. **Glific** checks the token, finds or creates the contact for the user, and accepts the socket.
5. **Your web app** joins the topic `web_channel:conversation` and gets the recent messages.
6. Both sides exchange events over the socket until the user leaves or the token runs out. Before
   it runs out, your web app gets a fresh token from your backend and hands it to Glific.

```text
 Your backend           Your web app (browser)                Glific (api.<org>.glific.com)
      |                          |                                          |
      |<-- 1. get token ---------|                                          |
      |--- 2. signed JWT ------->|                                          |
      |                          |-- 3. WebSocket upgrade                   |
      |                          |   /web_socket/websocket?token=..&vsn=2.0.0
      |                          |                                          |-- verify token,
      |                          |                                          |   find or create contact
      |                          |<----------------- 101 Switching Protocols|
      |                          |-- 4. phx_join "web_channel:conversation"->|
      |                          |<-------- reply {contact_id, messages} ---|
      |                          |-- new_message {body} ------------------->|-- flows, staff inbox
      |                          |<-------------------- new_message {..} ---|   (replies)
      |                          |                ...                       |
      |                          |<------------------ token_expiring {} ----|  (10 min before exp)
      |<-- 5. get fresh token ---|                                          |
      |--- fresh JWT ----------->|                                          |
      |                          |-- renew_token {token} ------------------>|
      |                          |<-------------------------------- ok -----|
```

## Before you start

### Turn on the web channel

Two switches must both be on before any socket connects:

1. Glific enables the web channel feature for your organization.
2. Your organization's admin turns on the **Web Channel** settings in Glific (Settings page) and
   saves them, so the credential is active.

If either is off, every connection is refused (HTTP 403). If your admin switches the Web Channel
settings off while users are connected, every open conversation receives
<a href="#web_channel_disabled">web_channel_disabled</a> and is closed.

### JWT signature secrets

On the **Web Channel** settings page, the admin adds the secrets your backend signs tokens with:

* At most **two** secrets. Glific reads only the first two in the list.
* Each has a **name** of your choice (for example `2026-10`). The name is only a label; it is not
  sent in the token and does not affect verification.
* Each secret must be at least **32 characters**. Glific silently ignores a shorter secret, so
  tokens signed with it are refused.
* A token signed with **any** of the secrets is accepted. Neither is "current" or "previous".
* The secret is used as-is, as the HMAC key (the UTF-8 bytes of the string). It is not base64
  decoded.

If no valid secret is set, every token you sign is refused. People can still sign in with phone
and one-time code if your organization uses Glific's own web chat.

Generate a secret with a cryptographically secure generator, for example:

```shell
openssl rand -base64 48
```

### Rotating a JWT signature secret

1. Add the new secret, with a new name, next to the old one.
2. Switch your backend to sign with the new secret.
3. Wait until tokens signed with the old secret have expired (at most your token lifetime).
4. Remove the old secret.

Removing a secret stops new connections and renewals with tokens it signed. Sockets that are
already connected stay open until their current token expires.

## Your Glific host

Glific decides which organization a connection belongs to from the **host name** the socket
connects to, never from the token. Use your organization's Glific API host: `api.` followed by the
host of your Glific dashboard.

Glific dashboard | Socket URL
---------------- | ----------
`https://example.glific.com` | `wss://api.example.glific.com/web_socket/websocket`

The host without `api.` (`example.glific.com`) resolves to the same organization. If your
organization uses a self-hosted Glific, use that deployment's API host.

A token is checked only against the secrets of the organization the host belongs to. A token
signed with another organization's secret, or sent to another organization's host, is refused.

## The login token (JWT)

The token is a standard JWT (RFC 7519) in compact form, signed with **HS256** using one of your
JWT signature secrets.

### Token header

```json
{ "alg": "HS256", "typ": "JWT" }
```

* `alg` must be `HS256`. Glific verifies with HS256 only and never trusts the token's own `alg`:
  `none`, `HS384`, `HS512`, `RS256` and every other value are refused.
* `typ` and `kid` are not checked. There is no key id; any of your secrets may verify the token.

### Token claims

Claim | Required | Type | Format and limits | Meaning | If invalid
----- | -------- | ---- | ----------------- | ------- | ----------
`sub` | Yes | string | 1 to 255 characters. Only letters `a-z` `A-Z`, digits `0-9`, `_`, `@` and `.`. Case-insensitive. | Your permanent, unique username for the user. See <a href="#the-sub-claim">The sub claim</a>. | Connection refused (403).
`channel` | Yes | string | Exactly `"web"`. | Marks the token as a web channel login token. | Connection refused (403).
`iat` | Yes | integer | Seconds since the Unix epoch. At most 60 seconds in the future. | When you issued the token. | Connection refused (403).
`exp` | Yes | integer | Seconds since the Unix epoch. `exp - iat` at most 86400 (24 hours). | When the token expires. Accepted until 60 seconds after `exp`. | Connection refused (403).
`name` | No | string | At most 255 characters. | The contact's name, used only when Glific creates a new contact. Defaults to the username. | Connection refused (403) if it is not a string or is longer than 255 characters.
`phone` | No | string | The user's phone number with country code. See <a href="#the-phone-claim">The phone claim</a>. | Links the user to their existing WhatsApp contact, or is stored on a new contact. | Ignored, as if absent. Never refuses the token.

`iat` and `exp` must be JSON integers: `1760000000` is accepted, `1760000000.5` and
`"1760000000"` are refused.

#### The sub claim

* Glific stores the username in lowercase, so `Ravi_12` and `ravi_12` are the same user.
* Allowed characters are letters, digits, `_`, `@` and `.`. Anything else (a space, `-`, `+`, `/`,
  non-Latin letters) is refused. **A UUID contains `-` and is refused.** Remove the hyphens, or
  use another id.
* The same `sub` always signs in as the same contact. Never reuse a `sub` for a different person,
  and make sure every system you sign tokens from uses the same `sub` for the same person.
* Do not use a phone number as the `sub`. See
  <a href="#security-and-your-responsibilities">Security and your responsibilities</a>.

#### The phone claim

* Send the number as a JSON **string**. A number value (`919876543210` without quotes) is ignored.
* Glific removes every character other than digits and `+`, adds a leading `+` if missing, and
  checks it is a valid number for its country. `"+91 98765 43210"`, `"919876543210"` and
  `"+91-98765-43210"` all become `919876543210`.
* The country code is required. A national number such as `"09876543210"` is not valid and is
  ignored.
* An invalid phone is ignored; the token still works, and the user gets a contact without a phone.
* The phone is used only the first time a `sub` connects. After that, `phone` and `name` in later
  tokens are ignored. See <a href="#web-channel-users-and-contacts">Web channel users and
  contacts</a> for when a phone links to an existing contact.
* Only send a phone you have verified belongs to the user.

#### Other claims

Glific ignores every claim not listed above. `aud`, `iss`, `nbf` and `jti` are not checked.
`contact_id` is no longer supported: it is ignored like any other unknown claim, so it cannot
choose which contact a token signs in as.

### Signing a token

Sign tokens on your backend only. Keep lifetimes short (the examples use one hour) and renew
them while the user is connected.

```javascript
// Node.js, using the jsonwebtoken package (npm install jsonwebtoken)
const jwt = require("jsonwebtoken");

function glificToken(user) {
  const claims = { sub: user.username, channel: "web" }; // e.g. "ravi_12": letters, digits, _ @ . only
  if (user.displayName) claims.name = user.displayName;    // optional
  if (user.verifiedPhone) claims.phone = user.verifiedPhone; // optional, a string such as "919876543210"

  return jwt.sign(
    claims,
    process.env.GLIFIC_JWT_SIGNATURE_SECRET, // at least 32 characters
    { algorithm: "HS256", expiresIn: "1h" }  // adds integer iat and exp
  );
}
```

```python
# Python, using PyJWT (pip install pyjwt)
import os
import time

import jwt


def glific_token(username, name=None, phone=None):
    now = int(time.time())
    claims = {"sub": username, "channel": "web", "iat": now, "exp": now + 3600}
    if name:
        claims["name"] = name
    if phone:
        claims["phone"] = phone  # a string such as "919876543210"
    return jwt.encode(claims, os.environ["GLIFIC_JWT_SIGNATURE_SECRET"], algorithm="HS256")
```

A decoded token:

```json
{
  "sub": "ravi_12",
  "channel": "web",
  "name": "Ravi",
  "phone": "919876543210",
  "iat": 1760000000,
  "exp": 1760003600
}
```

Hand the token to your web app over your own authenticated API, for example
`GET /api/glific-token` behind your login.

## Connecting to the web channel socket

### Socket URL

```text
wss://api.example.glific.com/web_socket/websocket?token=<jwt>&vsn=2.0.0
```

Part | Value
---- | -----
Path | `/web_socket/websocket`. WebSocket only; there is no long-polling fallback.
`token` | The JWT, as a query parameter. Without it the connection is refused.
`vsn` | `2.0.0`, the Phoenix Channels protocol version this guide describes. phoenix.js sends it for you.

The connection is a [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) socket. Use the
official JavaScript client, [phoenix](https://www.npmjs.com/package/phoenix), unless you have a
reason not to.

### Message framing

With `vsn=2.0.0`, every WebSocket text frame is a JSON array:

```text
[join_ref, ref, topic, event, payload]
```

Field | Type | Meaning
----- | ---- | -------
`join_ref` | string or null | The `ref` of the join message of this channel. `null` for heartbeats.
`ref` | string or null | A unique id you choose per message; Glific's reply carries the same `ref`. `null` in pushes from Glific.
`topic` | string | `web_channel:conversation` (or `phoenix` for heartbeats).
`event` | string | The event name, such as `phx_join`, `new_message`, `phx_reply`.
`payload` | object | The event's data.

Glific answers each message you send with a `phx_reply` whose payload is
`{"status": "ok" | "error", "response": {...}}`:

```json
["1", "1", "web_channel:conversation", "phx_join", {}]
["1", "1", "web_channel:conversation", "phx_reply", {"status": "ok", "response": {"contact_id": 15, "messages": []}}]

["1", "2", "web_channel:conversation", "new_message", {"body": "Hello"}]
["1", "2", "web_channel:conversation", "phx_reply", {"status": "ok", "response": {}}]

["1", "3", "web_channel:conversation", "new_message", {"body": "   "}]
["1", "3", "web_channel:conversation", "phx_reply", {"status": "error", "response": {"reason": "blank_body"}}]

["1", null, "web_channel:conversation", "token_expiring", {}]

[null, "4", "phoenix", "heartbeat", {}]
[null, "4", "phoenix", "phx_reply", {"status": "ok", "response": {}}]
```

### Minimal phoenix.js client

```javascript
// Browser, using the phoenix package (npm install phoenix)
import { Socket } from "phoenix";

const GLIFIC_SOCKET = "wss://api.example.glific.com/web_socket"; // phoenix adds /websocket

let currentToken = await fetchTokenFromYourBackend();

const socket = new Socket(GLIFIC_SOCKET, {
  // A function, so every reconnect sends the latest token, not the first one.
  params: () => ({ token: currentToken }),
});
socket.connect();

const channel = socket.channel("web_channel:conversation", {});

channel.on("new_message", (message) => render(message));

channel.on("token_expiring", async () => {
  currentToken = await fetchTokenFromYourBackend();
  channel.push("renew_token", { token: currentToken })
    .receive("error", ({ reason }) => console.warn("renew failed", reason));
});

channel.on("session_expired", () => { socket.disconnect(); showSignedOut(); });
channel.on("web_channel_disabled", () => { socket.disconnect(); showUnavailable(); });

channel.join()
  .receive("ok", ({ contact_id, messages }) => {
    messages.forEach(render); // oldest first
  })
  .receive("error", ({ reason }) => console.warn("join refused", reason));

function send(body) {
  channel.push("new_message", { body })
    .receive("ok", () => markSent())
    .receive("error", ({ reason }) => showError(reason))
    .receive("timeout", () => showError("timeout"));
}
```

### Refused connections

Glific refuses a connection during the WebSocket upgrade, before any channel is joined:

HTTP status | Meaning
----------- | -------
`403` | Refused. The reason is never given: invalid, expired or wrongly signed token, missing token, unknown host, web channel off, no valid secret, a `sub` with characters that are not allowed, too many connection attempts from your address, or a browser origin Glific does not allow.
`503` | The Glific server is busy (too many connection attempts across all users). Retry later with backoff.

Browsers do not show the HTTP status of a failed WebSocket upgrade to JavaScript; phoenix.js only
reports an error and retries. Use the
<a href="#check-a-token-before-you-connect">token check</a> and
<a href="#smoke-test-the-connection">smoke test</a> below to find out why a connection fails.

**Browser origin.** Browsers send an `Origin` header with the upgrade request. Glific refuses
(403) an origin that is not on its server's allowed list. That list is set per Glific deployment,
not per organization. Before you go live, confirm with Glific that the origin of your web app is
allowed. Clients that send no `Origin` header (most server-side clients) are not checked.

### Connection rate limits

Glific counts every connection attempt, successful or not, before it checks the token.

Limit | Default | When exceeded
----- | ------- | -------------
Connection attempts per client IP address | 120 per minute | `403`
Connection attempts across all users of a Glific server | 1000 per minute | `503`

Glific takes the client IP address from the `X-Forwarded-For` header, or the peer address if there
is none. If your users connect through a proxy you run, they share your proxy's address and its
budget. These are defaults; a Glific deployment can change them.

### Heartbeats and reconnecting

* Send a heartbeat (`[null, ref, "phoenix", "heartbeat", {}]`) at least every 30 seconds.
  phoenix.js does this for you. Glific closes a socket that sends nothing for 60 seconds.
* phoenix.js reconnects and rejoins automatically after a network drop. Each reconnect runs the
  token check again, so always pass `params` as a function that returns your latest token.
* A reconnect counts against the connection rate limit. If you write your own client, back off
  (for example 1, 2, 5, 10 seconds) and stop retrying after a few failures; get a fresh token from
  your backend before trying again.
* After a rejoin, if you renewed the token since the socket connected, push `renew_token` again
  with your latest token. A rejoin without a reconnect keeps the expiry of the token the socket
  connected with.

## Joining the conversation

Join the topic `web_channel:conversation` with an empty payload. The topic always means the
conversation of the user the token signed in. There is no topic per contact.

```json
["1", "1", "web_channel:conversation", "phx_join", {}]
```

### Join reply

```json
{
  "status": "ok",
  "response": {
    "contact_id": 15,
    "messages": [
      {
        "id": 901,
        "body": "Hi",
        "type": "text",
        "flow": "inbound",
        "inserted_at": "2026-10-18T09:15:02.123456Z",
        "interactive_content": {},
        "media": null
      },
      {
        "id": 902,
        "body": "Welcome to Example Foundation! Reply 1 for courses.",
        "type": "text",
        "flow": "outbound",
        "inserted_at": "2026-10-18T09:15:03.456789Z",
        "interactive_content": {},
        "media": null
      }
    ]
  }
}
```

Field | Type | Meaning
----- | ---- | -------
`contact_id` | integer | The Glific id of the user's contact. Staff see this contact in the inbox.
`messages` | array of <a href="#the-message-object">messages</a> | The latest 100 web channel messages of the conversation, oldest first. Use <a href="#load-older-messages-load_more">load_more</a> for older ones.

The history holds only messages sent and received on the web channel. If the user is linked to a
WhatsApp contact, their WhatsApp messages are not included.

Join error | Cause
---------- | -----
`{"reason": "unauthorized"}` | The topic is not `web_channel:conversation` (for example `web_channel:15`), or the token the socket connected with expired more than 60 seconds ago.
`{"reason": "unmatched topic"}` | The topic does not start with `web_channel:`.

### The message object

The same shape is used in the join reply, in `load_more` replies and in live `new_message` pushes.

Field | Type | Nullable | Meaning
----- | ---- | -------- | -------
`id` | integer | No | Glific's message id. Use it to de-duplicate.
`body` | string | No | The text. For a media message, its caption. `""` when there is none.
`type` | string | Yes | One of `text`, `image`, `audio`, `video`, `document`, `sticker`, `location`, `quick_reply`, `list`, `location_request_message`, `poll`, `contact`, `hsm`, `whatsapp_form_response`.
`flow` | string | Yes | `inbound` for a message the user sent, `outbound` for a message from your organization.
`inserted_at` | string | No | When Glific stored the message, ISO 8601 in UTC with microseconds, e.g. `2026-10-18T09:15:02.123456Z`.
`interactive_content` | object | Yes | For `quick_reply` and `list` messages, the interactive message as Glific stores it (buttons or list sections). `{}` for other messages.
`media` | object | Yes | `{"url": "<string>"}` for a message with a file; `null` otherwise.

An example `quick_reply` message:

```json
{
  "id": 950,
  "body": "",
  "type": "quick_reply",
  "flow": "outbound",
  "inserted_at": "2026-10-18T09:20:00.000000Z",
  "interactive_content": {
    "type": "quick_reply",
    "content": { "type": "text", "text": "Which course do you want?" },
    "options": [
      { "type": "text", "title": "Maths" },
      { "type": "text", "title": "Science" }
    ]
  },
  "media": null
}
```

To answer a button or list item, send its title as a
<a href="#send-a-text-message-new_message">new_message</a>.

## Events you send to Glific

Every event below is pushed on the joined `web_channel:conversation` channel. Glific replies to
each with `ok` or `error`. Error replies have the payload `{"reason": "<reason>"}`.

`new_message`, `new_media_message`, `new_location_message` and `load_more` share one rate limit:
**20 events per 10 seconds per user** (counted across all of the user's open sockets). Past it,
Glific replies `rate_limited` and does nothing.

### Send a text message: new_message

```json
["1", "5", "web_channel:conversation", "new_message", {"body": "I want to learn Maths"}]
```

Field | Required | Type | Limits
----- | -------- | ---- | ------
`body` | Yes | string | Leading and trailing whitespace is removed. 1 to 4096 characters after that.

Reply `ok` with an empty payload. Glific stores the message, shows it in the staff inbox and passes
it to your organization's flows. Glific does not echo your own message back as a `new_message`
push; show it in your UI when the reply is `ok`.

Error reason | Cause
------------ | -----
`blank_body` | `body` is missing, not a string, or only whitespace.
`body_too_long` | `body` is longer than 4096 characters after trimming.
`rate_limited` | More than 20 events in 10 seconds.
`contact_blocked` | Your organization has blocked this contact (or deleted it).
`send_failed` | Glific could not store the message. Retry once; if it persists, contact Glific.

### Load older messages: load_more

```json
["1", "6", "web_channel:conversation", "load_more", {"offset": 100}]
```

Field | Required | Type | Limits
----- | -------- | ---- | ------
`offset` | Yes | integer | 0 or more. The number of messages you already have.

Reply `ok` with `{"messages": [...]}`: up to 100 older <a href="#the-message-object">messages</a>,
oldest first. An empty list means there are no more. Messages received since you joined shift
the offset, so de-duplicate by `id`.

Error reason | Cause
------------ | -----
`invalid_offset` | `offset` is missing, not an integer, or negative.
`rate_limited` | More than 20 events in 10 seconds.

### Share a location: new_location_message

```json
["1", "7", "web_channel:conversation", "new_location_message", {"latitude": 12.9716, "longitude": 77.5946}]
```

Field | Required | Type | Limits
----- | -------- | ---- | ------
`latitude` | Yes | number | -90 to 90.
`longitude` | Yes | number | -180 to 180.

Reply `ok` with an empty payload. Glific stores a `location` message whose body is a Google Maps
link to the coordinates.

Error reason | Cause
------------ | -----
`invalid_location` | A coordinate is missing, not a JSON number (a string such as `"12.9"` is refused), or out of range.
`rate_limited` | More than 20 events in 10 seconds.
`contact_blocked` | Your organization has blocked this contact (or deleted it).
`send_failed` | Glific could not store the message.

### Send a file: new_media_message

<aside class="warning">
Sockets connected with your JWT cannot send files yet. The file must first be uploaded through
Glific's upload endpoint (<code>POST /api/v1/web_channel/upload-url</code>), and that endpoint
currently accepts only the tokens Glific issues for its own phone and one-time-code sign-in, not
your JWT.
</aside>

The event is documented for completeness. No file bytes travel over the socket: the event names a
file that is already in your organization's Glific storage bucket.

```json
["1", "8", "web_channel:conversation", "new_media_message", {"type": "image", "url": "https://storage.googleapis.com/<bucket>/uploads/<id>.jpg", "content_type": "image/jpeg", "caption": "My homework"}]
```

Field | Required | Type | Limits
----- | -------- | ---- | ------
`type` | Yes | string | `image`, `audio`, `video` or `document`.
`url` | Yes | string | A URL Glific issued for an upload to your organization's storage bucket.
`content_type` | Yes | string | Must equal the stored file's content type and suit `type`: an `image/` type for image, a `video/` type for video, an `audio/` type other than `audio/ogg` for audio, PDF, Word, Excel or PowerPoint for document.
`caption` | No | string | Shown as the message body.

Size limits: image 5 MB (5120 KB), audio and video 16 MB (16384 KB), document 100 MB (102400 KB).

Reply `ok` with an empty payload.

Error reason | Cause
------------ | -----
`unsupported media type` | `type` is missing or not one of the four types, or `url` is missing. Note the spaces in this reason.
`invalid_media_url` | The URL is not in your organization's bucket, the file does not exist, or its content type does not match `content_type` or `type`.
`media_too_large` | The stored file is over the size limit for its type.
`rate_limited` | More than 20 events in 10 seconds.
`contact_blocked` | Your organization has blocked this contact (or deleted it).
`send_failed` | Glific could not store the message.

### Extend the session: renew_token

```json
["1", "9", "web_channel:conversation", "renew_token", {"token": "<fresh jwt>"}]
```

Field | Required | Type | Limits
----- | -------- | ---- | ------
`token` | Yes | string | A fresh, valid JWT for the same user. Same rules as the connection token.

Reply `ok` with an empty payload: the channel now expires at the new token's `exp`. See
<a href="#token-renewal-and-session-expiry">Token renewal and session expiry</a>.

Error reason | Cause
------------ | -----
`invalid_token` | Any problem: missing, malformed, expired or wrongly signed token; its `sub` belongs to another contact or to no contact yet; or it is not the same kind of token the socket connected with. The cause is never given.

`renew_token` is not rate limited and never changes which user the socket speaks for.

## Events Glific sends to you

Glific pushes these events on `web_channel:conversation`. Pushes have `ref` set to `null`.

### Receive a message: new_message

Sent when your organization sends the user a message on the web channel, for example a flow's
reply to the user. The payload is one <a href="#the-message-object">message</a> with
`flow: "outbound"`.

```json
["1", null, "web_channel:conversation", "new_message", {"id": 903, "body": "Great choice!", "type": "text", "flow": "outbound", "inserted_at": "2026-10-18T09:16:00.000000Z", "interactive_content": {}, "media": null}]
```

Delivery is best effort. A message sent while the user has no socket open is still stored, and
appears in the history the next time the user joins. Every open socket of the user (for example
two browser tabs) receives the push.

### token_expiring

Payload `{}`. Sent once per token, when fewer than 10 minutes remain before its `exp`. Get a fresh
token from your backend and push <a href="#extend-the-session-renew_token">renew_token</a>.

### session_expired

Payload `{}`. Sent when the token expired more than 60 seconds ago and was not renewed. Glific
then closes the channel (`phx_close`). The WebSocket itself stays open. Disconnect the socket,
get a fresh token and connect again, or show the user as signed out.

### web_channel_disabled

Payload `{}`. Sent when your organization's admin switches the Web Channel settings off. Glific
then closes the channel (`phx_close`). New connections are refused until it is switched on again.
Disconnect and tell the user chat is unavailable; do not retry in a loop.

### phx_close and phx_error

These are Phoenix protocol events, not Glific events:

* `phx_close` follows `session_expired` and `web_channel_disabled`. phoenix.js does not rejoin a
  closed channel.
* `phx_error` means the channel crashed on the server. phoenix.js rejoins automatically.

## Token renewal and session expiry

Timing, for a token with expiry `exp`:

When | What happens
---- | ------------
Every 60 seconds after the join | Glific checks the token's expiry.
First check with less than 10 minutes left | Glific pushes `token_expiring` (once per token).
Up to 60 seconds after `exp` | The token is still accepted (clock leeway).
First check at or after `exp` + 60 seconds | Glific pushes `session_expired` and closes the channel. Because checks run every 60 seconds, this happens between 60 and about 120 seconds after `exp`.

Renewal rules:

* Renew with a fresh token for the **same user**. Glific looks up the new token's `sub`
  (case-insensitive) and accepts it only if it belongs to the contact the socket is signed in as.
  A token for a different user, or for a `sub` Glific has never seen, is refused with
  `invalid_token`, and nothing is created.
* The new token must pass every check a connection token passes (signature, `channel`, `iat`,
  lifetime of at most 24 hours, not expired). `name` and `phone` in it are ignored.
* A socket renews only with the kind of token it connected with. A socket connected with your JWT
  renews only with your JWT. A socket connected with Glific's own phone and one-time-code token
  cannot be renewed with your JWT, and the other way round.
* After `ok`, the warning resets: if the new token is also close to expiry, `token_expiring` is
  sent again.
* There is no limit on how often a socket connected with your JWT can renew. You decide how long a
  user stays signed in by deciding when to stop issuing tokens.
* `renew_token` updates the open channel only. Keep the latest token in your client too, so a
  reconnect sends it (see <a href="#heartbeats-and-reconnecting">Heartbeats and reconnecting</a>).

## Web channel users and contacts

Each user is a **contact** in your organization, the same kind of contact a WhatsApp user is. Your
`sub` is stored as the contact's **web identity** (its username).

* The first connection with a new `sub` creates the contact, or links the `sub` to an existing
  WhatsApp contact (see below). A new contact gets the `name` claim as its name, or the lowercase
  username if there is no `name`.
* Every later connection with the same `sub` (in any letter case) signs in as the same contact.
  `name` and `phone` in later tokens are ignored, and staff edits to the contact are kept.
* Two first connections at the same time for the same new `sub` still end with one contact.
* A contact can hold more than one username. A username is held by exactly one contact and is
  never moved to another contact.
* If staff delete the contact, its usernames are deleted with it. The next connection with that
  `sub` creates a new contact.
* A blocked contact can still connect and read its history, but every message it sends is refused
  with `contact_blocked`.
* A user with only a web identity has no phone: `@contact.phone` is empty in flows and webhooks.
* With an upcoming Glific release, Glific records the user's web channel consent when they first
  connect.

### How the phone claim links users

The `phone` claim matters only on the first connection of a `sub`.

Case | Result
---- | ------
No `phone`, or a phone that is not valid | New contact without a phone.
Phone matches no contact in your organization | New contact with that phone. If that number later messages your organization on WhatsApp, those messages go to the same contact.
Phone matches a contact that has it as its WhatsApp number (the contact messaged your organization on WhatsApp, or was created or imported with that phone) | No new contact: the `sub` is added to that contact. The user has one contact across WhatsApp and the web. Its name is not changed.
Phone is your organization's own WhatsApp number | New contact without a phone. Never linked.
Phone is a Glific simulator number (starts with `9876543210`) | New contact without a phone. Never linked.
Phone is stored only on a web contact (for example, another web login sent it) and that number has never messaged your organization on WhatsApp | New contact without a phone. Never linked, and the phone is not stored twice.

Linking gives the user that contact's whole conversation and data in Glific (staff see one
contact; flows see its fields). Only send a phone you have verified.

### Managing usernames as staff

Staff with the manager role can manage usernames with the GraphQL API:

* <a href="#add-an-identity-to-a-contact">addContactIdentity</a> gives an existing contact a
  username, so that user's first web login signs in as that contact.
* <a href="#create-a-contact">createContact</a> with `channel: WEB` and an `identifier` creates the
  contact before the user's first login.
* <a href="#get-a-contact-by-identity">contactByIdentity</a> finds the contact for a username.

## Web channel errors reference

Where | Code or reason | Cause | Fix
----- | -------------- | ----- | ---
Connect | HTTP `403` | Bad, expired or wrongly signed token; missing token; unknown host; web channel off; no secret of 32 or more characters; `sub` with characters that are not allowed; 120 connection attempts per minute from your IP used up; browser origin not allowed. | Run the <a href="#check-a-token-before-you-connect">token check</a>. Check the host, the secret and your server clock. Back off before retrying. Confirm your origin with Glific.
Connect | HTTP `503` | The Glific server's connection budget is used up. | Retry with backoff.
Join | `unauthorized` | Topic is not `web_channel:conversation`, or the socket's token expired more than 60 seconds ago. | Join `web_channel:conversation`. Reconnect with a fresh token.
Join | `unmatched topic` | Topic does not start with `web_channel:`. | Join `web_channel:conversation`.
`new_message` | `blank_body` | `body` missing, not a string or only whitespace. | Send non-empty text.
`new_message` | `body_too_long` | More than 4096 characters after trimming. | Split the text.
`new_message`, `new_media_message`, `new_location_message`, `load_more` | `rate_limited` | More than 20 of these events in 10 seconds for this user. | Wait and retry.
`new_message`, `new_media_message`, `new_location_message` | `contact_blocked` | The contact is blocked or was deleted. | Tell the user they cannot message. Staff can unblock the contact.
`new_message`, `new_media_message`, `new_location_message` | `send_failed` | Glific could not store the message. | Retry once, then contact Glific.
`load_more` | `invalid_offset` | `offset` missing, not an integer or negative. | Send an integer of 0 or more.
`new_location_message` | `invalid_location` | Coordinates missing, not numbers or out of range. | Send numeric latitude (-90 to 90) and longitude (-180 to 180).
`new_media_message` | `unsupported media type` | `type` not `image`, `audio`, `video` or `document`, or `url` missing. | Send a supported type and a url.
`new_media_message` | `invalid_media_url` | URL not issued for your organization's bucket, file missing, or content type mismatch. | Upload through Glific's upload endpoint and send its URL and content type unchanged.
`new_media_message` | `media_too_large` | File over the limit for its type. | Send a smaller file.
`renew_token` | `invalid_token` | Token invalid or expired, for another user or an unknown `sub`, or not the kind the socket connected with. | Sign a fresh token for the same `sub` with a current secret.
Push | `session_expired` | The token expired and was not renewed. | Reconnect with a fresh token.
Push | `web_channel_disabled` | The web channel was switched off. | Stop and show chat as unavailable.

## Security and your responsibilities

* **Keep secrets on your server.** Never put a JWT signature secret in a browser, a mobile app, a
  public repository or client-side configuration. Anyone with the secret can sign in as any of
  your users.
* **Never sign tokens in the browser.** Your web app gets tokens from your backend, after your own
  login.
* **Use short lifetimes.** The maximum is 24 hours; one hour or less, renewed while the user is
  active, limits the damage of a leaked token. The token travels in the socket URL, so it can
  appear in proxy and server logs.
* **Only send a `phone` you have verified belongs to the user**, for example with your own
  one-time code. A phone links the user to that number's WhatsApp contact and its conversation.
* **A `sub` is permanent and unique.** Never reuse a `sub` for another person. If several of your
  systems sign tokens, they must agree on one `sub` per person; two systems issuing the same `sub`
  sign in as the same contact.
* **Never use a phone number as a `sub`**, least of all another person's. People who sign in to
  Glific's own web chat with phone and one-time code are stored with their phone number as their
  username, so a `sub` equal to someone's phone number signs in as that person.
* **Use HTTPS and WSS only.** Never connect over `ws://` or serve your web app over `http://`.
* **Rotate secrets** when someone with access leaves, or if a secret may have leaked. See
  <a href="#rotating-a-jwt-signature-secret">Rotating a JWT signature secret</a>.

## Testing and troubleshooting

### Check a token before you connect

This script checks a token the way Glific does, without connecting. It catches most causes of a
`403`.

```python
# check_glific_token.py
# usage: GLIFIC_JWT_SIGNATURE_SECRET=... python check_glific_token.py <token>
import os
import re
import sys
import time

import jwt  # pip install pyjwt

token = sys.argv[1]
secret = os.environ["GLIFIC_JWT_SIGNATURE_SECRET"]
now = int(time.time())
problems = []

if len(secret) < 32:
    sys.exit("secret is shorter than 32 characters; Glific ignores it")

header = jwt.get_unverified_header(token)
if header.get("alg") != "HS256":
    sys.exit(f"alg is {header.get('alg')!r}, must be 'HS256'")

try:
    claims = jwt.decode(
        token, secret, algorithms=["HS256"], options={"verify_exp": False, "verify_iat": False}
    )
except jwt.InvalidTokenError as error:
    sys.exit(f"signature check failed: {error}")

sub, iat, exp = claims.get("sub"), claims.get("iat"), claims.get("exp")
if not isinstance(sub, str) or not 1 <= len(sub) <= 255:
    problems.append("sub must be a string of 1 to 255 characters")
elif not re.fullmatch(r"[a-z0-9_@.]+", sub.lower()):
    problems.append("sub may only contain letters, digits, _, @ and .")
if claims.get("channel") != "web":
    problems.append("channel must be 'web'")
if type(iat) is not int or type(exp) is not int:
    problems.append("iat and exp must be integers")
else:
    if exp - iat > 86400:
        problems.append("exp - iat is more than 24 hours")
    if iat > now + 60:
        problems.append("iat is more than 60 seconds in the future (check your clock)")
    if exp <= now - 60:
        problems.append("token has expired")
name = claims.get("name")
if name is not None and (not isinstance(name, str) or len(name) > 255):
    problems.append("name must be a string of at most 255 characters")
if "phone" in claims and not isinstance(claims["phone"], str):
    problems.append("phone is not a string and will be ignored")

print("\n".join(problems) or "token looks valid for Glific")
```

### Smoke test the connection

This script connects, joins, prints the history and sends one message. It speaks the raw
protocol, so it also shows you the frames. It sends no `Origin` header.

```python
# smoke_test.py
# usage: python smoke_test.py api.example.glific.com <token>
import asyncio
import json
import sys

import websockets  # pip install websockets


async def main(host, token):
    url = f"wss://{host}/web_socket/websocket?token={token}&vsn=2.0.0"
    topic = "web_channel:conversation"
    try:
        async with websockets.connect(url) as ws:
            await ws.send(json.dumps(["1", "1", topic, "phx_join", {}]))
            print("join reply:", await ws.recv())

            body = {"body": "Hello from the smoke test"}
            await ws.send(json.dumps(["1", "2", topic, "new_message", body]))
            print("send reply:", await ws.recv())

            try:
                while True:
                    print("push:", await asyncio.wait_for(ws.recv(), timeout=20))
            except asyncio.TimeoutError:
                pass
    except websockets.exceptions.InvalidStatus as error:
        print("connection refused with HTTP", error.response.status_code)


asyncio.run(main(sys.argv[1], sys.argv[2]))
```

### Common mistakes

Symptom | Likely cause
------- | ------------
Every connection gets `403` | Wrong host (connect to `api.<your org>.glific.com`); the secret on your backend differs from the one in Glific; the secret is shorter than 32 characters; the `channel` claim is missing; the web channel is not switched on.
`403` only for some users | Their `sub` contains a character that is not allowed (often `-` from a UUID, or a space).
`403` some of the time, right after you sign | Your server clock is ahead by more than 60 seconds (`iat` in the future). Sync it with NTP.
`403` for tokens that worked before | The token is older than `exp` + 60 seconds; a secret was removed; the lifetime is over 24 hours.
`403` from the browser but the smoke test works | The browser's origin is not on Glific's allowed list. Ask Glific to allow it.
`403` after many reconnects | 120 connection attempts per minute from one IP used up. Add backoff.
Join replies `unauthorized` | You joined a topic other than `web_channel:conversation`, or the token expired.
Session ends although you renewed | The reconnect sent the old token: pass `params` as a function returning the latest token. Or a rejoin happened after renewal and you did not push `renew_token` again.
Users land on the wrong contact | A `sub` was reused, or a phone you did not verify linked them to someone else's WhatsApp contact.
`phone` was not linked | The phone was a JSON number, missed the country code, was invalid, or the `sub` had already connected before.

### Web channel FAQ

**Can I change a user's `sub`?** Not through the token. Ask your staff to add the new username to
the contact with <a href="#add-an-identity-to-a-contact">addContactIdentity</a> before the user
connects with it; the old one keeps working.

**Can a user have several devices or tabs open?** Yes. Glific does not limit open connections per
user. Each socket receives outbound messages.

**Will the user see their WhatsApp history after linking?** No. The web conversation shows only web
channel messages.

**Does the token carry the organization?** No. The host decides the organization.

**What happens to a message sent while the user is offline?** It is stored and appears in the
history the next time the user joins.

## Web channel limits

Defaults; a Glific deployment may change the rate limits.

Limit | Value
----- | -----
JWT signature secrets per organization | 2
Secret length | at least 32 characters
`sub` | 1 to 255 characters: letters, digits, `_`, `@`, `.`
`name` length | at most 255 characters
Token lifetime (`exp - iat`) | at most 86400 seconds (24 hours)
Clock leeway on `iat` and `exp` | 60 seconds
`token_expiring` warning | 10 minutes before `exp`
Expiry checks | every 60 seconds; channel closed 60 to about 120 seconds after `exp`
Connection attempts per IP address | 120 per minute
Connection attempts per Glific server | 1000 per minute
Idle socket timeout | 60 seconds without a heartbeat or message
Text message body | 1 to 4096 characters, after trimming
Messages per history page (join and `load_more`) | 100
`new_message`, `new_media_message`, `new_location_message`, `load_more` | 20 per 10 seconds per user
Latitude, longitude | -90 to 90, -180 to 180
Image, audio, video, document size | 5120 KB, 16384 KB, 16384 KB, 102400 KB
