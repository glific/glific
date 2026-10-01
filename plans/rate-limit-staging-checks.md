# Rate limiting — staging verification

What to exercise on staging before this reaches production. Every HTTP request is touched by at
least one change, so section 1 applies to the whole surface; sections 2 onward are the specific
behaviours that are new or could regress.

Two infrastructure facts were confirmed rather than assumed: Gigalixir **appends** to
`x-forwarded-for`, and nothing parses log lines positionally.

## 1. Every request

| Change | What to look for |
|---|---|
| Logger format is now `$time [$level] $metadata$message` | Level reads before the metadata, and lines carry `remote_ip=` |
| `RemoteIp` restricted to `x-forwarded-for` and moved near the top of the endpoint | `remote_ip=` is a plausible, **varying** client address |
| Tenant resolution reads `Glific.Partners.OrganizationIndex` instead of querying | Every organization still reaches its own host |

**The one measurement that matters here:** make an external request and confirm `remote_ip=` is
your own public address. If every line carries the *same* address, everything keyed on the caller —
the unrouted bucket, the IP blocklist, OTP throttling, `users.last_login_from` — is attributing
traffic to the proxy instead. Check this first.

Already confirmed on staging: external requests do log a public address, and some traffic arrives
from inside Gigalixir's network carrying only a private one. That second case is expected, and
those callers are exempt from the unrouted limit — see section 2.

A second, cheaper check: `GET /aws.env` with a spoofed `X-Real-IP` and `X-Client-IP` must log the
real address, not the spoofed one.

## 2. New rejection behaviour

| Request | Expected | Was |
|---|---|---|
| Any path the router does not match | `404`, then `429` after `RATE_LIMIT_API_UNROUTED` (default 60) per minute per address | `404`, never throttled |
| Any path on a `Host` that resolves to no active organization | `404`, empty body | `403 Unauthorized` |
| Any path from an address in `BLOCKED_IPS` | `404`, empty body | n/a — new |
| An unrouted path from a **private** address (a health check) | `404` forever, never `429` | n/a — new |

The last row is the exemption: `RemoteIp` skips reserved ranges, so a private `remote_ip` means the
caller is inside the platform. They are indistinguishable from one another, so one bucket would
throttle them collectively, and refusing a health check is how an instance gets restarted.

Each limit's count is an environment variable read at boot: `RATE_LIMIT_API_UNROUTED`,
`RATE_LIMIT_API_UNAUTHENTICATED`, `RATE_LIMIT_API_AUTHENTICATED_PER_SEC` and the
`RATE_LIMIT_WEB_CHANNEL_*` family. Every limit is defined in `config/runtime.exs` and nowhere else;
windows are fixed there, so there is no period variable. `RATE_LIMIT_API_AUTHENTICATED_PER_SEC` replaces `MAX_RATE_LIMIT_REQUEST`, so **that variable has
to be renamed in the Gigalixir config or the authenticated limit silently falls back to its default
of 80/s.** `BLOCKED_IPS` is comma separated and a malformed entry refuses to boot, which is worth
testing once.

**The unauthenticated bucket changed shape.** It was keyed on address *and path*, giving each
endpoint its own budget; it is now the address alone, so one address shares a single budget across
every unauthenticated endpoint. The default was raised from 50 to 300 to compensate, but an office
behind one egress address is the case to watch: log in, request OTPs and use the web channel from
one address in quick succession and confirm nothing 429s. The per-phone budget is removed, so
`RATE_LIMIT_API_PHONE` can be deleted from Gigalixir.

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
| `/web_socket` connects | throttled per address, and in total across the node |

The socket is worth its own pass, because it reads the forwarded header itself rather than going
through `RemoteIp` in the plug pipeline. Confirm two distinct client addresses get distinct
budgets — if they share one, the deployed `x-forwarded-for` is not what we think it is — and that
exhausting the node-wide total answers **503**, not 403.

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

## 5. The web channel's own budgets

It no longer shares the staff budget, because it is embedded on public sites where a school or
carrier NAT fronts many unrelated beneficiaries. Exercise each from a real browser session.

| Surface | Limit | What to confirm |
|---|---|---|
| `branding`, `request-otp`, `verify-otp`, `renew-token` | 1200/min per address | A classroom signing in together is not refused |
| Sign-in OTP | 1 per 30s per phone, 100/min per address | The per-phone throttle still fires; the per-address one does not, for a class |
| `POST /web_channel/upload-url` | 6/min per contact, 60/min per address, 120/min overall | A contact sending several attachments is fine; the overall cap exists but should not be reachable in normal use |
| Socket connects | 120/min per address, 1000/min overall | Two addresses get separate budgets; exhausting the total answers **503** |
| Socket messages | 20 per 10s per contact | Ordinary conversation is unaffected |

The upload endpoint had no limit at all before, and each call mints a writable grant into the
organization's GCS bucket, so it is the one worth a deliberate try.

## 6. Observability

A breach logs at **warning** with the limit's name — `Rate limit exceeded: rate_limit_api_unrouted` —
and increments the AppSignal counter `rate_limit_exceeded`, tagged with that name. Confirm both
appear after deliberately tripping something, and that the counter's tags contain the limit name
only: never an address, phone number or contact id.

## 7. Regression risk from the rate limiter

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

## 8. Not affected — do not spend time here

- Websockets and longpoll for the staff API: `/socket` and `/live`. Socket dispatch halts before any
  plug added here, so subscriptions and LiveView bypass all of it, and their log lines carry no
  `remote_ip`. `/web_socket` bypasses the plugs too, but is **not** unaffected — it does its own
  limiting, so see sections 3 and 5.
- The authenticated budget's *shape*: still one bucket per signed-in user, now 80/s rather than
  180/min. Its variable changed name, which section 2 covers.

## Known wrinkle, not a defect

`favicon.ico` and `robots.txt` are declared static but `priv/static` only contains `assets/`, so
requests for them fall through to the scan bucket. A browser pointed at the API host spends a
couple of its 60 tokens a minute on them. Harmless at the default, worth knowing if the limit is
ever lowered.
