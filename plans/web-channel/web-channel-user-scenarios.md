# Glific Web Channel — User Scenarios & Acceptance Criteria

**Purpose:** align the team on **how the web channel behaves** before we write the technical design.
Each scenario is written as Given / When / Then and grouped by area. These are the target
behaviours; once we agree on them they become the acceptance criteria the tech design builds toward.

**One-line context:** NGO beneficiaries open a Glific-hosted web page, log in with phone + OTP, and
chat in a WhatsApp-style window. The conversation is driven by the **same Glific flow engine** and
appears in the **same staff inbox** as WhatsApp. Contacts are **shared** across channels (one person,
one contact); the channel is recorded on each message.

---

## 1. Onboarding & authentication

**S1 — Existing WhatsApp contact logs into web**
- **Given** a contact already exists with phone P (with WhatsApp history)
- **When** she completes phone + OTP on the web channel with phone P
- **Then** she is bound to the **same** contact — no duplicate is created — and staff see one unified
  conversation containing both channels.

**S2 — New contact, web-first**
- **Given** no contact exists for phone P
- **When** OTP verification succeeds
- **Then** the contact is created **at verification** (never merely on OTP request), and the org's
  new-contact flow triggers on the web channel.

**S3 — OTP requested but never verified**
- **Given** a phone P with no contact
- **When** an OTP is requested but never verified
- **Then** no contact is created, and the OTP request is rate-limited per-phone and per-IP.

**S4 — Consent is per channel; blocking is global**
- **Given** a contact who has opted out of WhatsApp
- **When** she opens the web chat she deliberately navigated to
- **Then** she **can** use the web channel (consent is per-channel). **But** a blocked contact
  (moderation) **cannot** use web either — blocking applies across all channels.

---

## 2. First load & the chat window

**S5 — Empty chat window on first login**
- **Given** a contact logs in for the first time with no prior web messages
- **When** the chat opens
- **Then** she sees an empty chat window with the **bot's name and logo shown at the top**.

**S6 — Last 50 messages on first load**
- **Given** a contact with prior web messages
- **When** the chat opens
- **Then** the most recent **50** web messages are loaded, newest at the bottom.

**S7 — Scroll up to load older messages, with an end-of-history cue**
- **Given** the chat is open
- **When** she scrolls up past the top of the loaded messages
- **Then** the previous page of older web messages loads; and once the **oldest** message on the
  channel has been fetched, a **visual cue** indicates there are no more messages (the view no longer
  scrolls further back).

**S8 — Copy a message**
- **Given** a message in the chat
- **When** she uses the copy action (long-press / menu, as in WhatsApp)
- **Then** the message text is copied to the clipboard.

**S9 — Rich content auto-unravels**
- **Given** a message (incoming or outgoing) containing a link, a YouTube URL, or an image
- **When** it renders in the chat
- **Then** the chat automatically shows a preview/embed — link unfurl, YouTube player/thumbnail,
  inline image.

**S10 — WhatsApp-style buttons**
- **Given** a flow sends an interactive message using the same button types available on WhatsApp
- **When** it renders in the web chat
- **Then** the buttons appear and the contact can tap one to respond.

**S11 — Record & send a voice note**
- **Given** the contact is in the chat
- **When** she records audio with the voice-note control and sends it
- **Then** the voice note is delivered as a message, appears in the conversation, and is visible in
  the staff inbox.

**S12 — Typing indicator with escalation (driven by the flow)**
- **Given** the flow is processing and will send the next message
- **When** the flow shows the typing indicator
- **Then** the contact sees a typing indicator; after **25s** it changes to **"taking longer than
  usual"**; after **45s** it changes to **"any minute now"**. These states are sent/controlled by the
  flow.

**S13 — Offline banner**
- **Given** the contact is in the chat
- **When** the web channel detects there is no connectivity
- **Then** a banner appears at the top saying **messages might not be sent**; the banner **hides
  automatically** when connectivity is restored.

**S14 — Install as an app (PWA)**
- **Given** the contact is using the web channel on iOS or Android
- **When** she chooses "Add to Home Screen" / install
- **Then** the web app is saved as an **icon on her device** and launches like an app.

**S15 — Mobile browser coverage**
- **Given** the range of mobile browsers in use
- **Then** the web channel **works on 95% of all mobile browsers**, verified by testing.

---

## 3. Cross-channel switching

*Invariant: at most one active flow per contact, regardless of channel.*

