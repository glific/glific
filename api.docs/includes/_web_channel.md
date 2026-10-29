# Web Channel Login

The web channel lets your own app or website talk to Glific on behalf of your users. Your backend
signs a short-lived token for the logged-in user, and the user's browser opens a WebSocket to Glific
with it. Glific never sees your users' passwords.

## JWT signature secret

Each organization has one JWT signature secret, shown on the **Web Channel** settings page. Glific
creates it when the web channel is enabled, and keeps it if the channel is switched off. Set your
backend to sign with it.

Replacing the secret signs every user of the organization out: tokens signed with the old one stop
being accepted, with no grace period (allow up to a day for every Glific server to switch over).
Change it only when you can update your backend at the same time. A secret must be at least 32
characters long, and it can be replaced but not removed.

The organization is taken from the host the request or socket connects to (`api.<your glific host>`),
never from the token. This holds for every token, including the one Glific issues after a phone and
one-time code login, and each is checked against that organization's secret only.

## Token

A JWT signed with the organization's JWT signature secret.

* The header must say `alg: HS256`; any other algorithm is refused. There is no `kid`.
* `sub` (required): your username for the user, at most 255 characters, only letters, digits, `_`,
  `@` and `.`. It is case-insensitive: `Ravi_12` and `ravi_12` are the same user.
* `channel` (required): the string `"web"`.
* `iat` and `exp` (required): seconds since the epoch. `exp - iat` must be at most 24 hours. A clock
  difference of up to 60 seconds is tolerated.
* `name` (optional): the contact's name for a new contact. Defaults to `sub`.
* `phone` (optional): the user's WhatsApp number as digits with the country code and no `+`.
* `optin` (optional): a boolean. `true` records the user's consent to be messaged on the web channel, the
  first time it is seen; `false` or absent records nothing, and it never opts the user out. Connecting alone
  never opts a user in. It has no effect on the user's WhatsApp consent. Any other type makes the token invalid.
* `jti` and `sst`: reserved for the sessions Glific issues after a one-time code login. Do not send them.

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
`new_media_message` | client to Glific | `{type, url, content_type, caption}` | Send a file the user uploaded. See <a href="#sending-files">Sending files</a>.
`new_location_message` | client to Glific | `{latitude, longitude}` | Share the user's location, e.g. to answer a location request.
`load_more` | client to Glific | `{offset}` | The reply is `{messages}`, the next older page of up to 100 messages.
`web_channel_disabled` | Glific to client | `{}` | The organization switched the web channel off; the socket is closed.
`new_message` | Glific to client | message | A message for the user, as soon as it is sent.
`renew_token` | client to Glific | `{token}` | Extend the session with a new token for the same `sub`. Replies `ok`, or an error with reason `invalid_token`.
`token_expiring` | Glific to client | `{}` | Sent 10 minutes before the token expires. Renew now.
`session_expired` | Glific to client | `{}` | The token expired and was not renewed; the socket is closed.

Fetch a fresh token from your backend when `token_expiring` arrives and push it with `renew_token`.

## Messages

Every message, live or in history, has the same shape. Render it by `type`.

> A message from Glific:

```json
{
  "id": 1234,
  "type": "text",
  "flow": "outbound",
  "body": "Welcome to Glific!",
  "inserted_at": "2026-10-22T08:16:56Z",
  "interactive_content": null,
  "media": null
}
```

Field | Description
----- | -----------
`id` | The message id.
`type` | What kind of message it is, see below.
`flow` | `outbound` for a message from Glific to the user, `inbound` for one the user sent (only in history).
`body` | The text. For a media message, its caption. May be empty.
`inserted_at` | When the message was created, in UTC.
`interactive_content` | The buttons, list or request of an interactive message, otherwise `null`.
`media` | `{url}` for a media message, otherwise `null`.

