# Web Channel Login

Let your own users chat with your organization on Glific's web channel, signed in with your own
login system. Your users never need a phone number or a Glific password.

How it works:

1. Your organization admin adds a **JWT signature secret** in Glific.
2. After a user logs in to your system, your backend signs a **token** for that user with that secret.
3. Your web app opens a **WebSocket** to Glific with the token, joins the conversation, and sends and
   receives messages.

The first time a user connects, Glific creates a contact for them. Every later connection with the
same username signs in as the same contact.

## Step 1: Set up Glific

On the **Web Channel** settings page, your organization admin:

* switches the web channel **on**;
* adds a **JWT signature secret**: a name of your choice (for example `2026`) and a random secret of
  **at least 32 characters**. A shorter secret is ignored.

You can keep up to **two** secrets; a token signed with either is accepted. Keep one secret, and a
second only while rotating:

1. Add the new secret.
2. Switch your backend to sign with the new secret.
3. Remove the old secret.

Keep the secret on your server only. Anyone who has it can sign in as any of your users.

## Step 2: Create a token for each user

The token is a standard **JWT** signed with **HS256** using your secret. Any JWT library can create
it. To try things out, you can build one by hand at [jwt.io](https://jwt.io): pick HS256, paste the
payload below and your secret. Only do this with a test secret.

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
`sub` | Yes | Your user's username. 1 to 255 characters, only letters, digits, `_`, `@` and `.`. Upper and lower case are the same user. It must never change for a user and never be reused for another person.
`channel` | Yes | Always `"web"`.
`iat` | Yes | When you created the token, in seconds since 1 January 1970 (Unix time).
`exp` | Yes | When the token expires, in Unix time. At most **24 hours** after `iat`. One hour is a good default.
`name` | No | The user's name, up to 255 characters. Used only when the contact is first created. If missing, the username is used.
`phone` | No | The user's WhatsApp number with country code, digits only (for example `919876543210`). Send it only if you have verified it belongs to the user. An invalid number is ignored.

Any other field is ignored. Glific allows up to 60 seconds of clock difference with your server.

**What `phone` does.** It only matters the first time a user connects:

* If the number belongs to a contact that is already on WhatsApp with your organization, the user is
  added to that contact, so they have one conversation across WhatsApp and the web.
* If no contact has the number, a new contact is created with it.
* Your organization's own number, Glific simulator numbers and numbers saved only by another web
  login are never linked; the user gets a new contact without a phone.

## Step 3: Connect

Open a WebSocket to your organization's Glific API host, with the token in the URL:

```
wss://api.<your-organization>.glific.com/web_socket/websocket?token=<TOKEN>&vsn=2.0.0
```

If your Glific dashboard is `https://example.glific.com`, the host is `api.example.glific.com`.
Glific finds your organization from the host, never from the token.

If the token or setup is wrong, the connection is refused (HTTP `403`). If Glific is busy, it
answers `503`; try again a little later.

Glific's socket uses the Phoenix protocol. The easiest option in a web app is the official
`phoenix` JavaScript client. With any other WebSocket client, every message you send or receive is a
JSON array:

```
[join_ref, ref, topic, event, payload]
```

* `join_ref`: the `ref` of your join message (`"1"` below). Use it in every message after joining.
* `ref`: a new number for each message you send, so you can match Glific's reply to it.

Send a heartbeat at least every **30 seconds**, or Glific closes the connection after 60 seconds
of silence:

```json
[null, "2", "phoenix", "heartbeat", {}]
```

## Step 4: Join the conversation

Send one join message after connecting:

```json
["1", "1", "web_channel:conversation", "phx_join", {}]
```

The topic must be exactly `web_channel:conversation`; any other topic is refused. Glific replies with
the contact's id and its recent messages (up to 100, oldest first):

```json
["1", "1", "web_channel:conversation", "phx_reply",
 {"status": "ok", "response": {"contact_id": 57573, "messages": []}}]
```

Each message has `id`, `body`, `type` (for example `text`), `flow` (`inbound` from the user,
`outbound` from your organization), `inserted_at` and, for files, `media`.

## Step 5: Send and receive messages

**Send a text message**

```json
["1", "3", "web_channel:conversation", "new_message", {"body": "Hello"}]
```

`body` is required: 1 to 4096 characters. Glific replies `{"status": "ok"}` and the message appears
in your organization's Glific inbox.

**Share a location**

```json
["1", "4", "web_channel:conversation", "new_location_message", {"latitude": 12.97, "longitude": 77.59}]
```

**Load older messages**

```json
["1", "5", "web_channel:conversation", "load_more", {"offset": 100}]
```

`offset` is how many messages you already have. The reply contains up to 100 older messages.

**Receive messages.** When your organization replies (from the inbox or a flow), Glific sends:

```json
["1", null, "web_channel:conversation", "new_message", {"id": 903, "body": "Hi Ravi!", "flow": "outbound"}]
```

Messages sent while the user is offline are kept and arrive in the join reply next time.

Sending files with this login is not supported yet.

A user can send at most 20 messages (of any kind, including `load_more`) per 10 seconds.

## Step 6: Keep the session alive

A token lasts until its `exp`. Before then:

* About **10 minutes before** `exp`, Glific sends `token_expiring`.
* Get a fresh token for the **same user** from your backend and send it:

```json
["1", "6", "web_channel:conversation", "renew_token", {"token": "<NEW TOKEN>"}]
```

If you don't renew, Glific sends `session_expired` shortly after `exp` and closes the conversation.
Connect again with a fresh token.

If the organization switches the web channel off, Glific sends `web_channel_disabled`. Stop and show
chat as unavailable.

## Errors

When something is refused, Glific's reply has `"status": "error"` and a `reason`:

Reason | Meaning
------ | -------
`unauthorized` | Wrong topic on join (use `web_channel:conversation`), or the token has expired.
`blank_body` | The message `body` is empty.
`body_too_long` | The message is longer than 4096 characters.
`invalid_location` | Latitude or longitude is missing or out of range.
`invalid_offset` | `offset` is missing or negative.
`rate_limited` | Too many messages in a short time. Wait and retry.
`contact_blocked` | Your organization has blocked this user.
`send_failed` | Glific could not save the message. Retry once.
`invalid_token` | The renewal token is invalid, expired or for a different user.

If the connection itself is refused (`403`), check:

* the host is your organization's `api.` host;
* the token is signed with HS256 using a current secret of 32 or more characters;
* `channel` is `"web"`, `exp` is in the future and at most 24 hours after `iat`;
* `sub` only uses letters, digits, `_`, `@` and `.`;
* the web channel is switched on.

You can paste your token into [jwt.io](https://jwt.io) to check its contents and signature.

## Your responsibilities

* Keep JWT signature secrets on your server. Never put them in a browser, an app or a public
  repository, and never create tokens in the browser.
* Give each person one permanent `sub`, and never use a phone number as a `sub`.
* Only send a `phone` you have verified belongs to the user.
* Use short-lived tokens (an hour is plenty) and renew them while the user is active.
* Before going live, ask Glific to allow your web app's address (origin) to connect.

## Managing users as staff

Staff with the manager role can also manage web users with the GraphQL API:

* <a href="#add-an-identity-to-a-contact">addContactIdentity</a> gives an existing contact a username,
  so that user's first web login signs in as that contact.
* <a href="#create-a-contact">createContact</a> with `channel: WEB` and an `identifier` creates the
  user's contact before they first log in.
* <a href="#get-a-contact-by-identity">contactByIdentity</a> finds the contact for a username.
