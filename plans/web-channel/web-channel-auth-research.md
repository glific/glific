# Embeddable Chat Auth — How Intercom / Zendesk / Crisp / Sunshine Do It

Research input for the Glific web-channel tech design. Question: when an NGO embeds Glific's chat
on **their own** site/app, how should the end-user be authenticated, and how should the widget be
delivered? The mature SaaS support platforms have converged on a small number of patterns; this
maps them onto Glific's locked decisions (separate frontend repo, `web.<shortcode>.glific.com`
subdomain, 30-day session, phone+OTP for the hosted case).

Sources are official developer docs (Intercom, Zendesk, Crisp) plus the Sunshine Conversations
API. Where a doc didn't confirm a detail, it's marked **[unverified]** rather than asserted.

---

## The one finding that matters most

**All four platforms authenticate an *identified* end-user the same way: the customer's backend
signs a token with a shared secret that never touches the browser; the vendor verifies the
signature and trusts the identity.** They differ only in token format and transport.

| Platform | Token format | Signed with | Identifying claim | How it reaches the widget |
|---|---|---|---|---|
| **Intercom** (current) | **JWT, HS256** | Messenger API Secret | `user_id` (required) | `Intercom("boot", { intercom_user_jwt })` |
| **Intercom** (legacy) | HMAC-SHA256 digest (`user_hash`) | API Secret | hash of `user_id`/`email` | `user_hash` in boot — **now deprecated**, still accepted |
| **Zendesk Messaging** | **JWT** | Signing key (admin-created, ≤10) | `external_id` + `scope:"user"` | `messenger("loginUser", cb→JWT)` |
| **Crisp** | Signed email (Identity Verification) + per-user **token** (session continuity) | secret key, backend-only | email | `$crisp` config at boot |
| **Sunshine Conv.** | app-scoped **JWT** or API key (basic auth) | API key secret | server-to-server only | n/a — API layer, not a widget claim |

**Takeaway for Glific:** this is exactly the "delegated auth" we flagged as a vague future item.
It is not vague — it's a standardized pattern. When an NGO embeds Glific and their user is already
logged into the NGO's site, the NGO's backend mints a signed token asserting "this is contact
+91XXXX", Glific verifies it against a per-org shared secret, and **no OTP is needed.** OTP is only
for Glific's *own* hosted page where there is no NGO backend to vouch.

Two design notes fall straight out:

- **Intercom moved HMAC → JWT and is deprecating HMAC.** So don't build the older raw-HMAC
  `user_hash` scheme even though it's simpler; **build JWT (HS256) from day one.** It's the same
  secret and same crypto, but carries structured claims (id, expiry, custom attributes) and is
  where the industry has settled. This directly answers the "should Glific adopt the HMAC pattern"
  question: adopt the *idea* (backend-signed identity), in its *current* form (JWT).
- **Email collisions are rejected.** Zendesk rejects a JWT whose email already maps to a different
  external_id. Glific's analogue: a delegated token asserting a phone that belongs to a different
  contact must fail closed. Phone is Glific's identity key, so this is naturally enforceable.

---

## Widget delivery: snippet-that-injects-an-iframe

The universal shape is a **small JS snippet (script loader) that asynchronously injects an
iframe.** Intercom's Messenger renders inside an iframe (`.intercom-messenger-frame > iframe`); the
snippet exposes the `window.Intercom(...)` JS API on the host page. Crisp is the clearest because it
offers **both** explicitly:

- **JS snippet** → global `$crisp` object: programmatic control, richer host-page integration.
- **Raw iframe** → `https://go.crisp.chat/chat/embed/?website_id=<id>`: drop-in, maximal isolation,
  less control.

**Trade-off, decided by these platforms in favour of iframe-under-a-snippet:**

| | iframe | inline snippet (no iframe) | Web Component |
|---|---|---|---|
| CSS isolation | Total (separate document) | None — host styles leak both ways | Shadow DOM (good, not total) |
| Security sandbox | `sandbox` attr, origin boundary | Runs in host's origin — risky | Same origin as host |
| CSP friendliness | Host allowlists one frame-src | Host must allow your scripts inline | Same as snippet |
| Host-page JS API | via `postMessage` only | Direct | Direct |

The consensus — snippet loads, iframe renders, `postMessage` bridges them — is what Glific should
copy. It maps cleanly onto the **separate frontend repo + subdomain** decision: the iframe's `src`
is `web.<shortcode>.glific.com`, so the chat runs in Glific's own origin (its cookies, its CSP, its
token storage) while embedded on the NGO's page. Origin isolation is *free* the moment it's an
iframe pointed at the subdomain — the subdomain decision and the embeddability decision reinforce
each other.

