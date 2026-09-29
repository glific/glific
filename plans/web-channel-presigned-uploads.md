# Pre-signed uploads — bytes never touch Glific

Follow-up on #5663. Replaces the multipart upload endpoint with a signed-URL handshake: the
browser PUTs the file straight into the organization's own GCS bucket, and Glific only ever sees
the metadata.

**Branch:** `web-channel-send-messages` in both repos (extends the open PRs, glific#5714 and
glific-web-channel#5).

## Why

Today every attachment is proxied: the browser POSTs multipart to
`POST /api/v1/web_channel/upload`, Glific buffers it (the endpoint's parser cap was raised to
110 MB for this route alone), writes it to a temp file, then uploads to GCS. That means a 100 MB
document crosses the network twice, occupies a Phoenix process for the duration, and is bounded
only by how many beneficiaries upload at once. It is also the one route where an unauthenticated
request can make the server buffer 110 MB before the 401, which the review already flagged.

The upload still lands in the organization's own bucket, under its own service account. What
changes is that the bytes go direct.

## Shape

```
POST /api/v1/web_channel/upload-url     {type, content_type, size}
  -> {upload_url, url, content_type, expires_in}

PUT <upload_url>                        the file, Content-Type as returned
  -> 200 from GCS, no Glific involvement

socket new_media_message                {type, url, ...}
  -> Glific verifies the object before persisting
```

## 1 — Per-organization V4 signing

New module `Glific.GCS.SignedUrl`.

**Do not reuse `GCS.get_signed_url/3` or waffle's signer.** Both go through
`GCS.load_goth/1`, which calls `Goth.Config.set(:client_email, ...)` and
`Goth.Config.set("private_key", ...)` — **global** process state, in a multi-tenant application.
Two organizations signing concurrently race, and the loser signs with the other's identity.
`Waffle.Storage.Google.UrlV2.build_signed_url/3` reads the same global `client_email`, and only
ever signs `GET`. (That global mutation is worth its own ticket; do not widen its use here.)

The organization's own credential is already available and is all that is needed:

```elixir
Glific.GCS.get_secrets(org_id)["service_account"]   # JSON string
|> Jason.decode!()                                   # %{"client_email" => ..., "private_key" => ...}
```

Implement GCS V4 signing directly — canonical request, `GOOG4-RSA-SHA256` string-to-sign,
RSA-SHA256 over it with `:public_key.sign/3` on the PEM key, hex signature in `X-Goog-Signature`.
Sign `host` and `content-type` only.

- `signed_put_url(org_id, object_name, content_type, expires_in)` → `{:ok, url} | {:error, term}`
- Expiry **5 minutes**. It is handed out one action before it is used.
- The private key must never be logged, never appear in an error tuple, and never reach
  AppSignal. `Glific.SafeLog` strips `Tesla.Env.__client__` and knows nothing about this — do not
  rely on it. Return `{:error, :signing_failed}` and log without the term.

## 2 — `POST /api/v1/web_channel/upload-url`

Same `:web_channel_api` pipeline, so it inherits the token check and the flag gate.

Validates, before signing:
- `type` in `~w(image audio video document)`
- `content_type` via `Messages.valid_media_content_type?/2`
- `size` a positive integer within `Messages.media_size_limit(type)`

Then derives the extension from the content type (never the caller), names the object as a bare
UUID, signs, and returns `upload_url`, the final `url`, `content_type` and `expires_in`.

**Delete the multipart action, the route, and the endpoint's 110 MB parser override.** Leaving it
alongside keeps the proxied path alive and reintroduces the pre-auth buffering this removes.

## 3 — Size is enforced when the message arrives, not at signing

A signed URL cannot reliably bind an upload's size: `x-goog-content-length-range` belongs to POST
policy documents, not PUT signed URLs, and `content-length` is a forbidden header for `fetch`, so
the browser sets it itself. The declared `size` therefore bounds the honest case only.

Enforce it authoritatively in `handle_in("new_media_message", ...)`, after `issued_url?/2` and
before persisting: read the object's metadata — `GET storage.googleapis.com/storage/v1/b/<bucket>/o/<object>`
returns `size` and `contentType` **without** transferring the file — and reject when either
exceeds or contradicts what was signed for.

**Do not use `Messages.validate_media/2` here.** It does a full `Tesla.get` of the URL, i.e. it
downloads the whole file, which is precisely the cost this ticket exists to remove.

Reply `{:error, %{reason: "media_too_large"}}` / `"invalid_media_url"` and do not persist. An
orphaned object stays in the bucket; note it and leave cleanup to a lifecycle rule rather than a
delete call on the socket path.

## 4 — CORS is a hard prerequisite

A browser PUT to `storage.googleapis.com` is cross-origin, so **each organization's bucket needs a
CORS configuration** admitting `PUT` from its web channel origin with the `Content-Type` header.
Without it every upload fails in the browser with an opaque CORS error and nothing reaches Glific
to log.

This is now a third enablement precondition, alongside the `verify_otp` HSM template and the GCS
credential itself. Add it to `Glific.GCS.refresh_gcs_setup/1` if the credential permits, and
provide a `Glific.Scripts.*` helper per the admin-script pattern either way. Document it in the
PR whichever route is taken.

## 5 — Widget

`uploadMedia(file, type)` becomes two steps: request the URL, then `PUT` the file to it with the
returned `Content-Type`. The error mapping keys on the same server `code`s; add a code for a
signing failure. A CORS or network failure on the PUT must present as an upload failure the user
can retry, not a silent stall — and the retry must re-request the URL, since the old one expires
in five minutes.

Ticket 10's contract still holds: an upload failure retries the upload, a socket-push failure
retries only the push, and neither loses the caption.

## Acceptance criteria

- [ ] No file byte passes through Glific. Confirm by uploading with the Phoenix log open.
- [ ] Two organizations signing concurrently each get a URL for their own bucket, signed by their
      own service account. This is the one that global Goth state would break.
- [ ] A signed URL expires and stops working.
- [ ] A signed URL cannot be used for a different object name or content type than it was signed for.
- [ ] An object larger than the type's limit is refused when the message arrives, and no message row
      is created.
- [ ] An unauthenticated `upload-url` request is refused, and no signature is produced.
- [ ] The multipart route is gone, and so is the 110 MB parser override.
- [ ] No private key appears in any log, error tuple or AppSignal event.

## Reviewer must verify personally

- [ ] Watch the network tab: the PUT goes to `storage.googleapis.com`, not to Glific.
- [ ] Confirm the signing path touches no global Goth state — grep for `Goth.Config.set` and check
      the new module is not in that call graph.
- [ ] Try a signed URL against a different object name and confirm GCS rejects it.
- [ ] Confirm CORS is configured on a real bucket before calling this done; a green test suite
      cannot see a CORS failure.