`type` | Render | The user answers with
------ | ------ | ---------------------
`text` | `body`. | `new_message`
`image`, `video`, `audio`, `document` | `media.url` as an image, a player or a download, with `body` as the caption. |
`sticker` | `media.url` as an image (webp). |
`quick_reply` | `interactive_content.content` and a button per option. | `new_message` with the tapped option's `title`
`list` | A button (`globalButtons[0].title`) opening `items`, each a section of options. | `new_message` with the chosen option's `title`
`location_request_message` | `interactive_content.body.text` and a button to share the location. | `new_location_message`

A user's own messages appear in history with `flow: "inbound"`, also as `location`, whose `body` is a
Google Maps link to the point.

### Answering an interactive message

There is no separate event for tapping a button or a list option. Push `new_message` with the
option's `title`, exactly as in `interactive_content`; flows match it like a WhatsApp button reply.
A location request is answered with `new_location_message`.

> A quick reply, answered with `{"body": "yes"}`:

```json
{
  "type": "quick_reply",
  "flow": "outbound",
  "body": "",
  "interactive_content": {
    "type": "quick_reply",
    "content": {
      "type": "text",
      "header": "Are you excited for Glific?",
      "text": "Glific comes with all new features"
    },
    "options": [
      {"type": "text", "title": "yes"},
      {"type": "text", "title": "no"}
    ]
  },
  "media": null
}
```

> A list, answered with `{"body": "Custom Flows"}`:

```json
{
  "type": "list",
  "interactive_content": {
    "type": "list",
    "title": "Interactive list",
    "body": "Glific",
    "globalButtons": [{"type": "text", "title": "button text"}],
    "items": [
      {
        "title": "Glific Features",
        "subtitle": "first Subtitle",
        "options": [
          {"type": "text", "title": "Custom Flows", "description": "Flow Editor for creating flows"}
        ]
      }
    ]
  }
}
```

> A location request, answered with `new_location_message`:

```json
{
  "type": "location_request_message",
  "interactive_content": {
    "type": "location_request_message",
    "body": {"type": "text", "text": "please share your location"},
    "action": {"name": "send_location"}
  }
}
```

A quick reply's `content.type` is `text`, or `image`, `video` or `document` with a `url` to show above
the text.

### Sending

> Text, or an answer to a quick reply or list:

```json
{"body": "yes"}
```

> A location:

```json
{"latitude": 28.6139, "longitude": 77.2090}
```

`new_message` takes a `body` of 1 to 4096 characters, trimmed. `new_location_message` takes numbers,
latitude between -90 and 90 and longitude between -180 and 180. Every push is replied to with `ok`,
or an error with one of these reasons:

`reason` | When
-------- | ----
`blank_body` | `body` is missing or empty.
`body_too_long` | `body` is over 4096 characters.
`invalid_location` | Missing or out of range coordinates.
`invalid_media_url`, `media_too_large`, `unsupported media type` | See <a href="#sending-files">Sending files</a>.
`rate_limited` | The user is sending too fast. Wait and retry.
`contact_blocked` | The contact is blocked or no longer exists.
`send_failed` | Anything else. Retry later.

## Sending files

A file takes three steps, and its bytes never pass through Glific:

1. **Get an upload URL** from Glific with the user's token.
2. **Upload the file** to the organization's Google Cloud Storage bucket with that URL.
3. **Send the file's `url`** over the socket with `new_media_message`.

The organization must have Google Cloud Storage set up.

### Accepted files

`type` | Accepted `content_type` | Max size
------ | ---------------------- | --------
`image` | `image/*`, e.g. `image/png`, `image/jpeg`, `image/gif`, `image/webp` | 5 MB
`video` | `video/*`, e.g. `video/mp4` | 16 MB
`audio` | `audio/*` except `audio/ogg`, e.g. `audio/mpeg`, `audio/aac` | 16 MB
`document` | PDF, Word (`.doc`, `.docx`), Excel (`.xls`, `.xlsx`), PowerPoint (`.ppt`, `.pptx`) | 100 MB

### 1. Get an upload URL

`POST /api/v1/web_channel/upload-url` on the organization's API host, with the user's token as
`Authorization: Bearer <token>`. The token is checked like a socket connection's, and its `sub` must
belong to an existing contact: connect to the socket once first.

