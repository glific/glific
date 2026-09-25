# Rate limiting — staging verification

What to exercise on staging before this reaches production. Every HTTP request is touched by at
least one change, so section 1 applies to the whole surface; sections 2 onward are the specific
behaviours that are new or could regress.

Two infrastructure facts were confirmed rather than assumed: Gigalixir **appends** to
`x-forwarded-for`, and nothing parses log lines positionally.

## 1. Every request

| Change | What to look for |
|---|---|
| Logger format is now `$time [$level] $metadata$message` | Level reads before the metadata; lines carry `status=` |
| `RemoteIp` restricted to `x-forwarded-for` and moved near the top of the endpoint | `remote_ip=` is a plausible, **varying** client address |
| Tenant resolution reads `Glific.Partners.OrganizationIndex` instead of querying | Every organization still reaches its own host |

**The one measurement that matters here:** if `remote_ip=` is the *same* address on every request,
a Gigalixir hop is appending a public address and `RemoteIp` is selecting it. Everything else in
this change that keys on the client address — the scan bucket, the IP blocklist, OTP throttling,
`users.last_login_from` — is then attributing traffic to the proxy. Check this first.

A second, cheaper check: `GET /aws.env` with a spoofed `X-Real-IP` and `X-Client-IP` must log the
real address, not the spoofed one.

## 2. New rejection behaviour

| Request | Expected | Was |
|---|---|---|
| Any path the router does not match | `404`, then `429` after `RATE_LIMIT_GLOBAL` (default 60) per minute per address | `404`, never throttled |
| Any path on a `Host` that resolves to no active organization | `404`, empty body | `403 Unauthorized` |
| Any path from an address in `BLOCKED_IPS` | `404`, empty body | n/a — new |

All limits are environment variables read at boot: `RATE_LIMIT_GLOBAL`,
`RATE_LIMIT_UNAUTHENTICATED`, `RATE_LIMIT_AUTHENTICATED` and `RATE_LIMIT_PERIOD_SECONDS`.
`RATE_LIMIT_AUTHENTICATED` replaces `MAX_RATE_LIMIT_REQUEST`, so **that variable has to be renamed
in the Gigalixir config or the authenticated limit silently falls back to its default of 180.**
`BLOCKED_IPS` is comma separated and a malformed entry refuses to boot, which is worth testing
once.

**The unauthenticated bucket changed shape.** It was keyed on address *and path*, giving each
endpoint its own budget; it is now the address alone, so one address shares a single budget across
every unauthenticated endpoint. The default was raised from 50 to 300 to compensate, but an office
behind one egress address is the case to watch: log in, request OTPs and use the web channel from
one address in quick succession and confirm nothing 429s. The per-phone budget is now charged *in
addition to* the address budget rather than instead of it, so rotating phone numbers no longer buys
extra attempts.

## 3. Endpoints that read the client address

These behave differently if `remote_ip` resolves differently than before. Exercise each and confirm
the recorded or throttled address is the real caller.

| Endpoint | Why it matters |
|---|---|
| `POST /api/v1/registration/send-otp` | throttles on `send_otp:<ip>` |
| `POST /api/v1/web_channel/request-otp` | throttles on `web_channel_send_otp_ip:<ip>` |
| `POST /api/v1/session` | writes `users.last_login_from` |
| `POST /api/v1/onboard/setup` | records the originating address |
| `/gupshup`, `/gupshup-enterprise`, `/maytapi` | allowlisted on the provider's published addresses |

The BSP webhooks are the highest-consequence item on this list: they are how inbound WhatsApp
arrives. Their filter reads `x-forwarded-for` directly and is unchanged, but confirm messages still
flow end to end.

## 4. Actions that rebuild the organization index

Each of these must leave the organization reachable on its host **immediately**, not after a minute.

- `updateOrganization` — especially changing **shortcode** or **status**
- `deleteOrganization`
- `createCredential`, `updateCredential`
- Suspending and reactivating an organization from the SaaS console
- Gupshup credential verification

A shortcode rename is the case this change got wrong once and now has a regression test; it is still
worth doing by hand, because the failure mode is a hard 404 for that tenant.

## 5. Regression risk from the rate limiter

It engages only for paths the router does not match, so legitimate traffic should never see it. The
ways that could be wrong:

- **`HEAD` on any real route** — uptime monitors and link previewers. `Plug.Head` rewrites `HEAD`
  to `GET` after the limiter, so the limiter maps it itself.
- **`OPTIONS` preflights**, particularly `/flow-editor/*` with per-flow UUIDs in the path. The
  frontend preflights each distinct URL. A throttled preflight would surface in the browser as an
  opaque CORS failure rather than a rate limit, because `CORSPlug` runs after the limiter.
- **A full frontend session from one office address** — several staff behind one NAT egress is the
  realistic worst case.
- **Percent-encoded paths**, e.g. `/%61pi/v1/session`, must still be treated as matched.

## 6. Not affected — do not spend time here

- Websockets and longpoll: `/socket`, `/live`, `/web_socket`. Socket dispatch halts before any plug
  added here, so subscriptions, LiveView and the web channel bypass all of it. They also therefore
  carry no `remote_ip` in their log lines.
- Rate limiting for authenticated API users: the `:api` pipeline behaviour is unchanged.

## Known wrinkle, not a defect

`favicon.ico` and `robots.txt` are declared static but `priv/static` only contains `assets/`, so
requests for them fall through to the scan bucket. A browser pointed at the API host spends a
couple of its 60 tokens a minute on them. Harmless at the default, worth knowing if the limit is
ever lowered.
