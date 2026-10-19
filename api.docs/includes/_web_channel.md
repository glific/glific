# Web Channel Login

Let your own users chat with your organization on Glific's web channel, signed in with your own
login system. Your users never need a phone number or a Glific password.

The web channel has one public API: a **WebSocket**. Your backend signs a token for each of your
users, your app connects to the socket with that token, joins the conversation, and sends and
receives messages.

## Authentication

### 1. Generate a JWT signature secret

An admin of your organization opens **Settings → Web Channel** in Glific
(`https://<your-organization>.glific.com/settings/web_channel`), switches the web channel **on** and
adds a **JWT signature secret**:

* **Name**: anything that helps you tell secrets apart, for example `2026`.
* **Secret**: a random value of **at least 32 characters**. A shorter secret is ignored.

You can keep up to **two** secrets; a token signed with either is accepted. Keep one, and add a
second only while rotating: add the new secret, switch your backend to it, then remove the old one.

Keep the secret on your server only. Anyone who has it can sign in as any of your users, so never
put it in a browser, an app or a public repository.

### 2. Create the token

The token is a standard **JWT** signed with **HS256** using your secret. Any JWT library can create
it. To try things out, you can build one by hand at [jwt.io](https://jwt.io): choose HS256, paste the
payload below and your secret (use a test secret for this).

**Header**

```json
{ "alg": "HS256", "typ": "JWT" }
```

**Payload**

```json
{
  "sub": "ravi_12",
  "channel": "web",
  "iat": 1792310400,
  "exp": 1792314000,
  "name": "Ravi Kumar",
  "phone": "919876543210"
}
```

Field | Required | What to put
----- | -------- | -----------
`sub` | Yes | Your user's username. 1 to 255 characters, only letters, digits, `_`, `@` and `.`. Upper and lower case are the same user. It must never change for a user, never be reused for another person, and never be a phone number.
`channel` | Yes | Always `"web"`.
`iat` | Yes | When you created the token, in seconds since 1 January 1970 (Unix time).
`exp` | Yes | When the token expires, in Unix time. At most **24 hours** after `iat`. One hour is a good default.
`name` | No | The user's name, up to 255 characters. Used only when the user first connects. If missing, the username is used.
`phone` | No | The user's WhatsApp number with country code, digits only (for example `919876543210`). Send it only if you have verified it belongs to the user. An invalid number is ignored.

Any other field is ignored. Glific allows up to 60 seconds of clock difference with your server.

The first time a user connects, Glific creates a contact for them. Every later connection with the
same `sub` signs in as the same contact. If you send a `phone` and that number already chats with
your organization on WhatsApp, the user joins that same contact, so they have one conversation
across WhatsApp and the web.

### 3. Connect to the socket

Open a WebSocket to your organization's Glific API host, with the token in the URL:

```
wss://api.<your-organization>.glific.com/web_socket/websocket?token=<TOKEN>&vsn=2.0.0
```

If your Glific dashboard is `https://example.glific.com`, the host is `api.example.glific.com`.
Glific finds your organization from the host, never from the token.

If the connection is refused (HTTP `403`), check that:

* the host is your organization's `api.` host;
* the token is signed with HS256 using a current secret of 32 or more characters;
* `channel` is `"web"`, `exp` is in the future and at most 24 hours after `iat`;
* `sub` only uses letters, digits, `_`, `@` and `.`;
* the web channel is switched on.

You can paste a token into [jwt.io](https://jwt.io) to check its contents and signature. A `503`
means Glific is busy; try again a little later. Before going live, ask Glific to allow your web
app's address (origin) to connect.

The socket uses the Phoenix protocol. In a web app, the easiest option is the official `phoenix`
JavaScript client. With any other WebSocket client, every message you send or receive is a JSON
array:

```
[join_ref, ref, topic, event, payload]
```

* `join_ref`: the `ref` of your join message (`"1"` below). Use it in every message after joining.
* `ref`: a new number for each message you send, so you can match Glific's reply to it.

Send a heartbeat at least every **30 seconds**, or Glific closes the connection after 60 seconds of
silence:

```json
[null, "2", "phoenix", "heartbeat", {}]
```

### 4. Keep the session alive

A token is valid until its `exp`. About **10 minutes before** that, Glific sends a `token_expiring`
event. Get a fresh token for the **same user** from your backend and send it:

```json
["1", "6", "web_channel:conversation", "renew_token", {"token": "<NEW TOKEN>"}]
```

If the token is not renewed, Glific sends `session_expired` shortly after `exp` and closes the
conversation; connect again with a fresh token. A token for a different user is refused with
`invalid_token`.

## Joining the conversation

After connecting, send one join message:

```json
["1", "1", "web_channel:conversation", "phx_join", {}]
```

The topic must be exactly `web_channel:conversation`; any other topic is refused with
`unauthorized`. Glific replies with the user's contact id and their recent messages (up to 100,
oldest first):

```json
["1", "1", "web_channel:conversation", "phx_reply",
 {"status": "ok", "response": {"contact_id": 57573, "messages": []}}]
```

Each message has `id`, `body`, `type` (for example `text`), `flow` (`inbound` from the user,
`outbound` from your organization), `inserted_at` and, for files, `media`.

To load older messages, send how many you already have as `offset`; the reply has up to 100 more:

```json
["1", "5", "web_channel:conversation", "load_more", {"offset": 100}]
```

## Sending messages

**Text**

```json
["1", "3", "web_channel:conversation", "new_message", {"body": "Hello"}]
```

`body` is required: 1 to 4096 characters. Glific replies `{"status": "ok"}` and the message appears
in your organization's Glific inbox.

**Location**

```json
["1", "4", "web_channel:conversation", "new_location_message", {"latitude": 12.97, "longitude": 77.59}]
```

`latitude` is -90 to 90 and `longitude` is -180 to 180.

Sending files is not supported yet with this login.

A user can send at most 20 events (messages, locations and `load_more` together) per 10 seconds.

If a message is refused, the reply has `"status": "error"` and a `reason`:

Reason | Meaning
------ | -------
`blank_body` | The message `body` is empty.
`body_too_long` | The message is longer than 4096 characters.
`invalid_location` | Latitude or longitude is missing or out of range.
`invalid_offset` | `offset` is missing or negative.
`rate_limited` | Too many events in a short time. Wait and retry.
`contact_blocked` | Your organization has blocked this user.
`send_failed` | Glific could not save the message. Retry once.

## Receiving messages

When your organization sends the user a message (from the Glific inbox or a flow), Glific pushes it
on the conversation:

```json
["1", null, "web_channel:conversation", "new_message", {"id": 903, "body": "Hi Ravi!", "type": "text", "flow": "outbound"}]
```

Messages sent while the user is offline are kept and arrive in the join reply the next time they
connect.

Glific may also send:

Event | Meaning | What to do
----- | ------- | ----------
`token_expiring` | The token expires in about 10 minutes. | Send `renew_token` with a fresh token.
`session_expired` | The token expired and was not renewed. | Connect again with a fresh token.
`web_channel_disabled` | Your organization switched the web channel off. | Disconnect and show chat as unavailable.