**S16 — Web flow active, she replies on WhatsApp (no keyword)**
- **Given** an active flow on the web channel, parked waiting for a response
- **When** an inbound WhatsApp message arrives with no keyword match
- **Then** the web flow does **not** advance (continuation is channel-scoped); the WhatsApp message is
  recorded; the web flow stays parked and remains resumable on web. **No cross-channel takeover.**

**S17 — Keyword sent on a different channel**
- **Given** an active flow on the web channel
- **When** she sends a matching keyword over WhatsApp
- **Then** the web flow is completed and a new flow starts on WhatsApp.

**S18 — Rapid/simultaneous inbound on both channels (last message wins)**
- **When** messages arrive on both channels close together
- **Then** messages are handled in processing order, and the **last-processed message wins** — its
  channel becomes the contact's current/active channel.

---

## 4. Presence & delivery

**S19 — Outbound while present**
- **When** a flow (or staff) sends to a **connected** web contact
- **Then** the message is pushed live over the socket and marked delivered.

**S20 — Outbound while absent (pause)**
- **When** a flow reaches a send step and the contact is **not** connected
- **Then** the message is **not** sent and the flow **pauses** at that step. Nothing is queued ahead.

**S21 — Contact returns**
- **When** the contact reconnects
- **Then** the paused flow **resumes** from where it stopped and the pending message is delivered.

**S22 — Contact never returns**
- **Then** the parked flow simply lives out the **standard flow lifetime** — there is no
  web-specific expiry.

**S23 — Long delays work**
- **Given** a web flow with a wait/delay step of any duration (hours or days)
- **Then** it works unchanged — there is no short web expiry that would cut it off.

**S24 — Disconnect with nothing pending**
- **When** the contact disconnects while the flow is simply waiting for her reply
- **Then** nothing happens; the flow stays parked and resumes when she returns.

---

## 5. Node behaviour on web

**S25 — All nodes supported except "Update WhatsApp Group"**
- **Given** a web-channel flow
- **Then** every flow node behaves as it does on WhatsApp — text, media, images, **voice**,
  interactive **buttons**, templates — **except "Update WhatsApp Group"**.

**S26 — Unsupported node stops the flow and notifies**
- **Given** a flow contains an "Update WhatsApp Group" node
- **When** a contact on the web channel reaches that node
- **Then** the flow **stops** at that node and a **notification** is raised saying the flow stopped
  because the node is not supported on web.

**S27 — Contact name is shared, not set on web**
- **Given** contacts are shared across channels
- **Then** the web channel shows and uses the **same contact name as WhatsApp** — there is no
  separate web name and no set-name-on-web behaviour.

---

## 6. Staff inbox

**S28 — Unified timeline**
- **Then** staff see **one conversation per contact** with all channels merged, and a channel marker
  where the conversation moves between channels.

**S29 — Reply channel selection**
- **When** staff reply from the inbox
- **Then** the composer defaults to the contact's **last channel**, **always shows** which channel it
  will send on, and is **overridable** in one click.

**S30 — Channel & session indicator by last-seen**
- **Given** an admin viewing a contact's chat window
- **When** the contact was **last seen on WhatsApp**
- **Then** a **WhatsApp icon** shows next to the **session timer** (the 24-hour window)
- **When** the contact was **last seen on web**
- **Then** a **web icon** shows with **no timer** — the session window does not apply to web.

---

## 7. Metrics & abuse

**S31 — Daily active user**
- **Then** a "daily active user" is a contact who **sent** at least one web message that day
  (received-only does not count).

**S32 — Rate limiting**
- **Then** per-contact limits apply to messages sent/received, and per-phone + per-IP limits apply to
  the OTP request endpoint.

---

## 8. Organisation configuration (Settings)

**S33 — Enable the web channel from a "Web" settings page**
- **Given** an admin in Glific Settings, with a new **"Web"** page shown next to **Gupshup**
- **When** they open it and click to enable the default web channel
- **Then** the page shows the **potential (accessible) link** for the org's web channel; on
  **confirmation** the web channel is activated; and the page then shows a **link to the active web
  channel**.

---

*Open items to confirm during alignment: exact copy for the typing-indicator states and the offline
banner; which button types count as "same as WhatsApp"; whether "Update WhatsApp Group" stopping the
flow should also surface to the end-user or only to staff; and the precise list of browsers behind
the 95% coverage target.*
