# Web Channel Login

The web channel lets your own app or website talk to Glific on behalf of your users. Your backend
signs a short-lived token for the logged-in user, and the user's browser opens a WebSocket to Glific
with it. Glific never sees your users' passwords.

## JWT signature secrets

An organization admin sets up to two JWT signature secrets, each with a name of your choice, on the
**Web Channel** settings page. A token signed with either secret is accepted. To rotate a secret:

1. Fill the empty slot with a new name and JWT signature secret.
2. Switch your backend to sign with the new secret.
3. Clear the old slot.

Each secret must be at least 32 characters long; Glific ignores a shorter one, so tokens signed
with it are refused.

The organization is taken from the host the socket connects to (`api.<your glific host>`), never from
the token.

## Token

A JWT signed with a JWT signature secret.

* The header must say `alg: HS256`; any other algorithm is refused. There is no `kid`.
* `sub` (required): your username for the user, at most 255 characters, only letters, digits, `_`,
  `@` and `.`. It is case-insensitive: `Ravi_12` and `ravi_12` are the same user.
* `channel` (required): the string `"web"`.
* `iat` and `exp` (required): seconds since the epoch. `exp - iat` must be at most 24 hours. A clock
  difference of up to 60 seconds is tolerated.
* `name` (optional): the contact's name for a new contact. Defaults to `sub`.
* `phone` (optional): the user's WhatsApp number as digits with the country code and no `+`.

```javascript
// Node.js, using the jsonwebtoken package
const jwt = require("jsonwebtoken");

const token = jwt.sign(
  { sub: "ravi_12", channel: "web", name: "Ravi" },
  process.env.GLIFIC_JWT_SIGNATURE_SECRET,
  { algorithm: "HS256", expiresIn: "6h" } // adds iat and exp
);
```

```python
# Python, using PyJWT
import time, jwt

now = int(time.time())
token = jwt.encode(
    {"sub": "ravi_12", "channel": "web", "name": "Ravi", "iat": now, "exp": now + 6 * 3600},
    JWT_SIGNATURE_SECRET,
    algorithm="HS256",
)
```

## Connecting

Open `wss://<org api host>/web_socket/websocket?token=<jwt>&vsn=2.0.0`, using any Phoenix Channels
client. A refused token fails the connection without saying why.

Event | Direction | Payload | Description
----- | --------- | ------- | -----------
`phx_join` on `web_channel:conversation` | client to Glific | `{}` | The reply is `{contact_id, messages}`, the latest messages of the conversation.
`new_message` | client to Glific | `{body}` | Send a message from the user.
`new_message` | Glific to client | message | A message for the user, as soon as it is sent.
`renew_token` | client to Glific | `{token}` | Extend the session with a new token for the same `sub`. Replies `ok`, or an error with reason `invalid_token`.
`token_expiring` | Glific to client | `{}` | Sent 10 minutes before the token expires. Renew now.
`session_expired` | Glific to client | `{}` | The token expired and was not renewed; the socket is closed.

Fetch a fresh token from your backend when `token_expiring` arrives and push it with `renew_token`.

## Contacts

The first connection with a new `sub` creates the contact. If `phone` is given and is the number of a
WhatsApp contact in the organization, the username is linked to that contact instead, so the user
has one conversation across WhatsApp and the web. If the `sub` is already known, its contact is used
and `phone` is ignored. The organization's own WhatsApp contact and simulator contacts are never
linked to.

Glific treats a phone you send as the user's own: the contact owns that number, including its
WhatsApp messages.

You can also create the contact ahead of the first login with the
<a href="#create-a-contact">createContact</a> mutation with `channel: WEB` and an `identifier` (or give an
existing contact a username with <a href="#add-an-identity-to-a-contact">addContactIdentity</a>), and look a
user's contact up with <a href="#get-a-contact-by-identity">contactByIdentity</a>.

## Your responsibilities

* Only send a `phone` you have verified belongs to the user. Glific trusts the token, and linking
  attaches the user to that number's conversation.
* A `sub` is permanent for a user and must be unique across every system you sign tokens from. Two
  systems issuing the same `sub` log in as the same contact. Reconciling ids between your systems
  is your job.
* Never use another person's phone number as a `sub`. People who sign in to the web chat with their
  phone and a one-time code are recorded under their phone number, so a `sub` equal to someone's
  phone signs in as that person.
* A user who only has a web identity has no phone: `@contact.phone` is empty in flows and webhooks.
