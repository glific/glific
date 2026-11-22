# Research — Telegram and RCS integration

**Captured:** 2026-08-28 · **Docs snapshot:** Telegram Bot API **10.3** (dated 2026-08-24)

Source material for [tech-design.md](../tech-design.md) §3. That section is the distillation; this
file holds the citations, the exact limits, and the items that could **not** be verified.

> **Reading rule.** Every factual claim about the Telegram or RCS/RBM APIs carries a primary-source
> URL. Items marked **UNVERIFIED** could not be confirmed from primary docs and were *not* guessed —
> a wrong API claim in an engineering doc is worse than an acknowledged gap.

---

## 0. Codebase grounding

| Fact | Location |
|---|---|
| Inbound org resolution is by **subdomain**, globally, before any provider code runs | `lib/glific_web/plugs/subdomain_plug.ex`, wired at `lib/glific_web/endpoint.ex:79` |
| Webhooks `forward` to per-provider Shunt plugs, which rewrite `path_info` and re-dispatch | `lib/glific_web/router.ex:124-126`, `lib/glific_web/providers/gupshup/plugs/shunt.ex` |
| Send resolves **one handler per organisation** from `services["bsp"]`, from a single `organizations.bsp_id` FK | `lib/glific/communications.ex:13`, `lib/glific/partners.ex:725` |
| Credentials already keyed by provider **shortcode** and encrypted — `services["telegram"]` works today | `lib/glific/partners.ex:745`, `lib/glific/partners/credential.ex:38` (`Glific.Encrypted.Map`) |
| `messages.type` is a **Postgres enum**; `channel` is varchar | `lib/glific/enums/ecto_enums.ex:67` |
| `contacts` unique on `(phone, organization_id)`; `contact_type` defaults to `"WABA"` | `lib/glific/contacts/contact.ex:136`, `:88` |
| **No cross-channel fallback mechanism exists anywhere** in `lib/glific` | verified by exhaustive grep |

**The most important precedent.** The web channel did not get a clean dispatch clause. It got a
parallel context (`Glific.Communications.WebMessage`) plus a bypass in `Messages.check_for_hsm_message/2`:

```elixir
defp check_for_hsm_message(%{channel: "web"} = attrs, _contact),
  do: send_web_channel_message(attrs)
```

Channel #2 cost a bypass clause. Channel #3 and #4 will each want their own unless `dispatch` is
built first.

---

## 1. Telegram — direct integration

### 1.1 Transport