```shell
curl -X POST https://api.<org>.glific.com/api/v1/web_channel/upload-url \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"type": "image", "content_type": "image/png", "size": 20480}'
```

Field | Required | Description
----- | -------- | -----------
`type` | yes | `image`, `audio`, `video` or `document`.
`content_type` | yes | The file's MIME type. Must be accepted for `type`; the upload must send exactly this value.
`size` | yes | The file's size in bytes, within the limit for `type`.

> Returns JSON structured like this:

```json
{
  "data": {
    "upload_url": "https://storage.googleapis.com/<bucket>/uploads/4edd172e-4d46-4505-89a2-aa85248e07ec.png?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Expires=300&X-Goog-SignedHeaders=content-type%3Bhost&X-Goog-Signature=...",
    "url": "https://storage.googleapis.com/<bucket>/uploads/4edd172e-4d46-4505-89a2-aa85248e07ec.png",
    "content_type": "image/png",
    "expires_in": 300
  }
}
```

Field | Description
----- | -----------
`upload_url` | Where to upload the file, valid for `expires_in` seconds (5 minutes).
`url` | Where the file is stored once uploaded. Nothing is there until step 2 succeeds. Send it in step 3.
`content_type` | The content type to upload with.
`expires_in` | Seconds `upload_url` stays valid.

> Errors are returned like this:

```json
{"error": {"status": 413, "code": "file_too_large", "message": "Maximum size limit is 5120KB"}}
```

Status | `code` | When
------ | ------ | ----
401 | `unauthorized` | Missing or invalid token, a token for another organization, or no contact has this `sub`.
404 | `web_channel_disabled` | The web channel is off for the organization.
413 | `file_too_large` | `size` is over the limit for `type`.
415 | `unsupported_type` | `type` or `content_type` is not accepted.
422 | `invalid_size` | `size` is not a positive integer.
422 | `upload_failed` | `type`, `content_type` or `size` is missing.
429 | `rate_limited` | Too many upload URLs requested. Wait and retry.
503 | `storage_unavailable` | The organization has no Google Cloud Storage set up.
500 | `signing_failed` | The URL could not be signed. Retry later.

Branch on `code`, not on `message`.

### 2. Upload the file

`PUT` the file's bytes to `upload_url` before it expires, with `Content-Type` set to exactly the
`content_type` from step 1 and no `Authorization` header. Use the URL as returned: changing any
character of it invalidates the signature.

```shell
curl -X PUT "<upload_url>" \
  -H "Content-Type: image/png" \
  --data-binary @photo.png
```

```javascript
// In the browser, with the File the user picked
await fetch(uploadUrl, {
  method: "PUT",
  headers: { "Content-Type": file.type },
  body: file
});
```

A `200` with an empty body means the file is stored at `url`. Google reports a failure as an XML
`<Error>` body; `403 SignatureDoesNotMatch` usually means the `Content-Type` differs from step 1, and
an expired URL needs a new one from step 1.

### 3. Send it

Push `new_media_message` on the conversation channel with the `url` from step 1.

```json
{
  "type": "image",
  "url": "https://storage.googleapis.com/<bucket>/uploads/4edd172e-4d46-4505-89a2-aa85248e07ec.png",
  "content_type": "image/png",
  "caption": "optional text"
}
```

`type` and `content_type` must match step 1, and `url` must be one Glific issued for the
organization. Glific checks the stored file's size and content type before posting it. The reply is
`ok`, or an error with reason `invalid_media_url` (not an issued URL, nothing uploaded, or a mismatch),
`media_too_large`, or `unsupported media type`.

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
existing contact a username with <a href="#add-an-identity-to-a-contact">addContactIdentity</a>), record the
user's web consent with <a href="#optin-a-contact">optinContact</a> and `channel: WEB`, and look a user's
contact up with <a href="#get-a-contact-by-identity">contactByIdentity</a>. Creating a contact never opts it in.

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