---

## Realtime transport

- **Crisp RTM:** WebSocket over **Socket.IO**. After connect you have **~10 seconds to
  authenticate** by emitting an `authentication` event with a token id + key and the event
  namespaces you want. REST performs actions; RTM delivers events/acks. The RTM endpoint URL is
  fetched from REST first (`Get Connect Endpoints`) — i.e. **connection discovery precedes the
  socket**, useful for routing/sharding.
- **Sunshine Conversations:** server-side **webhooks** are the realtime-out mechanism for building
  custom clients — you receive message events and render them yourself.
- **Intercom/Zendesk:** the widget's own transport is internal (not a documented public socket);
  realtime-for-integrations is webhooks.

**For Glific:** our Phoenix Channel already gives us what Crisp bolts onto Socket.IO — a joined
topic with an auth step at connect (the token in connect params). Two patterns worth stealing:
(1) **authenticate promptly after connect with a bounded window**, matching Crisp's 10s rule —
reject unauthenticated sockets fast; (2) **endpoint discovery before connect** — a cheap REST call
that hands back the socket URL, which is exactly where multi-node session routing would later live
without changing the client contract.

---

## Public API surface (build-your-own-UI)

**Sunshine Conversations is the reference for "headless chat as a product."** Its Core API is
**app-scoped** (one app = one customer workspace): an app-scoped API key or app-scoped JWT grants
access to that app's integrations, webhooks, users, and conversations — server-to-server only,
never shipped to a browser. Customers build custom clients by calling the send API and consuming
inbound **webhooks**. Two auth methods: **basic auth** (key id = username, secret = password) or
**JWT signed with an API key**. There's also a broader **account scope** for cross-app operations.