Webhook and long polling are **mutually exclusive** ([getting-updates](https://core.telegram.org/bots/api#getting-updates)).
Undelivered updates are dropped after **24 hours**. Webhook is correct for Glific — long polling
would need a supervised GenServer per org holding an open `getUpdates` connection.

Hard constraints ([webhooks guide](https://core.telegram.org/bots/webhooks), [setWebhook](https://core.telegram.org/bots/api#setwebhook)):

- **Ports: 443, 80, 88, 8443 only.** *"Other ports are not supported and will not work."*
- **TLS 1.2+ mandatory.** SSLv2/3, TLS 1.0/1.1 not supported. Self-signed allowed via `certificate`.
- **IPv4 only** — *"IPv6 is currently not supported for webhooks."*
- **Redirects not supported.** Wildcard certificates *"may not be supported"* ([FAQ](https://core.telegram.org/bots/faq#i-m-having-problems-with-webhooks)) — ⚠️ Glific's `*.glific.com` wildcard cert is a live risk to validate.
- Source subnets **`149.154.160.0/20`** and **`91.108.4.0/22`**, with *"Our IP-range might change in the future."*
- `secret_token` arrives in header **`X-Telegram-Bot-Api-Secret-Token`**, 1–256 chars, `A-Z a-z 0-9 _ -`.
- `max_connections` 1–100, default 40.
- Retries: *"we will repeat the request and give up after a reasonable amount of attempts."* Exact count/backoff **UNVERIFIED**.
- You may answer the webhook POST with a method call ([making-requests-when-getting-updates](https://core.telegram.org/bots/api#making-requests-when-getting-updates)) — but *"It's not possible to know that such a request was successful."*

**One webhook URL per bot: UNVERIFIED** as an explicit statement; inferred from `setWebhook` taking a single `url`.

**Per-org routing is already solved** — `SubdomainPlug` populates `organization_id` from the Host
header, so each NGO sets `https://<shortcode>.glific.com/telegram`. No lookup table, no path tokens.

### 1.2 Credential

Token format `123456:ABC-DEF...` ([authorizing-your-bot](https://core.telegram.org/bots/api#authorizing-your-bot)).
Whether the numeric prefix is the bot's user id is **UNVERIFIED**. Obtained via @BotFather `/newbot`,
rotated via `/token` ([features](https://core.telegram.org/bots/features#generating-an-authentication-token)) —
whether `/token` instantly invalidates the old one is **UNVERIFIED**.

**One token = one bot.** No organisation concept; a bot belongs to a Telegram *user account*.
Ownership transfer is permanent and gives the new owner *"full control… access the bot's messages"*.

Credential home is clean: `providers` row with `shortcode: "telegram"`, per-org
`credentials.secrets["bot_token"]`, already encrypted. **No schema change.**

### 1.3 Identity — the crux

`User.id`: *"at most 52 significant bits, so a 64-bit integer or double-precision float type are safe"* ([User](https://core.telegram.org/bots/api#user)).

⚠️ **Permanence is UNVERIFIED.** The docs say "unique identifier" but make no permanence guarantee —
in pointed contrast to `File.file_unique_id`, where they *do* commit: *"supposed to be the same over
time and for different bots"* ([File](https://core.telegram.org/bots/api#file)).

`User.username` is **Optional**; changeability for end users **UNVERIFIED**. **Do not key on username.**

`Chat.id`: signed, ≤52 significant bits. **`chat.id == user.id` in private chats is UNVERIFIED** —
community folklore, never stated. Telegram provides `ChatJoinRequest.user_chat_id` /
`BusinessConnection.user_chat_id` for exactly this. **Recommendation: persist `chat.id` from inbound
updates; never synthesise it from `user.id`.** Note `ResponseParameters.migrate_to_chat_id` — group
ids change on supergroup migration.

**`user.id` is global, not per-bot.** Established by three passages that only make sense under a
global id space: [SharedUser](https://core.telegram.org/bots/api#shareduser) (*"unless the user is
already known to the bot by some other means"*), `Contact.user_id`, and `tg://user?id=` deep links
([InlineKeyboardButton](https://core.telegram.org/bots/api#inlinekeyboardbutton)). Contrast `file_id`,
which Telegram **explicitly** scopes per bot — they state bot-scoping where it exists.

**Phone number: only with an explicit tap.** `KeyboardButton.request_contact` → `Message.contact.phone_number`
([KeyboardButton](https://core.telegram.org/bots/api#keyboardbutton)). Private chats only. No API reads a phone without a tap.

> ### Where the "cheap channel" claim first breaks
> `contacts` is unique on `(phone, organization_id)` and a Telegram user has no phone.
> **`contact_identities` is a hard prerequisite for Telegram, not an enhancement.** The web channel
> dodged this by inventing a phone+OTP flow; Telegram has no such escape hatch.
>
> Secondary: `searches.ex:179,259` filters `contact_type in ["WABA","WABA+WA"]`, so a Telegram
> contact is **silently invisible in the staff inbox** until that widens.

### 1.4 Sending surface

Three file-input forms ([sending-files](https://core.telegram.org/bots/api#sending-files)): `file_id`
(no limits), HTTP URL (5 MB photos / 20 MB other), multipart (10 MB photos / 50 MB other).
**50 MB send / 20 MB download** ([FAQ](https://core.telegram.org/bots/faq#how-do-i-download-files)).

| `MessageBehaviour` callback | Telegram method | Notes |
|---|---|---|
| `send_text` | `sendMessage` | `text` **1–4096 chars** |
| `send_image` | `sendPhoto` | ≤10 MB; `caption` 0–1024 |
| `send_audio` | `sendAudio` **or** `sendVoice` | ⚠️ ambiguous — see below |
| `send_video` | `sendVideo` | MPEG4; `supports_streaming` |
| `send_document` | `sendDocument` | URL sending works only for **.PDF and .ZIP** |
| `send_sticker` | `sendSticker` | .WEBP/.TGS/.WEBM |
| `send_interactive` | `sendMessage` + `reply_markup` | not a separate method |
| *(no callback)* | `sendLocation`, `sendVenue`, `sendContact`, `sendAnimation`, `sendVideoNote`, `sendMediaGroup`, `sendChatAction` | |

⚠️ **`send_audio` mapping ambiguity.** `sendAudio` renders in the music player (.MP3/.M4A);
`sendVoice` renders as a playable voice message (.OGG/OPUS). Glific's WhatsApp voice-note flows mean
`sendVoice`, but `MessageBehaviour` has one `send_audio/2` and `messages_media` carries no is-voice
discriminator. Either sniff MIME or add one.

`sendChatAction` (typing indicators, 5 s TTL) has **no `MessageBehaviour` callback** — the behaviour is send-only.

**Rate limits** ([FAQ](https://core.telegram.org/bots/faq#my-bot-is-hitting-limits-how-do-i-avoid-this)), verbatim:
**1 message/second to a single chat** · **20 messages/minute in a group** · **~30 messages/second overall**.
429s carry `parameters.retry_after` ([ResponseParameters](https://core.telegram.org/bots/api#responseparameters)).
⚠️ Telegram warns `error_code` *"contents are subject to change"* — key retry logic off the presence
of `retry_after`, not off literal `429`.

Glific fit: the `gupshup` Oban queue is plain `gupshup: 10` with no rate limiting. Oban Pro
`rate_limit` with `partition` is already used for `custom_certificate`, so a `telegram` queue can
express both caps. Config work, not architecture.

### 1.5 Interactive / rich

**Inline keyboards** ([InlineKeyboardMarkup](https://core.telegram.org/bots/api#inlinekeyboardmarkup)):
`callback_data` is **1–64 bytes** (*bytes*, not chars). Also `url`, `web_app`, `login_url`,
`copy_text` (≤256), `style` (`danger`/`success`/`primary`), `disabled`.

> ⚠️ **`answerCallbackQuery` is effectively mandatory** and has no home in the current architecture.
> *"Telegram clients will display a progress bar until you call answerCallbackQuery. It is,
> therefore, necessary to react by calling answerCallbackQuery even if no notification to the user
> is needed"* ([CallbackQuery](https://core.telegram.org/bots/api#callbackquery)).
>
> This is an **outbound API call triggered by an inbound event**, and it is not a message.
> `MessageBehaviour` is send-only plus parse-only; the ingest seam has no "acknowledge the provider" step.
>
> Also: *"Be aware that the message originated the query can contain no callback buttons with this
> data"* — `callback_data` is **not authenticated** against the current keyboard. Validate server-side.

**Reply keyboards**: a press *"will be sent as a message"* — indistinguishable from the user typing
that string. Cheaper (arrives via the ordinary text parser) but loses response-id fidelity.

**Mini Apps** ([webapps](https://core.telegram.org/bots/webapps)): arbitrary HTTPS HTML/JS. Return
paths — `sendData()` (≤4096 bytes) → `Message.web_app_data`, or `answerWebAppQuery`. Auth via
`initData` HMAC-SHA-256, keyed by HMAC of the bot token with constant `"WebAppData"`.
⚠️ Both `WebAppData` fields carry *"a bad client can send arbitrary data in this field."*

| Glific | Telegram | Fidelity |
|---|---|---|
| `quick_reply` | inline keyboard + `callback_query` | **Good** — ≤64 *bytes* of `callback_data` |
| `list` | inline keyboard rows, or reply keyboard | **Degraded** — no native sectioned list |
| `location_request_message` | `KeyboardButton.request_location` | **Good** (private chats only) |
| Blocks (`:blocks`) | **Mini App** | **Strong.** The one non-web channel that could render Blocks natively |

⚠️ **Max buttons / rows / buttons-per-row is UNVERIFIED** — unbounded `Array of Array`, no documented limit.

### 1.6 Media inbound

Arrives as `Message.photo` (Array of PhotoSize) / `document` / `voice` / `audio` / `video` /
`video_note` / `animation` / `sticker`. Albums arrive as **N separate updates sharing `media_group_id`**.

Every file object carries `file_id` (downloadable/reusable) and `file_unique_id` (*"same over time
and for different bots… Can't be used to download or reuse"*). **Use `file_unique_id` for dedupe,
`file_id` as the transient handle.**

`getFile` → `https://api.telegram.org/file/bot<token>/<file_path>`, *"guaranteed valid for at least 1
hour"*, **20 MB cap** ([getFile](https://core.telegram.org/bots/api#getfile)).

1. ⚠️ **The download URL embeds the bot token in the path.** Never log, persist, or forward. Extend `SafeLog`.
2. Expiry is a floor — cache the bytes, never the URL.
3. ⚠️ **`file_id` is bot-scoped** — *"can't be transferred from one bot to another"*. One bot per NGO
   means a shared asset must be re-uploaded per org. No cross-tenant media reuse.

### 1.7 Delivery receipts — **none exist for bots**

Evidence, strongest first:

1. **The exhaustive `Update` field list** ([Update](https://core.telegram.org/bots/api#update)) —
   `message`, `edited_message`, `channel_post`, `edited_channel_post`, `business_connection`,
   `business_message`, `edited_business_message`, `deleted_business_messages`, `guest_message`,
   `message_reaction`, `message_reaction_count`, `inline_query`, `chosen_inline_result`,
   `callback_query`, `shipping_query`, `pre_checkout_query`, `purchased_paid_media`, `poll`,
   `poll_answer`, `my_chat_member`, `chat_member`, `chat_join_request`, `chat_boost`,
   `removed_chat_boost`, `managed_bot`, `subscription`, `stopped_message_generation`.
   **No delivery- or read-status update type exists.**
2. Every send method returns a `Message` — a server-accepted ack, with no `status`/`delivered_at`/`read_at`.
3. The only "read" surface points the other way: `readBusinessMessage` marks *someone else's* message read.

Reaction updates exist but are not receipts, require the bot to be a chat **administrator**, and are
excluded from the default `allowed_updates`.

> ⚠️ **Architectural consequence.** `Glific.Enums.MessageStatus` is `[:sent, :delivered, :enqueued,
> :error, :read, :received, :contact_opt_out, :reached, :seen, :played, :deleted]`. On Telegram only
> `sent` and `error` can ever fire. Delivery-rate reports will show Telegram at 0% rather than N/A.
> The status model needs a per-channel notion of which states are **observable**.

### 1.8 Other constraints that matter

**Cannot initiate.** *"Users must start the bot first"* is **UNVERIFIED as an explicit sentence**, but
established by five passages: the `SharedUser` caveat; `WebAppUser.allows_write_to_pm`;
`LoginUrl.request_write_access`; the time-boxed exception `ChatJoinRequest.user_chat_id` (*"can use
this identifier for 5 minutes"*); and *"Users will see a Start button the first time they open a chat
with your bot."*

> ⚠️ **Bigger for Glific than the receipts gap.** Import a contact list, run a broadcast, fire a
> trigger — all assume you can message any contact you hold. On Telegram, acquisition is strictly
> **pull-based** via `t.me/<bot>?start=<payload>` (payload `A-Za-z0-9_-`, **≤64 chars**,
> [deep-linking](https://core.telegram.org/bots/features#deep-linking)). Broadcasts, triggers and
> contact import all need a Telegram-aware reachability precondition that does not exist.

**No 24-hour session window** for ordinary bots — confirmed by absence; the FAQ frames constraints
purely as throughput. **Exception:** Telegram Business connections *do* impose one —
`BusinessBotRights.can_reply` ([BusinessBotRights](https://core.telegram.org/bots/api#businessbotrights)).

> ⚠️ **The inverse problem to §1.3.** `Contacts.can_send_message_to?/2,3`
> (`lib/glific/contacts.ex:631-703`) gates every send on `contact.bsp_status ∈ [:session_and_hsm,
> :session]` and emits *"Sorry! 24 hrs window closed."* — a WhatsApp rule applied globally. The web
> channel escaped it only by bypassing the whole function. **The session-window check needs to move
> behind the channel abstraction; it is currently in front of it.**

**Groups.** Privacy mode is on by default — the bot sees only commands addressed to it, replies to
it, and service messages ([privacy-mode](https://core.telegram.org/bots/features#privacy-mode)).

> ⚠️ **The WhatsApp-groups precedent is the honest cost estimate.** Maytapi groups required an
> entirely parallel domain: `wa_messages`, `Glific.WAMessages`, `Communications.WAGroupMessage`,
> `Providers.Maytapi.WaMessages`, its own worker and controllers. Telegram groups would be a third
> such domain, not a parser clause.

**Blocking** is learned via `my_chat_member` — *"For private chats, this update is received only when
the bot is blocked or unblocked by the user"*. ⚠️ **The 403 string `Forbidden: bot was blocked by the
user` does not appear anywhere in the docs — UNVERIFIED.** Do not string-match `description`.
Note `my_chat_member` *is* in the default `allowed_updates` — easy to lose by passing an explicit list.

**Telegram Business** (`business_connection_id`) is a fundamentally different posture — the bot acts
as the *operator's* agent inside the operator's own chats, much closer to the WhatsApp Business model.
Telegram flags legal exposure: *"make sure you have read and understood Section 5.4"* of the Bot Developer ToS.

---

## 2. RCS / RBM

### 2.1 Identity — MSISDN, confirmed

RBM addresses users by raw E.164 **in the URL path**: `phones/+12223334444/agentMessages`
([phones.agentMessages](https://developers.google.com/business-communications/rcs-business-messaging/reference/rest/v1/phones.agentMessages/create)).
Inbound carries `senderPhoneNumber` ([UserMessage](https://developers.google.com/business-communications/rcs-business-messaging/reference/rest/v1/UserMessage));
`ServerEvent` inconsistently uses `phoneNumber`. **No per-agent opaque id exists** (verified by absence).

> **The consequence is subtler than "collision".** With `contact_identities` unique on
> `(organization_id, channel, identifier)`, an RCS identity and a WhatsApp identity for the same human
> are two rows — same `identifier`, different `channel`. No violation; resolution to one `contact_id`
> is exactly what the design intends.
>
> The real problem is downstream: **one contact is reachable on two channels at the same address, and
> nothing decides which to use.** Today `channel` is an *input* to send. With RCS + WhatsApp it becomes
> an *output* of a routing decision — preference, capability, cost, reachability. **No channel-selection
> policy exists in Glific**, and `provider_handler/1` cannot express one.

### 2.2 Capability check — a genuinely new component

`GET /v1/phones/{E.164}/capabilities?requestId=…&agentId=…`
([phones.getCapabilities](https://developers.google.com/business-communications/rcs-business-messaging/reference/rest/v1/phones/getCapabilities))
→ `{features: [Feature], carrier: string}`.

Feature enum (all 9): `FEATURE_UNSPECIFIED`, `RICHCARD_STANDALONE`, `RICHCARD_CAROUSEL`,
`ACTION_CREATE_CALENDAR_EVENT`, `ACTION_DIAL`, `ACTION_OPEN_URL`, `ACTION_SHARE_LOCATION`,
`ACTION_VIEW_LOCATION`, `ACTION_OPEN_URL_IN_WEBVIEW`.

**Non-capable → HTTP 404, not silent failure.** Success returned *"only if the MSISDN has connected to
the RCS service within the last 31 days"*.

Bulk is a different thing: `POST /v1/users:batchGet`, **500–10,000 numbers**, single region,
**600 QPM**, returns `reachableUsers[]` — *"estimate the number of RBM-reachable users but do not
indicate specific device features."* Bulk for audience sizing; per-number for feature gating. That is
an N-calls-per-broadcast cost.

**Google does not do fallback — you do.** *"Always check for delivery receipts before triggering a
fallback message"* / *"Always attempt to revoke the original message before sending the fallback SMS"*
([best-practices](https://developers.google.com/business-communications/rcs-business-messaging/guides/learn/best-practices)).
There is **no `sms_fallback` field on `AgentMessage`**. (That Google provides no fallback is
**UNVERIFIED as an explicit statement** — inferred from consistent partner-side phrasing plus the absent field.)

> ### Where the claim breaks hardest
> The documented-safe sequence is **send → await `DELIVERED` or TTL expiry (up to 15 days) → `DELETE`
> (revoke) → only if revoke succeeds, send SMS.**
>
> `Communications.Message.send_message/2` is a synchronous `apply/3` that enqueues one Oban job. It has
> no pre-send hook, no post-send *wait* state, no revoke concept, and — verified by exhaustive grep —
> **no cross-channel fallback anywhere in `lib/glific`.** This is a multi-day stateful saga, not a
> function call. It does not fit the dispatch seam; it needs something above it.

### 2.3 Rich features and limits

`AgentContentMessage` union: `text` | `uploadedRbmFile` | `richCard` | `contentInfo`. Actions:
`dialAction`, `viewLocationAction`, `createCalendarEventAction`, `openUrlAction`, `shareLocationAction`.
Typing and read are **agent events**, not messages — `POST /v1/phones/*/agentEvents` with
`eventType` ∈ `IS_TYPING` | `READ`.

| Limit | Value |
|---|---|
| Text | **3072 chars** |
| Suggestions per message / per card | **11** / **4** |
| Carousel cards | **min 2, max 10** |
| Card title / description | **200** / **2000** chars |
| Suggestion text | **25 chars** |
| `SuggestedAction.postbackData` | **2048 chars** |
| Payload / media / thumbnail | **250 KB** / **100 MiB** / **100 kB** |
| TTL | max **15 days** |

⚠️ **`SuggestedReply.postbackData` has no stated max** (unlike `SuggestedAction`'s 2048). Do not assume 2048.
There is also a MB/MiB inconsistency between the reference and the send guide.

| Glific | RCS | Fidelity |
|---|---|---|
| `quick_reply` | `suggestedReply` | **Excellent** — but **25-char** button text is tighter than WhatsApp |
| `list` | carousel (2–10) or ≤11 suggestions | **Degraded** — no sectioned list; hard cardinality caps |
| `location_request_message` | `shareLocationAction` | **Native** |
| Blocks (`:blocks`) | rich card / carousel | **Partial** — `glific/*` could translate; org namespaces cannot |

⚠️ **Rich cards and carousels have no `messages.type` enum value.** `message_type_enum` is a Postgres
enum. Either overload `:quick_reply`/`:list`, or ship a migration. **The "no migration needed"
property covers the `channel` column only.**

### 2.4 Inbound transport and receipts

**The docs currently contradict themselves.** The guides document **webhooks only**
([webhooks](https://developers.google.com/business-communications/rcs-business-messaging/guides/integrate/webhooks)),
and the old `/guides/integrate/pubsub` URL now redirects there; the REST reference still describes
Pub/Sub. Envelope is Pub/Sub-shaped either way: `{"message":{"data":"[base64]"}}`, with
`X-Goog-Webhook-Type` and `X-Goog-Signature` (SHA512 HMAC). Whether a *pull* subscription still works
is **UNVERIFIED**. Good news: a webhook is a Phoenix controller, not a GCP Pub/Sub subscriber.

**RCS gives real receipts — unlike Telegram.** `UserEvent.EventType` ∈ `DELIVERED`, `IS_TYPING`,
`READ`, `UNSUBSCRIBE`, `SUBSCRIBE`; `messageId` *"is populated for DELIVERED and READ events"*.
Plus `ServerEvent`: `TTL_EXPIRATION_REVOKED`, `TTL_EXPIRATION_REVOKE_FAILED`.

**The inbound shape maps onto Glific's model more naturally than the web channel did** — `messageId` +
`senderPhoneNumber` + a typed content union (`text` | `userFile` | `location` | `suggestionResponse`),
plus separate delivered/read events keyed by `messageId`. That is `bsp_message_id` +
`message_event_controller` almost exactly.

### 2.5 Launch friction and India specifics

1. Register as partner → 2. partner account + service-account key → 3. create brand + agent
(**hosting region immutable**) → 4. add test devices (**max 20 invites/day, 200 total**) →
5. **brand verification** (a named brand employee **must** reply to `rbm-support@google.com`) →
6. **launch approval** — requires a working STOP flow **plus a screen recording demonstrating it** →
7. live ~30 min after `LAUNCH_STATE_LAUNCHED`.

**Per-carrier approval: confirmed.** `launchDetails` is a **map keyed by region/carrier**, each with
its own `launchState`. Sending where you are not launched → **404**. Google-managed launches take
**1–3 business days**; carrier-managed timelines, brand-verification turnaround and partner-registration
approval time are all **UNVERIFIED** (unpublished). Google **does not publish a carrier list**.

India promotional caps, reputation-tiered over rolling 28 days
([agent-use-cases](https://developers.google.com/business-communications/rcs-business-messaging/guides/learn/agent-use-cases)):

| Reputation | Msgs/user/28d | Unique users/28d |
|---|---|---|
| High | 8 | 300M |
| Medium | 4 | 25M |
| **Low (default — all new agents)** | **2** | **1M** |

Promotional window **7AM–10PM**. *"Replies to user-initiated messages are exempt."*

> ⚠️ **2 messages per user per 28 days at Low reputation is likely disqualifying for an NGO broadcast
> use case**, unless the agent classifies as Transactional/OTP or reputation can be raised.

**Carriers:** **Airtel is PRIMARY-verified** via an
[Airtel press release (1 Mar 2026)](https://www.airtel.in/press-release/03-2026/airtel-and-google-collaborate-to-advance-spam-protection-in-india-with-secure-rcs-messaging/).
**Jio and Vi: UNVERIFIED** (trade press only).

**TRAI / DLT: UNVERIFIED, and the evidence is thin.** The actual TRAI PDFs were downloaded and
full-text-searched:

| Document | "RCS" hits |
|---|---|
| [TCCCP (Second Amendment) Regulations, 2025](https://www.trai.gov.in/sites/default/files/2025-02/Regulation_12022025.pdf) | **0** (19 × DLT) |
| [Draft TCCCP (Third Amendment), 2026](https://www.trai.gov.in/sites/default/files/2026-03/Draft_CP_13032026_0.pdf) | **0** (27 × DLT, 31 × A2P) |

**No primary source states that RCS A2P traffic in India requires DLT registration.** Vendor blogs
claiming otherwise sell DLT registration services. One narrower claim *is* sound: DLT unambiguously
governs the **SMS fallback leg**. Resolve with whichever provider is chosen; do not design around either assumption.

### 2.6 Provider note

Provider selection was explicitly ruled out of scope for the design doc. Two findings are recorded
because they would otherwise be rediscovered:

- **Gupshup's RCS product is real** ([RCS API](https://www.gupshup.ai/en/communicate/rcs-api),
  [Google partner listing](https://rcsforbusiness.google/intl/en_in/find-a-partner/gupshup/)) but lives
  on the legacy `enterprise.smsgupshup.com/GatewayAPI/rest` gateway — different host, `userid`+`password`
  instead of the `apikey` header, pipe-delimited responses. [`docs.gupshup.io/llms.txt`](https://docs.gupshup.io/llms.txt),
  the complete docs index, contains **zero occurrences of "RCS"**. **~Zero reuse** from
  `lib/glific/providers/gupshup/api_client.ex`. Rich content is not programmable — templates are
  *"performed by Gupshup on behalf of the brand"*, media uploaded **by emailing support**. Inbound
  payload shape and multi-agent selection at send time are both **UNVERIFIED/undocumented**.
- **Google RBM directly is not viable** — *"Businesses must use a partner or messaging aggregator"*
  ([FAQ](https://rcsforbusiness.google/resources/faq/)). No self-serve tier.
- Of the aggregators checked, **Infobip** was the only one verifiable end-to-end for India with real
  API docs — `POST /ott/rcs/1/message`, clean JSON, and **built-in `smsFailover` with an `indiaDlt`
  parameter** ([docs](https://www.infobip.com/docs/api/channels/rcs/rcs-outbound-messages/send-rcs-message)).
  Twilio and Vonage do **not** cover India. Sinch and Karix **UNVERIFIED**.

---

## 3. The 18 places the "cheap channel" claim breaks

| # | Gap | Channel | Why it isn't a clause |
|---|---|---|---|
| 1 | `contact_identities` is a prerequisite | Telegram | `contacts` unique on `(phone, org)`; a Telegram user has no phone. **Cannot ship before it** |
| 2 | The dispatch seam does not exist | Both | `provider_handler/1` reads a single `services["bsp"]`. Channel #3 = the third bypass clause |
| 3 | Session-window check sits in front of the abstraction | Both | `can_send_message_to?/2,3` gates on `bsp_status` for *every* channel |
| 4 | Capability-check-then-fallback has no home | RCS | A multi-day saga; no pre-send hook, no wait state, no revoke |
| 5 | Channel-selection policy is missing | RCS | RCS + WhatsApp reachable at the same E.164 |
| 6 | `answerCallbackQuery` — inbound-triggered outbound ack | Telegram | Ingest seam has no "acknowledge the provider" step |
| 7 | Status model assumes receipts exist | Telegram | `:delivered`/`:read` can never fire |
| 8 | Outbound initiation is not universal | Telegram | Users must `/start` first |
| 9 | `message_type_enum` is a Postgres enum | RCS | Rich card / carousel need a migration |
| 10 | Group chats are a separate domain | Telegram | The `wa_messages` precedent |
| 11 | Media is per-bot, and the URL is a secret | Telegram | `file_id` not transferable; `getFile` URLs embed the token |
| 12 | Rate limiting is per-chat, not per-org | Telegram | 1 msg/s per chat; `gupshup: 10` has no rate limit |
| 13 | Staff inbox filters on `contact_type` | Both | New-channel contacts silently absent |
| 14 | Gupshup RCS shares nothing with Gupshup WhatsApp | RCS | Different host, auth, format |
| 15 | Gupshup rich content is not programmable | RCS | Templates created by support; media by email |
| 16 | Two undocumented holes block a Gupshup spec | RCS | Inbound payload shape; multi-agent selection |
| 17 | RCS launch friction is weeks | RCS | Per-carrier approval, brand verification, STOP-flow recording |
| 18 | India promotional caps may disqualify the use case | RCS | 2 msgs/user/28 days at Low reputation |

---

## 4. Conclusion

**Telegram is close to the claim; RCS is not.**

Telegram is genuinely a parser + adapter + dispatch clause **once two things exist**:
`contact_identities` (mandatory) and the `dispatch` seam. Everything else is bounded work — a media
downloader, a rate-limited queue, a callback-ack path, a reachability precondition. Onboarding is
minutes. And it is the **only non-web channel that can render Blocks natively**, via Mini Apps.

**RCS is not a channel-adapter problem.** Three of its costs are architectural: the fallback saga; the
missing channel-selection policy; and, on the Gupshup path specifically, rich content that is not
programmable at all — which removes the reason to want RCS. The commercial blockers are worse than the
technical ones.

**The most useful sentence:** the web channel proved the **ingest seam works** and the **dispatch seam
doesn't**. Telegram is the channel that would justify building `dispatch` properly. RCS is the channel
that would break it again.