**For Glific:** this validates "the socket/REST contract *is* the public API." The scope split maps
directly to multi-tenancy — an **org-scoped API credential** is the natural unit (Sunshine's "app"
= Glific's "organization"). Server-to-server org credentials for the API; short-lived signed
per-contact tokens for the browser. Never one in place of the other.

---

## Multi-tenancy & domain allowlisting

- **Intercom Trusted Domains:** the Messenger only loads on an explicit allowlist of
  domains/subdomains, **wildcards supported** (`*.intercom.com`). Off-list → Messenger refuses to
  load ("This domain is not allowed for the Intercom Messenger").
- **Workspace/website scoping:** Intercom `app_id`, Crisp `website_id`, Sunshine `app` — a public,
  non-secret key in the snippet that scopes the widget to one workspace. **Non-secret by design**;
  security comes from the signed identity token and the domain allowlist, *not* from hiding this id.

**For Glific:**

- The public scoping key is the **org shortcode / subdomain** — already the case.
- Add a **per-org allowed-origins list** (the CORS/embedding allowlist), wildcards supported, so an
  org self-hosting on `their-ngo.org` adds it explicitly. This is precisely the "whitelist their
  domains" item from the requirements dump, and Intercom's model says implement it as a
  first-class, wildcardable org setting — not hardcoded.
- Don't rely on the shortcode being secret. It isn't, in any of these systems.

---

## Session longevity — the nuance that resolves the 30-day decision

Here's the tension worth surfacing in the design doc. **Intercom recommends a *short* JWT expiry
(as little as ~5 minutes)** — but that short token is the *identity proof*, not the *session*. The
long-lived session is a **separate cookie**, whose lifetime Intercom controls via a
`session_duration` claim. Crisp draws the same line even more sharply: a backend-generated
**per-user token** provides **session continuity** — "recover the same conversation even when they
change browser, switch device, or clear cookies" — decoupled from any single short-lived credential.

So the mature pattern is **two layers**:

1. a **short-lived, re-signable identity token** (minutes) that proves who you are, and
2. a **long-lived session** (days) that keeps you in the same conversation.

**Glific's 30-day decision should be read as layer 2, not layer 1.** A 30-day *bearer token that is
itself the only credential* is the risky object I flagged — if it leaks, it's a 30-day master key
with no revocation. The safer construction that still delivers "don't make her log in for 30 days":

- Hosted case: OTP verifies once → mint a **30-day *session*** (server-side session record or a
  rotating refresh token), from which short-lived access tokens are derived. Revocable server-side;
  a leaked access token dies in minutes.
- Embedded case: the **NGO's short-lived signed JWT** is layer 1; Glific issues its own session as
  layer 2. The NGO controls identity; Glific controls session.

This is strictly better than a raw 30-day JWT and costs only a session table you'll want anyway for
the "logout / revoke device" story and for DPDP-style data-subject requests.

---

## Abuse protection on the public endpoint

The docs are thin on published rate-limit numbers (expected — vendors don't advertise them), but
the structural pattern is consistent and matches what we already decided:

- The **anonymous/unauthenticated** surface (widget first load, and for Glific `request_otp`) is
  the throttled one — per-IP and, for Glific, per-phone, because each OTP spends the NGO's WhatsApp
  balance.
- The **identified** surface is protected by the signed token, which makes bulk abuse expensive
  (you'd need the NGO's secret or a valid OTP).

Nothing here contradicts the "per-contact rate limit, no per-org circuit breaker" call — but it
reinforces that the OTP-request endpoint is the one place per-contact limiting can't help (no
contact yet), so per-IP + per-phone there is non-negotiable.

---

## Recommendations for Glific, ranked

1. **Adopt backend-signed JWT (HS256) for delegated/embedded auth, per-org shared secret.** This is
   the Intercom-current / Zendesk / Sunshine consensus. Skip raw HMAC `user_hash` — it's the
   deprecated form of the same idea. Claim set: `phone` (identity), `org`, short `exp`. Reject a
   token whose phone maps to a different contact (Zendesk's collision rule).
2. **Two auth modes, one channel:** OTP for Glific-hosted; delegated JWT for NGO-embedded. Same
   downstream contact + socket; only the front door differs.
3. **Ship as snippet-injects-iframe, iframe `src` = `web.<shortcode>.glific.com`.** Origin
   isolation for free; `postMessage` bridge for host-page control. The subdomain decision already
   bought this.
4. **Split session from identity.** 30-day *session* (revocable, server-side) issued from a
   short-lived credential — not a 30-day bearer JWT. Needs a session/device table.
5. **Per-org allowed-origins allowlist, wildcardable** (Intercom Trusted Domains). This *is* the
   "whitelist their domains" requirement; make it a first-class org setting.
6. **Org-scoped server-to-server API credential** (Sunshine app-scope model) for the headless/API
   play, distinct from browser tokens. Inbound via signed webhooks.
7. **Authenticate the socket promptly after connect with a bounded window** (Crisp's 10s) and
   **discover the socket URL via a pre-connect REST call** (room to add multi-node routing later
   without a client change).

## Security pitfalls flagged by the sources

- **Secret in the browser** — every platform screams this: signing secret / API secret is
  backend-only. Glific's per-org JWT secret must never reach the widget bundle (which lives in a
  *public* repo — extra care).
- **Raw long-lived bearer tokens** — a 30-day JWT with no revocation is the anti-pattern; use a
  session layer.
- **Trusting the workspace id for security** — `app_id`/`website_id`/shortcode are public; security
  is the signed token + domain allowlist, never the id.
- **Email/identity collision** — must fail closed (Zendesk). For Glific, phone collision across
  contacts.
- **Deprecated-but-accepted auth** — Intercom still accepts `user_hash`; don't let "still works"
  become "what we built on." Start on JWT.

## Sources
- Intercom — [Authenticating users in the Messenger with JWTs](https://www.intercom.com/help/en/articles/10589769-authenticating-users-in-the-messenger-with-json-web-tokens-jwts)
- Intercom — [Identity Verification (deprecated HMAC user_hash)](https://www.intercom.com/help/en/articles/183-set-up-identity-verification-for-web-and-mobile-deprecated)
- Intercom — [List trusted domains for your Messenger](https://www.intercom.com/help/en/articles/4418-list-trusted-domains-you-use-with-your-messenger)
- Intercom — [Using Intercom with Content Security Policy](https://www.intercom.com/help/en/articles/3894-using-intercom-with-content-security-policy)
- Zendesk — [Authenticating end users for messaging](https://support.zendesk.com/hc/en-us/articles/4411666638746-Authenticating-end-users-for-messaging)
- Zendesk/Sunshine — [Sunshine Conversations API Reference](https://docs.smooch.io/rest/v1/)
- Zendesk/Sunshine — [API Quickstart (current)](https://developer.zendesk.com/documentation/conversations/getting-started/api-quickstart/)
- Crisp — [RTM API](https://docs.crisp.chat/guides/rtm-api/)
- Crisp — [Web Chat SDK: Identity Verification](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/)
- Crisp — [Web Chat SDK: Session Continuity](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/session-continuity/)
- Crisp — [Embed the chatbox in an iFrame](https://help.crisp.chat/en/article/how-to-embed-the-crisp-live-chat-chatbox-in-an-iframe-bkfh98/)
