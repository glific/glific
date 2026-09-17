# Glific Platform Guide

A comprehensive reference for the Glific WhatsApp chatbot platform, written for an AI support chatbot that helps NGO staff. The chatbot cannot see screenshots — every UI element is described in plain text using the exact labels that appear in the product.

> Glific is built on React 19 + TypeScript + Apollo (GraphQL) + MUI v7. The frontend lives in `glific-frontend/src/`. Routes are defined in `src/routes/AuthenticatedRoute/AuthenticatedRoute.tsx`. The left-sidebar menu is configured in `src/config/menu.ts`.

---

## Navigation & Layout

### Overall layout

When a user logs in, the screen is divided into:

1. **Left sidebar (SideDrawer)** — collapsible vertical menu with icons. Top section has feature menus; bottom has user-account menus (My Account, Settings, Logout) and external links (Resources, Discord).
2. **Main content area** — the active screen renders here. Most list-style screens have a top toolbar (search, filter, "+ Add" button) and a paginated table.
3. **Toast/notification area** — bottom of the screen. Success messages appear green, warnings yellow, errors red. Errors with stack-trace details open as a centered dialog.

### Roles

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

- **Staff** — limited access (Chats, assigned Collections, Tickets, Blocked Contacts, My Account).
- **Manager** — Staff plus Flows, Templates, Triggers, Tags, Speed Sends, Searches, Interactive Messages, Notifications, Webhook Logs, Contact Variables.
- **Admin** — Manager plus Settings, Contact Management (bulk), Roles.
- **Glific_admin** — Admin plus Organizations multi-tenant management, Consulting Hours.
- **Dynamic roles** — organizations can define custom roles via `/role`; behavior set per-role.

### Sidebar menu (left, top to bottom)

The exact items shown in the side drawer come from `src/config/menu.ts`:

| Menu item                    | URL                    | Roles        | Notes                                                                                                                                                                                                                                                                                                    |
| ---------------------------- | ---------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chats**                    | `/chat`                | All          | The default landing screen                                                                                                                                                                                                                                                                               |
| **WhatsApp Groups** (parent) | `/group/chat`          | All          | Visible only when the `whatsappGroupEnabled` org service is on. Children: **Group Chats** (`/group/chat`), **Group Collections** (`/group/collection`), **Group Polls** (`/group/polls`), **WhatsApp Phones** (`/group/phones`, Manager+)                                                                 |
| **Flows** (parent)           | `/flow`                | Manager+     | Children: **Flows** (`/flow`), **Google sheets** (`/sheet-integration`), **Webhook logs** (`/webhook-logs`), **Support tickets** (`/ticket`, only when `ticketingEnabled`), **Certificates** (`/certificates`, only when `certificateEnabled`)                                                            |
| **Support tickets**          | `/ticket`              | Staff (only) | Top-level for the Staff role; Manager+ reach it via the Flows submenu. Only when `ticketingEnabled`.                                                                                                                                                                                                     |
| **Quick tools** (parent)     | `/interactive-message` | Manager+     | Children: **Interactive Msg** (`/interactive-message`), **HSM Templates** (`/template`), **WhatsApp Forms** (`/whatsapp-forms`, only when `whatsappFormsEnabled`), **Triggers** (`/trigger`), **Searches** (`/search`), **Speed Sends** (`/speed-send`)                                                   |
| **Notifications**            | `/notifications`       | Manager+     | Shows badge with unread count                                                                                                                                                                                                                                                                            |
| **AI toolkit** (parent)      | `/assistants`          | Manager+     | Children: **AI Assistant** (`/assistants`), **AI Evals** (`/ai-evaluations`)                                                                                                                                                                                                                             |
| **Data Analytics**           | `/analytics`           | All          | Marked "new" in the menu                                                                                                                                                                                                                                                                                 |
| **Manage** (parent)          | `/collection`          | Staff+       | Children: **Collections** (`/collection`), **Staff** (`/staff-management`, Manager+), **Contacts** (`/contact-management`, Admin+), **Blocked contacts** (`/blocked-contacts`), **Contact variables** (`/contact-fields`, Manager+), **Tags** (`/tag`, Manager+), **Roles** (`/role`, only when the org doesn't use Dynamic roles), **Organizations** (`/organizations`, Glific_admin), **Consulting** (`/consulting-hours`, Glific_admin) |
| **Resources**                | external (Glific docs) | All          |                                                                                                                                                                                                                                                                                                          |
| **Discord**                  | external               | All          |                                                                                                                                                                                                                                                                                                          |

User-account menu (bottom of sidebar / avatar):

- **My Account** (`/myaccount`) — change password, language preference.
- **Settings** (`/settings`) — Admin only; routes to Organization, Flows config, Billing, and provider tiles.
- **Logout** (`/logout/user`).

---

## Screens

### Chat

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Chats/

#### Screen: Chats (main inbox)

- **URL:** `/chat` (also `/chat/:contactId`, `/chat/collection`, `/chat/collection/:collectionId`, `/chat/saved-searches`, `/chat/saved-searches/:contactId`)
- **Purpose:** Send and receive WhatsApp messages with individual contacts, manage conversations, run flows, send templates and interactive messages.
- **How to access:** Click **Chats** in the sidebar (top item).

**Layout (three columns):**

1. **Tab bar (top of left panel):** **Contacts** | **Collections** | **Searches**.
2. **Left panel — conversation list:**
   - Search bar with placeholder **"Search conversations"** (1-second debounce).
   - **Saved Search Toolbar** — quick filter pills, typically **All**, **Unread**, **Not Responded**, with count badges like "(12)". A `…` button reveals additional saved searches.
   - List of conversations: each row shows avatar (initials), contact name, last-message preview (truncated to ~100 chars), relative timestamp ("now", "2m", "1h", "Yesterday"), unread badge, and an icon for the last message type (text/media/template/interactive).
3. **Right panel — chat thread:**
   - **Conversation header** with the contact name (max 40 chars), comma-separated list of collections the contact belongs to, and a **session timer** showing **"Time left: HH:MM"** counting down the 24-hour messaging window. A dropdown arrow opens an actions menu.
   - **Message list** with date separators ("Today", "Yesterday", or full date), per-message timestamps, and status icons (single check = sent, double check = delivered, double check filled = read, ⚠ = failed; hover for error).
   - **Chat input** at bottom (see "How to send messages" below).

**Conversation header — dropdown menu items:**

- **View contact profile** → navigates to `/contact-profile/:id`.
- **Start a flow** → opens "Select flow" dialog with a list of published flows; click **Start**. Toast: _"Flow started successfully."_ Disabled when the 24-hour window is closed unless the contact is HSM-eligible.
- **Add to collection** → opens "Add contact to collection" multi-select dialog with checkboxes; click **OK**.
- **Clear conversation** → confirmation dialog _"Are you sure you want to clear all conversation for this contact?"_ with buttons **YES, CLEAR** and **MAYBE LATER**. Toast: _"Conversation cleared for this contact."_
- **Terminate flows** → opens dialog listing currently active flows; select and click **Terminate**.
- **Block Contact** → confirmation _"Do you want to block this contact"_ / _"You will not be able to view their chats and interact with them again"_ with **OK**/**Cancel**. Toast: _"Contact blocked successfully."_ Returns user to `/chat`.

**How to send messages:**

The chat input has, left-to-right: **down-arrow** (quick send picker) · **paperclip** (attachment) · **rich-text editor** (bold `*x*`, italic `_x_`, strikethrough `~x~`, code `` `x` ``, lists, links) · **emoji picker** · **microphone** (voice) · **send button** (paper airplane).

1. **Send a text message:** type in the editor, click **send** (or Ctrl+Enter).
2. **Send media:** click the paperclip → choose Image / Video / Audio / Document → optionally add caption → **Send**.
3. **Send a Speed Send:** click the down arrow → **Speed sends** tab → search/select → text auto-fills the editor → optionally edit → **send**.
4. **Send an HSM template:** down arrow → **Templates** tab → search/select. If the template has variables, an **"Add Variables"** dialog opens with a field per `{{n}}`; click **Submit variables**. The template body fills the editor (read-only) and any required media auto-loads → **send**.
5. **Send an Interactive Message:** down arrow → **Interactive msg** tab → select. The buttons/list preview is shown read-only → **send**.
6. **Send a voice message:** click the microphone → speak → click microphone again to stop → **send** (uploaded as MP3).

**Message behavior depending on contact status:**

- **SESSION** (within 24-hour window): Speed sends and Interactive messages allowed.
- **SESSION_AND_HSM**: Templates, Interactive, and Speed sends.
- **HSM** (24-hour window expired): Templates only.

**Per-message hover menu (3-dot icon):**

- **Add to speed sends** → "Save message as speed send" dialog → enter shortcode → **Save**.
- **Download media** (for non-text messages) — saves with appropriate extension (.png/.mp4/.m4a).

**Tabs:**

- **Contacts** (`/chat`) — individual contact conversations.
- **Collections** (`/chat/collection`) — message a whole collection. Header dropdown adds **View details**, **Start a flow**, **Add groups/contacts** (the dialog is titled _"Add contacts to the collection"_).
- **Searches** (`/chat/saved-searches`) — pick a saved search; results render as a conversation list. From the search bar, applying a filter exposes **Create new** and **Update** buttons to save / update the saved search.

**Common issues:**

- _"The contact is blocked"_ in red — unblock from `/blocked-contacts`.
- Send button disabled with tooltip _"Option disabled because the 24hr window expired"_ — send a template (HSM) instead.
- _"Sorry, unable to send the attachment."_ — verify file size and format.
- _"Sorry, unable to upload audio."_ — try recording again.

---

#### Screen: Group Chats (WhatsApp Groups)

- **URL:** `/group/chat`, `/group/chat/:groupId`, `/group/chat/collection`, `/group/chat/collection/:collectionId`.
- **Purpose:** Same UX as `/chat` but for WhatsApp groups (multi-participant). Visible when `whatsappGroupEnabled` org service is enabled.
- **Differences from contact chat:** sender's contact name appears above each incoming message ("Message from: ContactName"). Block, Clear conversation, and Terminate flows are not available. **Start a flow** for a group runs the flow for all participants — toast _"Your flow will start in a couple of minutes."_

---

### Flows

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/

#### Screen: Flow list

- **URL:** `/flow`
- **Purpose:** Browse, search, manage all flows.
- **How to access:** Sidebar → **Flows** → **Flows**.

**Columns:** Pinned (pin icon) · Title (with keywords below in gray) · Last Published (date or "Not published yet") · Tag · Last Saved in Draft (date or "Nothing in draft").

**Toolbar / actions:**

- **Search field** — searches name, keywords, and tags.
- **Status filter** — **Active** / **Inactive**. (There is no Template filter: flow templates are on hold — glific/glific#5332 — and the filter option is commented out in the UI.)
- **Tag filter** — autocomplete.
- **+ Create** button — goes straight to the new-flow form (`/flow/add`). The old "How do you want to create a flow? → Create from Scratch / Create from Template" dialog is bypassed while templates are on hold.
- **Import flow** button — uploads a JSON file (exported from another Glific instance). A status dialog titled _"Import flow Status"_ reports the result.

**Per-row actions:** Configure (opens flow editor) · Share (responder link — if the flow has no keywords you get the warning _"No keywords found to share the responder link"_) · Copy (duplicates with prefix "Copy of …" and clears keywords) · Export (downloads JSON) · Edit (metadata form) · Pin/Unpin · Delete (confirmation: _"You won't be able to use this flow."_).

#### Screen: Flow create/edit (metadata)

- **URL:** `/flow/add`, `/flow/:id/edit`, `/flow/:id/view` (read-only)

**Fields:**

- **Name** \* — required, no special characters allowed.
- **Keywords** — comma-separated, alphanumeric and hyphens only. Helper: _"Enter comma separated keywords that trigger this flow."_
- **Description** — 2-row textarea.
- **Tag** — autocomplete; can create inline. Helper: _"Use this to categorize your flows."_
- **Ignore Keywords** — checkbox. Tooltip: _"If activated, users will not be able to change this flow by entering keyword for any other flow."_
- **Is active?** — checkbox (default checked).
- **Is pinned?** — checkbox; pinned flows sort to top.
- **Run this flow in the background** — checkbox; flow executes without blocking user.
- **Skip Validation** — checkbox; bypass validation for results fetched dynamically (resumeFlow API).
- **Roles** (when dynamic roles enabled) — checkboxes per role.

**Buttons:** **Save** · **Configure** (after save → flow editor) · **Delete** (confirmation: _"You won't be able to use this flow."_).

#### Screen: Flow Editor (visual canvas)

- **URL:** `/flow/configure/:uuid`
- **Purpose:** Build the flow logic graphically.

**Top header:** Back arrow · Flow title and keywords (with status: `draft:KEYWORD`, `template:NAME`, "Sorry, the flow is not active", or "No keyword found") · **More** menu (Export flow, Reset flow count, Share Responder Link) · **Translate** · **Preview** (simulator) · **Publish**.

**Publishing:** click **Publish** → confirmation _"Ready to publish?"_ with **Publish & stay** / **Publish & go back**. On success: toast _"The flow has been published"_. Validation errors open a dialog listing issues to fix first.

**Read-only mode:** when another user is editing, a banner shows _"View Only Mode - …"_ with a **Take Over** button.

**Simulator (Preview):** opens a chat-like panel where you type messages as a fake contact and see flow responses node-by-node. **Reset** clears the simulator state.

#### Flow Editor — Node types

Every node is added by dragging from the node palette or clicking on the canvas. Each node has a header (the action type), a body (configured content), and one or more exit ports (lines to the next node). Click a node to open its inline editor; click an exit to draw a connector to the next node.

**A. Send / Output actions**

| Node UI label             | Internal type          | What it does                                                   | Key fields                                                                                                                                                                                        |
| ------------------------- | ---------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Send Message**          | `send_msg`             | Sends a text message to the contact.                           | Message text (Gupshup rejects >4096 chars) · **Labels** to apply to the outgoing message · **Attachments** tab (one attachment per node) · **HSM Templates** tab (template + variables). No quick-reply field and no Facebook "Topic" field in Glific. |
| **Interactive Message**   | `send_interactive_msg` | Sends a button or list interactive message (WhatsApp).         | Pick an existing Interactive Message template. Buttons/list items are defined on the template, not on the node — this is how you get reply buttons.                                                |
| **Send message to staff** | `send_broadcast`       | Sends a message to selected staff/users, not to the contact.   | Message text, recipient staff                                                                                                                                                                     |
| **Save Flow Result**      | `set_run_result`       | Stores a named variable usable later in the flow.              | Result name, Result value (expression or fixed), Category                                                                                                                                         |

**Attachment limits** (enforced server-side by `validate-media`): image ≤ 5 MB · video ≤ 16 MB · audio ≤ 16 MB · document ≤ 100 MB · sticker ≤ 100 KB. Uploading a file needs Google Cloud Storage configured for the org; otherwise you paste a public media URL.

**B. Contact management actions**

| Node UI label              | Internal type                                  | What it does                                                                                                            |
| -------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Update Contact**         | `set_contact_field` / `set_contact_language`   | Updates a contact field or the contact's language. The property dropdown in Glific offers **Language** and **Channel** plus every contact field — Name and Status are removed from the list. |
| **Add to Collection**      | `add_contact_groups`                           | Adds the contact to one or more collections.                                                                            |
| **Remove from Collection** | `remove_contact_groups`                        | Removes from collections.                                                                                               |
| **Add Labels**             | `add_input_labels`                             | Tags the incoming message with flow labels.                                                                             |
| **Update WhatsApp Group**  | `set_wa_group_field`                           | Sets a WhatsApp-group field. Only visible when the **WhatsApp Groups** feature is enabled for the org.                   |
| **Manage profile**         | `set_contact_profile`                          | Switch / create / deactivate profile. Only visible when the **Contact Profiles** feature is enabled for the org.         |

> The flow engine handles `set_contact_field`, `set_contact_language`, `set_contact_name` (legacy flows) and `set_contact_profile`. There is no handler for `set_contact_channel` or `set_contact_status`, so don't build on the Channel option — a flow that uses it fails at runtime with "Unsupported action type".

**C. Flow-control actions / routers**

| Node UI label           | Internal type       | What it does                                                                                                                                                                          |
| ----------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Enter a Flow**        | `enter_flow`        | Calls another flow as a sub-flow; resumes when it completes. Exits: Completed / Expired.                                                                                              |
| **Start Somebody Else** | `start_session`     | Starts a different contact or collection in a flow (fire-and-forget). Lets you select recipients manually, by collection, or create a new contact.                                    |
| **Call Webhook**        | `call_webhook`      | HTTP call. Method is **GET**, **POST**, or **FUNCTION** (a Glific built-in webhook) — PUT/DELETE/PATCH are disabled. Configure URL, Headers, POST body, result name. Exits: Success / Failure. |
| **Link Google sheet**   | `link_google_sheet` | Reads from / writes to a configured Google Sheet. Configure sheet, row lookup, result name.                                                                                          |
| **Open Ticket**         | `open_ticket`       | Creates a support ticket and routes on Success / Failure. Used with the Ticketing feature.                                                                                           |
| **Split by Intent**     | `split_by_intent` (`call_classifier`) | Runs the Dialogflow classifier; one exit per intent + fallback. **Only appears when the Dialogflow service is enabled** for the org.                           |

**AI / LLM steps are built with Call Webhook, not with a dedicated AI node.** Glific ships a set of built-in **FUNCTION** webhooks — set the webhook Method to `FUNCTION` and put the function name in the URL field (`parse_via_chat_gpt`, `parse_via_gpt_vision`, `filesearch-gpt`, `speech_to_text`, `text_to_speech`, `call_and_wait`, `geolocation`, `create_certificate`, and others). The result lands in `@results.<result_name>` and you branch on it with **Split by Flow Result** / **Wait for result**. The full list and request bodies are in the Built-in Webhooks Reference (section 20 of the chatbot knowledge base).

**D. Wait / input routers**

| Node UI label         | Internal type       | What it does                                                                                                                                                     |
| --------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Wait for Response** | `wait_for_response` | Waits for the next contact message. Define **Categories** (named outcomes) and **Cases** (operators, see below). Optional timeout with its own exit.             |
| **Wait for Time**     | `wait_for_time`     | Pauses the flow for a delay (blank/0 falls back to a short built-in wait); the contact is woken by the background worker.                                        |
| **Wait for result**   | `wait_for_result`   | Parks the flow until an external system calls Glific's Resume Flow API. Set the wait; a wait of 24 hours or more makes the next message need to be an HSM, and publishing warns you about it.                              |

**Operators available in Cases** (many RapidPro operators are switched off in Glific): `has_any_word`, `has_all_words`, `has_phrase`, `has_only_phrase`, `has_beginning`, `has_multiple`, `has_number`, `has_number_eq`, `has_number_between`, `has_phone`, `has_email`, `has_pattern` (regex), `has_media`, `has_image`, `has_audio`, `has_video`, `has_file`, `has_location`, plus `has_intent` / `has_top_intent` when a classifier is configured. Date/time comparisons (`has_date*`, `has_time`), numeric `<`/`>` comparisons, `has_text`, `has_value`, `has_error`, `has_group`, `has_category` and location operators (`has_state`, `has_district`, `has_ward`) are excluded from the editor.

**E. Split / routing routers**

| Node UI label                      | Internal type            | What it does                                             |
| ---------------------------------- | ------------------------ | -------------------------------------------------------- |
| **Split by Expression**            | `split_by_expression`    | Evaluates an expression (e.g. `@contact.fields.age`) and routes it through the same operator-based cases as Wait for Response. |
| **Split by Contact Field**         | `split_by_contact_field` | Routes on a contact field.                               |
| **Split by Flow Result**           | `split_by_run_result`    | Routes on a previously saved flow result.                |
| **Split Randomly**                 | `split_by_random`        | A/B split across N buckets.                              |
| **Split by collection Membership** | `split_by_groups`        | In-collection vs not-in-collection.                      |

Webhook, sub-flow, ticket and flow-result nodes also serialize as combined action+router variants (`split_by_webhook`, `split_by_subflow`, `split_by_ticket`, `split_by_run_result_delimited`) — the same node, just how the JSON names it.

**Not available in Glific** — these exist in the upstream RapidPro flow editor but Glific hides them, so don't reference them in flows or answers:

- Explicitly excluded by the Glific frontend: **Add URN** (`add_contact_urn`), **Send Email** (`send_email`), **Call Zapier** (`call_resthook`), **Send Airtime** (`transfer_airtime`), **Split by URN Type** (`split_by_scheme`).
- Hidden because the feature flag is off: **Call AI** (`call_llm`), **Request Opt-In** (`request_optin`).
- Voice-only nodes, and Glific only runs `messaging` flows: **Play Message** (`say_msg`), **Play Recording** (`play_audio`), **Wait for Menu Selection** (`wait_for_menu`), **Wait for Digits** (`wait_for_digits`), **Wait for Forwarded Call** (`wait_for_dial`), **Wait for Audio** (`wait_for_audio`).
- Surveyor / offline-only nodes: **Wait for Image** (`wait_for_image`), **Wait for Video** (`wait_for_video`), **Wait for Location** (`wait_for_location`). To collect an image or location, use **Wait for Response** with the `has_image` / `has_location` operators instead.

**Configuring a node:** click it on the canvas → form appears → fill required fields → **Ok** to save the node. To connect: drag from a node's exit port to another node. Delete by selecting the node and pressing Delete (or context menu).

**Translations:** click **Translate** → choose **Automatic translation** (auto-fill all enabled languages), **Export with auto translate** (CSV with translated rows), **Export translations** (blank CSV template), or **Import translations** (upload completed CSV: `Flow_Translations_{flowId}.csv`).

**Import / export flows:** Export downloads a JSON file. Import accepts the same JSON. After import a status dialog reports per-flow success/failure (with a help link if linked OpenAI assistants couldn't be auto-created).

---

### Speed Sends

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Speed%20Sends/

- **URL:** `/speed-send`, `/speed-send/add`, `/speed-send/:id/edit`
- **Purpose:** Pre-written message snippets staff can pick from in chat.
- **Fields:** Language bar (multilingual switch) · **Title** \* (≤50 chars) · **Message** \* (EmojiInput, supports `@variable` insertion) · **Attachment Type** (IMAGE URL / AUDIO URL / VIDEO URL / DOCUMENT URL / STICKER URL) · **Attachment URL** (validated, required when a type is set).
- **Notes:** picking **STICKER** warns _"Animated stickers are not supported."_ and _"Captions along with stickers are not supported."_; picking **AUDIO** warns _"Captions along with audio are not supported."_

---

### HSM Templates

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

- **URL:** `/template`, `/template/add`, `/template/:id/edit`
- **Purpose:** Maintain WhatsApp-approved message templates (HSMs) used outside the 24-hour window.

> Two versions of this screen exist. Orgs with the `templateV2Enabled` service on get a redesigned form grouped into **Template Details · Message Content · Interactive Buttons · Media Attachment · Organization & Tags**; everyone else gets the classic single-column form described below. The underlying fields and WhatsApp approval flow are the same.

**List columns:** Title (with quality rating "Not Rated" or score) · Body · Category · Status (Approved/Pending/Rejected/Failed) · Reason (Rejected/Failed only) · Updated At.

**Toolbar:** Status filter (APPROVED default, PENDING, REJECTED, FAILED) · Tag filter · Search · **+ Add Template** · **Import** · **Sync** (sync templates from BSP) · **Bulk Apply** (apply samples/updates from CSV).

**Create/edit form fields:**

- **Language** \* (dropdown; defaults to English; disabled on edit).
- **Translate existing HSM?** — checkbox; if checked, **Existing Element name** dropdown appears so you can create a translation that shares the same shortcode.
- **Element name** _ — lowercase alphanumeric and underscores only (`^[a-z0-9_]+$`). Helper: \_"Only lowercase alphanumeric characters and underscores are allowed."\*
- **Title** _ — ≤50 chars. Helper: _"Define what use case does this template serve eg. OTP, optin, activity preference"\*.
- **Message** \* — ≤1024 chars; insert variables `{{1}}`, `{{2}}`, etc.
- **Variables (Template Variables)** — for each `{{n}}` in the body, define an example value (used for approval and preview). Error: _"Variable is required" / "Text cannot be empty"_.
- **Footer** — ≤60 chars (optional).
- **Add buttons** — checkbox; opens button section with type radio (**Call to Action** / **Quick Reply** / **WhatsApp Form**).
  - Call to Action: pick **Phone Number** or **URL**, set Title and Value; URL Type Static/Dynamic; max 2 buttons.
  - Quick Reply: text-only buttons (Value).
  - WhatsApp Form: pick a published form, button title, and screen.
- **Category** \* — **Utility** or **Marketing**. (WhatsApp's Authentication category is not offered by Glific.)
- **Attachment Type** — TEXT (default), IMAGE, VIDEO, DOCUMENT; "UPLOAD ATTACHMENT" appears if Google Cloud Storage is configured.
- **Attachment URL** — required when type is set; validated on blur.
- **Tag** — create-or-pick autocomplete.

**Submit button:** **Submit for Approval** (create) / **Save** (edit). On submit the template goes to **Pending** while WhatsApp reviews. Once **Approved** the template can be used in chat and in flows. **Sync** pulls the latest WhatsApp status.

**Right-side simulator** previews the template with substituted variables, footer, attachment, and buttons.

---

### Triggers

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

- **URL:** `/trigger`, `/trigger/add`, `/trigger/:id/edit`
- **Purpose:** Schedule a flow to run automatically against a collection at a specific time.

**List columns:** Title (formatted `{flow.name}_{startDateTime}` with active/inactive clock icon and tooltip "Repeat: {frequency}({days})") · End Date · Collections.

**Create/edit form fields:**

- **Select flow** _ — only published flows. While selecting, helper text shows _"Validating flow…"\* and surfaces warnings if flow is missing required nodes.
- **Date range** \* — Start date and End date (start ≥ today, end > start). Disabled on edit.
- **Time** _ — start time. Validation: _"Start time should be greater than current time"\* if start date is today.
- **Repeat** \* — Does not repeat / Hourly / Daily / Weekly / Monthly.
- **Frequency Values** — appears based on repeat: Weekly → **Select days** (Mon–Sun checkboxes), Monthly → **Select dates** (helper: _"If you are selecting end of the month dates… 30, 31… will default to the last day of that month."_), Hourly → **Select hours** (0–23).
- **Select Trigger Type** — radio: **WABA Collections** / **WhatsApp Group Collections** (when WhatsApp Groups enabled).
- **Select collection** \* — multi-select autocomplete.
- **isActive** — toggle to enable/disable.

**Per-row actions:** View · Copy (toast: _"Copy of the trigger has been created!"_) · Edit · Delete.

---

### Collections

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Collections/

- **URL:** `/collection`, `/collection/add`, `/collection/:id/edit`, `/collection/:id/contacts`, `/collection/:id/groups` (group memberships); group-collection variants under `/group/collection`.
- **Purpose:** Group contacts (or WhatsApp groups) for targeted messaging, flow start, staff assignment, and triggers.

**List columns:** Label · Description · Contacts/Groups (clickable count linking to membership view).

**Per-row actions:** Add Contacts (opens AddToCollection dialog) · Edit · Delete · Export (downloads `collection_{timestamp}.csv`).

**Create/edit form fields:**

- **Title** _ — ≤50 chars; uniqueness checked (_"Title already exists."\*).
- **Description** — 3-row textarea.
- **Assign staff to collection** — multi-select; not shown for WhatsApp group collections. Helper: _"Assigned staff members will be responsible to chat with contacts in this collection"_.

**Membership view (`/collection/:id/contacts`):** lists Name (with masked phone), Status, other Collections. Buttons to **Add Contacts** (search dialog) and **Remove** selected.

---

### Contacts & Contact Management

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Contact%20Profile%20%26%20History/

#### Screen: Contact Management (bulk import)

- **URL:** `/contact-management`
- **Purpose:** Bulk-import contacts from CSV; manage admin-level contact operations.
- **How to access:** Manage → **Contacts** (Admin only).

**Workflow:** click **Continue** → opens **Upload Contacts** dialog with:

- File upload (CSV only).
- **Select collection** \* autocomplete (where the imports go).
- **Please confirm if contacts are opted in.** checkbox \* (legally required).
- **Download Sample CSV** link.

On submit: toast _"Contact import is in progress."_ + dialog _"Please check notifications to see the status of import."_ with a **Go to notifications** button. Async — open `/notifications` to monitor.

#### Screen: Contact Profile

- **URL:** `/contact-profile/:id/*`
- **Purpose:** View and manage a single contact's data.
- **Tabs:** **Profile** · **Details** · **History**.

**Profile tab:**

- Phone (masked by default; eye icon toggles "Show number" / "Hide number").
- Collections — comma-separated.
- Assigned to — staff names (or "None"). Shows up to 2 names then "+N more".
- Last Message timestamp.
- Status — VALID / INVALID / PROCESSING (and BLOCKED via blocked list).
- Custom contact fields — listed as label: value.

**History tab events:** `contact_flow_started`, `contact_flow_ended`, `contact_fields_updated` (e.g., "{field} is updated to {new} from {old}"), with timestamps.

#### Screen: Blocked contacts

- **URL:** `/blocked-contacts`
- **Columns:** Name · Phone Number.
- **Action:** **Unblock** with confirmation _"Do you want to unblock this contact"_. Toast: _"Contact unblocked successfully"_.

#### Screen: Contact Variables (custom fields)

- **URL:** `/contact-fields`
- **Purpose:** Define custom fields beyond Name/Phone/Language.
- **Fields:**
  - **Name** \* — display label.
  - **Shortcode** \* — lowercase letters and underscores only (`^[a-z_]+$`, error _"Only lowercase alphabets and underscore is allowed."_); referenced in flows as `@contact.fields.<shortcode>`.

---

### Tags

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Tags/

- **URL:** `/tag`, `/tag/add`, `/tag/:id/edit`
- **Purpose:** Categorize contacts/messages.
- **Field:** **Name** \* (label).

---

### Searches (Saved Searches)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Searches/

- **URL:** `/search`, `/search/add`, `/search/:id/edit`
- **Purpose:** Save complex chat filters as named pills usable in the chat saved-search toolbar.
- **Fields:** **Title** _ (≤20 chars) · **Description** _ · **Enter name, label, keyword** (free text term) · **Includes Labels** · **Includes Collections** · **Includes Staff** · **Date Range** (toggle **Use Expression** for dynamic Timex expressions like `<%= Timex.shift(Timex.today(), days: -2) %>`).

---

### Interactive Messages

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

- **URL:** `/interactive-message`, `/interactive-message/add`, `/interactive-message/:id/edit`
- **Purpose:** Build button / list / location-request messages used in flows or sent from chat.

**Type \*** — a dropdown: **Reply buttons** (QUICK_REPLY) · **List message** (LIST) · **Location request** (LOCATION_REQUEST). Locked once the message exists; everything else stays editable.

**Fields:**

- **Title** _ — _"Only alphanumeric characters and spaces are allowed"\*.
- **Message Body** \* — supports `@` variables.
- **Footer** (Quick Reply only).
- **Options/Buttons:** Quick Reply gives an array of text buttons (max 3 buttons). List gives sections, each with a section title (≤24 chars) and items (title ≤20 chars, description ≤72 chars; up to 10 total options).
- **Show Title in Message** checkbox.
- **Attachment Type** + **Attachment URL** (Quick Reply only): IMAGE/VIDEO/DOCUMENT.
- **Allow Dynamic Media** checkbox — bypasses pre-validation.
- **Tag** autocomplete.
- **Language bar** for translations; warning displayed if unsaved changes when switching language.

**Right-side simulator** previews the rendered message with buttons/list selectable.

---

### WhatsApp Forms

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

- **URL:** `/whatsapp-forms`, `/whatsapp-forms/add`, `/whatsapp-forms/:id/edit`, `/whatsapp-forms/:id/configure`
- **Purpose:** Build WhatsApp-native forms with structured questions; sent via templates that include a form button.
- **Fields:** **Title** _ (≤50) · **Description** · **Categories** _ (multi-select, ≥1) · **Data Storage (Optional)** Google Sheet URL — _"Responses will get saved in your Big Query project by default. Add a writable Google Sheet if you'd like to see and share responses more easily."_
- **Configure** workflow builds the form's screens / fields. Once published, form editing is disabled.
- **Activate / Deactivate** toggles available; toasts _"Form activated successfully"_ / _"Form deactivated successfully"_.
- **Sync** action pulls forms from WhatsApp; failure shows _"Sorry, failed to sync whatsapp forms updates."_

---

### Triggers, Tickets, Webhook Logs, Notifications

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

#### Webhook Logs

- **URL:** `/webhook-logs`
- **Purpose:** Audit external HTTP calls made by Call Webhook nodes.
- **Columns:** Time (sortable desc default) · URL · Status (color-coded) · Status Code · Error · Method · Request Header · Request JSON · Response JSON. Each cell has a copy-to-clipboard control and JSON popover view. Search by `contact_phone` or `url`. No edit/delete.

#### Notifications

- **URL:** `/notifications`
- **Purpose:** Monitor system events (failed messages, sync status, contact upload, etc.).
- **Columns:** unread dot · Timestamp · Category (Message / Flow / Templates / Partner / Ticket / WA Group / Contact Upload / Custom Certificates) · Severity (Critical / Warning / Info) · Entity (JSON with `name`) · Message.
- **Severity filter (radio):** All / Critical / Warning / Info.
- **Auto-mark-as-read:** items load as unread, then marked read 1 second later.
- **Check action** navigates to the relevant entity:
  - Message → `/chat/{id}`
  - Flow → `/flow/configure/{flow_uuid}`
  - Templates → `/template/{id}/edit`
  - Partner → `/settings/{shortcode}`
  - Ticket → `/tickets`
  - WA Group → `/group/chat/{id}`
  - Contact Upload → downloads CSV status report
  - Custom Certificates → `/certificate/{template_id}/edit`

#### Support Tickets

- **URL:** `/ticket`
- **Purpose:** Track agent escalations created by **Open Ticket** flow nodes.
- **Actions:** Close tickets (toast _"Tickets closed successfully"_).

---

### AI Assistants

📖 Source: https://glific.github.io/docs/docs/Integrations/Creating%20and%20modifying%20assistants%20in%20Glific/

- **URL:** `/assistants`, `/assistants/add`, `/assistants/:assistantId`
- **Purpose:** Configure OpenAI Assistants. Flows use them through **Call Webhook** with method `FUNCTION` — `filesearch-gpt` / `voice-filesearch-gpt` — not through a dedicated AI node (Glific has none).

**Fields:**

- **Name** _ — _"Give a recognizable name for your assistant"\*.
- **Model** \* — the dropdown is served by the backend model catalogue, not hard-coded in the UI, so the exact list changes over time. Models are grouped as **recommended** (currently `gpt-5.6-luna` "Best value", `gpt-5-nano` "Fastest", `gpt-5-mini` "Budget", `gpt-5.6-terra` and `gpt-5.4` "All-rounder") and **deprecating** (`gpt-4o`, `gpt-4o-mini`). An assistant created without an explicit model still gets `gpt-4o`.
- **Instructions/Prompt** _ — _"Set the instructions according to your requirements."\* Expandable textarea.
- **Temperature** — slider 0.0–2.0 (default 0.1). Helper: _"Controls randomness: Lowering results in less random completions…"_.
- **Knowledge Base Files** — drag-and-drop. Accepts `.csv .doc .docx .html .htm .md .markdown .pdf .txt`. Max 20 MB per file, up to 10 concurrent uploads, automatic retry up to 5 times. Status pills: uploading / queued / failed / attached. Toast _"$oversizedFileNames were/was above 20MB"_ if too large.
- **Version Description / Notes** — free text per-version.

**Actions:** **Save** · **Clone** (warning _"Cloned assistants may behave differently from the original…"_) · **Delete** (confirmation) · version selector (with **Set as live**).

**Knowledge base creation** is async — toast _"Knowledge base creation in progress, will notify once it's done"_.

---

### Sheet Integration (Google Sheets)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

- **URL:** `/sheet-integration`, `/sheet-integration/add`, `/sheet-integration/:uuid/edit`
- **Purpose:** Connect a sheet for the **Link Google sheet** flow node to read or write rows.
- **Fields:**
  - **Allowed Operations** — _"What operations are allowed to be performed in the sheet?"_ — Read / Write / Read & Write (default Read).
  - **Sheet Name** \*.
  - **URL** \* — link to the Google Sheet (with **View Sample**).
  - **Auto Sync** — _"Data will be synced from the sheet on a daily basis"_.
- **Permissions:** the GCP service account configured in `/settings/google_sheets` must have read/write access to the sheet (share the sheet with the service account email).

---

### Certificates

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Custom%20Certificates/

- **URL:** `/certificates`, `/certificate/add`, `/certificate/:uuid/edit`
- **Purpose:** Generate personalized certificates from a Google Slides template.
- **Fields:** **Title** _ (≤40) · **Description** (≤150) · **URL** _ — Google Slides link, must end with `slide=id.p` (regex `^https://docs.google.com/presentation/d/[a-zA-Z0-9_-]+/edit.*$` and `slide=id\.g…$`).
- **Sizing guidance** (helper text): Landscape 3300×2550 px · Portrait 816×1056 px · Badges (square) ≥ 600×600 px.

---

### Polls (WhatsApp Group Polls)

📖 Source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/Sending%20Polls%20To%20WhatsApp%20Groups/

- **URL:** `/group/polls`, `/group/polls/add`, `/group/polls/:id/edit`
- **Purpose:** Create polls for WhatsApp groups (when feature enabled).

---

### Staff Management

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

- **URL:** `/staff-management`, `/staff-management/:id/edit`
- **Purpose:** Manage user accounts, roles, and collection access.
- **Fields:**
  - **Username** \* (text).
  - **Phone Number** — read-only (set from contact).
  - **Roles** \* — single-select for standard orgs, multi-select for orgs with dynamic roles. Managers cannot grant Admin.
  - **Assigned to collection(s)** — multi-select.
  - **Can chat with contacts from assigned collection only** — checkbox (Staff role only).
- **Help dialog:** clicking "help?" opens a modal explaining each role.
- **Self-demotion:** if an Admin removes their own Admin role, they're auto-logged-out (`/logout/user`).

---

### Roles

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

- **URL:** `/role`, `/role/add`, `/role/:id/edit`
- **Visibility:** only when org doesn't use dynamic roles.
- **Fields:** **Label** _ · **Description** _.

---

### Organizations (multi-tenant — Glific_admin)

- **URL:** `/organizations`, `/organizations/:id/extensions`, `/organizations/:id/customer`
- **Purpose:** Manage all NGOs on the Glific platform; install extensions; access customer info.

---

### Consulting Hours (Glific_admin)

- **URL:** `/consulting-hours/`
- **Purpose:** Track support consulting time delivered by the Glific team.
- **Fields:** **Select Organization** _ · **Participants** _ · **Select date** _ · **Enter time (in mins)** _ — must be a positive multiple of 15 · **Billable / Non-Billable** _ (radio) · **Support team** _ · **Notes** \*.

---

### My Account

- **URL:** `/myaccount`
- **Purpose:** Change your password and account preferences.

---

## Step-by-Step Guides

### 1. Setting up a new chatbot from scratch

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Getting%20Started%20with%20Glific/

1. Open `/settings/organization` and fill **Organization name**, **Supported languages**, **Default language**, **Webhook signature**, **Organization phone number**, then **Save**.
2. Open `/settings/gupshup` and enter **App Name**, **API Key**, **App ID** from your Gupshup dashboard. Confirm — credentials lock after first save.
3. (Optional) Configure providers: `/settings/google_sheets`, `/settings/bigquery`, `/settings/google_cloud_storage`, `/settings/google_slides`, `/settings/maytapi`. There is no OpenAI or Dialogflow settings tile — the backend excludes them from the provider list.
4. Open `/settings/organization-flows` and pick a **New contact flow** (the flow that runs on first contact) and a **Default flow** (out-of-hours fallback).
5. Add staff via `/staff-management` — Username, Roles, optional collection assignment.
6. Build your first flow (see guide #2).
7. Approve at least one HSM template (see guide #5).
8. Go live by sending the new contact your WhatsApp business number.

### 2. Creating your first flow with a keyword trigger

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Getting%20Started%20with%20Glific/

1. Sidebar → **Flows** → **Flows** → **+ Create**.
2. Fill **Name** (e.g. "Welcome"), **Keywords** (e.g. `hi,hello,start`), check **Is active?**, **Save**.
3. Click **Configure** → flow editor opens.
4. Drag **Send Message** onto the canvas → enter "Hi! What's your name?" → **Ok**.
5. Add **Wait for Response** → connect from Send Message → set Result name "name" → **Ok**.
6. Add **Update Contact** → pick the contact variable you want to store it in (create one at `/contact-fields` first, e.g. shortcode `name`) → value `@results.name` → **Ok**. Glific's Update Contact node does **not** offer the built-in Name or Status properties — only Language, Channel and your own contact variables.
7. Add a final **Send Message** "Thanks @contact.fields.name!" → connect.
8. **Preview** → simulate the conversation.
9. **Publish** → confirm. Toast: _"The flow has been published"_. Now sending "hi" to your bot triggers it.

### 3. Sending a broadcast message to a collection

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Collections/

1. Open **Manage** → **Collections** → click the collection you want.
2. Use **Chats** → **Collections** tab → pick the collection.
3. Pick a **Speed Send** or **HSM Template** from the down-arrow picker (HSM is required if any contact's 24-hour window is closed).
4. Click **Send**.

### 4. Recording flow responses to a Google Sheet

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

1. Share your Google Sheet with the service-account email shown in `/settings/google_sheets` (Editor access).
2. Go to `/sheet-integration` → **+ Add** → **Allowed Operations: Write** → paste the **URL**, set a **Sheet Name** → **Save**.
3. In your flow editor, add **Link Google sheet** node → pick the sheet → map flow results / contact fields to columns → **Ok**.
4. Publish the flow. Each flow run appends a row.

### 5. Creating and submitting an HSM template

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

1. Sidebar → **Quick tools** → **HSM Templates** → **+ Add Template**.
2. Set **Language**, **Element name** (e.g. `order_confirmation`), **Title**, **Message** (use `{{1}}` for variables) → fill **Variables** with example values.
3. Pick **Category** (Utility or Marketing). Optionally add buttons / footer / attachment.
4. **Submit for Approval**. Status starts at PENDING.
5. Click **Sync** later to refresh status. Once APPROVED you can use it from chat or flow.

### 6. Setting up a scheduled trigger

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

1. Sidebar → **Quick tools** → **Triggers** → **+ Add**.
2. **Select flow** (must be Published).
3. Pick **Date range** and **Time**. Pick **Repeat** (e.g., Weekly) and **Select days** (e.g., Mon, Wed, Fri).
4. **Select Trigger Type** (WABA Collections) → **Select collection**.
5. **Save**. The trigger fires on schedule and runs the flow for every member of the collection.

### 7. Configuring BigQuery sync

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/BigQuery%20Setup%20and%20link%20with%20Glific/

1. In Google Cloud, create a service account with BigQuery Admin and Storage Admin roles, download JSON key.
2. Open `/settings/bigquery` → toggle **Active?** → paste JSON credentials and project ID → **Save**.
3. Sync runs automatically; check `/notifications` for status.

### 8. Setting up an AI Assistant with file search

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

1. `/assistants` → **+ Add**.
2. Fill **Name**, pick a **Model** from the dropdown, write **Instructions**.
3. Drag knowledge files (PDF/DOCX/MD) into the upload area. Wait for status to become **attached**. Files >20 MB are rejected.
4. **Save** → wait for _"Knowledge base creation in progress, will notify once it's done"_.
5. In a flow, add **Call Webhook** → Method **FUNCTION** → `filesearch-gpt` → in the body pass the assistant id and the question → set a **result name** → **Ok** → publish. Branch on `@results.<result_name>` afterwards. (There is no "Call AI" node in Glific.)

### 9. Managing contact opt-in / opt-out

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

- **Opt-in:** create an **Optin flow** in `/settings/organization-flows`. Trigger it via the keyword users send (e.g. "JOIN").
- **Opt-out:** contacts opt out through the BSP (replying STOP on WhatsApp), which Glific records as `optout_time`. In a flow you can additionally listen for a keyword with **Wait for Response** and route the contact into an "Opted out" collection with **Add to Collection** — the Update Contact node cannot set contact status, so don't try to set BLOCKED from a flow.
- **Block** in chat: dropdown → **Block Contact** → confirm.
- **Unblock**: `/blocked-contacts` → **Unblock**.

### 10. Creating Interactive Messages (buttons / lists)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

1. `/interactive-message` → **+ Add**.
2. Pick **Reply Buttons** or **List Message**.
3. Fill **Title**, **Message Body**, configure buttons or list items.
4. (Optional) attach IMAGE/VIDEO/DOCUMENT, set Tag, add translations via the language bar.
5. **Save**. Use it in chat (down-arrow → Interactive msg) or in flows (**Interactive Message** node).

### 11. Setting up a webhook integration in a flow

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

1. In flow editor, add **Call Webhook** → enter URL, Method, Headers (Content-Type: application/json + auth), Body (use `@contact.field` and `@results.x` substitutions).
2. Method is **GET**, **POST**, or **FUNCTION** (Glific's built-in webhooks) — PUT/DELETE/PATCH are not available. Branch on the two exits, **Success** and **Failure**.
3. After the webhook, optionally add **Save Flow Result** to capture parts of the response.
4. **Publish**. Inspect calls in `/webhook-logs`.

### 12. Importing contacts from CSV

1. Manage → **Contacts** → **Continue**.
2. Download **Sample CSV**, fill it (Phone is mandatory; add custom-field columns matching your `/contact-fields` shortcodes).
3. Upload, **Select collection**, check **Please confirm if contacts are opted in.**, **Upload**.
4. Track via `/notifications` (Contact Upload category) → **Check** to download a status CSV listing successes/errors.

### 13. Multi-language flows

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/

1. Add languages in `/settings/organization` → **Supported languages**.
2. In a flow, click **Translate** in the editor → **Automatic translation** for AI translation, or export → fill → import a CSV.
3. Speed sends, HSM templates, and Interactive messages all have a **Language bar** for per-language content.
4. Switch a contact's language with **Update Contact** → field **Language** → flow renders in that language.

### 14. Testing a flow before going live

📖 Source: https://glific.github.io/docs/docs/Starter%20Kit/12%20Pre-launch%20Chatbot%20Checks/

1. Open the flow in the editor → **Preview**.
2. Simulator opens — type messages as if you were the contact.
3. Step through each branch. Use **Reset** if needed.
4. When confident, **Publish**.

### 15. Setting up GCS for media storage

📖 Source: https://glific.github.io/docs/docs/Pre%20Onboarding/Google%20Cloud%20Storage%20Setup%20-%20GCS/

1. Create a GCS bucket and a service account with Storage Admin.
2. Open `/settings/google_cloud_storage` → toggle **Active?** → paste credentials → **Save**.
3. After this, the **Attachment Type → UPLOAD ATTACHMENT** option appears on HSM templates and elsewhere.

---

## Settings Reference

### Settings landing page (`/settings`)

A grid of tiles. Top tiles always present: **Organization** ("Manage organization name, supported languages.") · **Flows** ("Manage organization flows.") · **Billing** ("Setup for glific billing account"). The remaining tiles are loaded dynamically from the backend Provider list.

### `/settings/organization` — Organization

- **Organization name** \*.
- **Supported languages** \* (multi-select).
- **Default language** \* (single-select; must be one of the Supported languages).
- **Webhook signature** \*.
- **Organization phone number** _ (≤30 chars, copy button to clipboard). If `allowBotNumberUpdate` is set, updates trigger confirmation _"Are you sure you want to update the phone number? It will not be possible to update the number later."\*
- **WhatsApp tier** — read-only display (quality rating).
- **Receive warning mails?** — checkbox; reveals:
  - **Low balance threshold for warning emails** — number ≥0; alerts once a week.
  - **Critical balance threshold for warning emails** — number ≥0; alerts every two days.

### `/settings/organization-flows` — Flows config

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/New%20Contact%2C%20Default%20flow%20Out%20of%20office%20hours%20notifications/

- **Default flow** checkbox; reveals **Select flow**, **Select days**, **All day** checkbox or **Start**/**Stop** time pickers, and a fallback **Select flow (all other days & times)**.
- **New contact flow** checkbox + **Select flow**.
- **Optin flow** checkbox + **Select flow**.
- **Regular expression flow** checkbox + **Select flow** + **Regular expression** + **Regular expression modifiers**.

### `/settings/billing` — Billing

Pricing displayed:

- One-time setup INR 15,000 / $200 + tax (incl. 5h consulting + 1h onboarding).
- Monthly INR 9,500 / $120 + tax (up to 250k messages).
- Per staff over 10: INR 150 / $2.
- Per 1k messages up to 1M: INR 10 / $0.14; above 1M: INR 5 / $0.07.
- Suspended accounts INR 1,500/mo + tax.

Form: **Coupon Code** + **Apply** · **Your Organization Name** _ · **Email ID** _ (valid email) · **Card Details** (Stripe). When subscription active, panel shows **Visit Stripe portal** button.

### `/settings/{provider}` — Providers (dynamic)

Loaded from the backend provider list. Each provider has `keys` (config) and `secrets` (credentials). The backend deliberately **hides** several seeded providers from this screen — `goth`, `kaapi`, `gupshup_enterprise`, `navana_tech`, `google_asr`, `dialogflow` and `open_ai` are excluded, and trial orgs additionally don't see `google_cloud_storage`. So there is no `/settings/openai` or `/settings/dialogflow` tile; OpenAI is provided centrally by Glific.

Tiles you can actually expect:

- **Gupshup** (`gupshup`, required) — App Name, API Key, App ID (each lockable), API End Point (default `https://api.gupshup.io/sm/api/v1`), Worker / Handler / URL (read-only). Once required fields are set, the form is locked with a confirmation dialog.
- **BigQuery** (`bigquery`).
- **Google Cloud Storage** (`google_cloud_storage`) — the shortcode is the full name, not `gcs`.
- **Google sheet** (`google_sheets`).
- **Google Slides** (`google_slides`) — used by Custom Certificates.
- **Maytapi** (`maytapi`) — WhatsApp Groups. Confirmation: _"Are you sure you want to change these credentials? All information related to this account will be deleted. All data has already been backed up in BigQuery."_
- **Exotel** (`exotel`) — missed-call opt-in callback.

Each provider page has an **Active?** toggle (required fields enforced when active) and per-field labels read from the backend schema.

---

## Error Messages

Format: **"Exact text"** — Cause → Fix.

### Chat & messaging

- **"Flow started successfully."** — Toast after starting a flow on a contact.
- **"Your flow will start in a couple of minutes."** — Toast after starting a flow on a collection.
- **"Contact blocked successfully."** / **"Contact unblocked successfully"** — Confirms block/unblock action.
- **"Conversation cleared for this contact."** — Toast (warning severity) after clearing chat history; data is permanently deleted.
- **"The contact is blocked"** — Send-area banner. Fix: unblock from `/blocked-contacts` if intentional.
- **"Flow terminated successfully"** / **"Sorry, failed to terminate flow. Please try again."** — Result of Terminate flows. Fix: retry; if persistent, check that the flow run is still active.
- **"$numberAdded contact(s) were added"** / **"$numberAdded group(s) were added"** — Bulk add to a collection.
- **"Sorry, unable to send the attachment."** — Attachment upload/send failed. Fix: check format and size; retry.
- **"Sorry, unable to upload audio."** — Voice upload failed. Fix: re-record and retry.
- **"Message has been successfully added to speed sends."** — Saved a chat message as a speed send.
- **"Option disabled because the 24hr window expired"** — Tooltip on Send when contact is HSM-only.

### Flows

- **"The flow has been published"** — Publish success.
- **"Flow counts have been reset"** / **"An error occured while resetting the flow count"** — Reset Flow Count outcome.
- **"No keywords found to share the responder link"** — Add keywords to flow first.
- **"Flow exported successfully"** — Export download started.
- **"An error occured while importing the flow"** — Import failed. Fix: verify the JSON is a valid Glific export.
- **"Flow has been translated successfully"** / **"An error occured while translating flows."** / **"An error occured while exporting flow translations"** — Translation outcomes.
- **"Sorry! Simulator timeout. Please click Preview again"** — Simulator hit a timeout (often an infinite loop or external call). Fix: simplify the flow, retry.
- **"Sorry! Failed to get simulator"** — Refresh and retry.
- **"View Only Mode - …"** — Another user is editing. Use **Take Over** or wait.

### Templates / Interactive / Forms

- **"$capitalListItemName created/edited/deleted successfully!"** — Generic CRUD confirmation across forms.
- **"An error occured while uploading the file"** — Media upload failed.
- **"Error! Invalid media url"** — Attachment URL not reachable. Fix: provide a public URL.
- **"Interactive Message Exported / Imported / Translated Successfully"** — Action confirmations.
- **"HSM queued for sync. Check notifications for updates."** / **"Sorry, failed to sync HSM updates."** — HSM Sync outcomes.
- **"Form published successfully"** / **"Form activated successfully"** / **"Form deactivated successfully"**.
- **"Please fix the errors in the form before publishing."** — Form has validation issues.
- **"Error saving form revision"** — Auto-save failure. Fix: check connection and save manually.
- **"Sorry, failed to sync whatsapp forms updates."** — Forms sync failed.

### Collections / Contacts

- **"Contact has been removed successfully from the collection."** / **"Group has been removed successfully from the collection."** — Successful removal.
- **"Removed Contact from Group"** — Removed contact from a WA group.
- **"An error occured while exporting the collection"** — Retry export.
- **"Downloaded the status of the contact upload"** — Bulk import status downloaded.
- **"Contact import is in progress."** + **"Please check notifications to see the status of import."** — Async import started.
- **"Sorry! An error occured while deleting the contact field"** / **"… while updating the contact field"** — Contact-field admin failures.
- **"Contact field deleted successfully!"** — Success.

### Assistants / AI

- **"Assistant created successfully"** / **"Assistant cloned successfully"** / **"Assistant clone failed"** — CRUD confirmations.
- **"Changes saved successfully"** — Generic save confirmation.
- **"Version set as live successfully"** — Assistant version promoted to production.
- **"$oversizedFileNames were/was above 20MB"** — Knowledge-base file too big. Fix: split or shrink.
- **"Some file uploads failed, hover the failure to see the reason"** — Hover the failed file to see why.
- **"Remove or re-upload files that failed before saving."** — Clean up failed entries before Save.
- **"Knowledge base creation in progress, will notify once it's done"** — Async KB build started.
- **"Golden QA uploaded successfully"** / **"Failed to upload Golden QA"** / **"No file selected for Golden QA upload"** — AI Evaluation upload outcomes.

### Settings & sync

- **"Organization updated successfully"** / **"Organization deleted successfully"** — Org admin actions.
- **"Your billing account is setup successfully"** — Stripe setup completed.
- **"Your changes have been autosaved"** — Auto-save tick.
- **"Copied to clipboard"** / **"Sorry, cannot copy content over insecure connection"** — Clipboard requires HTTPS.
- **"Whatsapp groups synced successfully."** / **"Sorry, failed to sync whatsapp groups."** — WA Groups sync.
- **"Sorry! An error occurred while fetching data from the Google sheet."** — Sheet read failed. Fix: confirm the sheet is shared with the service account.

### Bulk / CSV

- **"Templates applied successfully. Please check the csv file for the results"** — Bulk apply succeeded.
- **"Templates were processed with errors. Please check the csv file for details."** — Some rows failed; download CSV.
- **"Please upload a valid CSV file"** / **"An error occured! Please check the format of the file"** — File parse failed.

### Generic

- **"Sorry! An error occurred"** / **"Sorry! An error occurred!"** — Generic catch-all. Retry; check console / contact support.
- **"Email Sent Successfully!"** — Sent from the HSM list's _"Report Template … to Gupshup"_ dialog, which emails Gupshup support about a rejected/failed template. Nothing to do with flows: Glific has no Send Email node.
- **"File uploaded successfully"** / **"File upload failed. Please try again."**.
- **"Tickets closed successfully"** — Ticket close action.
- **"Sorry! Id not found"** / **"Sorry! UUID not found"** — Stale link or deleted record.
- **"Failed to download QR code"** / **"Failed to update pin status"** / **"Error reverting to version"** / **"Successfully reverted to selected version"** — Misc admin actions.

### Form-validation messages (Yup)

These appear inline below input fields:

- Required: _"Input required"_, _"Name is required."_, _"Email is required."_, _"Phone number is required."_, _"OTP is required"_, _"Title is required."_, _"Description is required."_, _"Collection is required"_, _"Roles is required"_, _"Language is required."_, _"Type is required."_, _"Flow is required"_, _"Category is required."_, _"Form is required."_, _"Screen is required."_, _"Instructions are required"_, _"Model is required"_, _"Variable is required"_, _"Shortcode is required."_, _"Evaluation name is required"_, _"Please select a Golden QA dataset"_, _"Please select an AI Assistant"_.
- Email format: _"Email is invalid"_, _"Enter a valid email."_.
- Length: _"Title is too long."_, _"Title length is too long."_, _"Title should be less than 40 characters"_, _"Maximum 1024 characters are allowed"_, _"Description should be less than 150 characters"_, _"Name cannot be more than 250 characters."_, _"Please enter not more than 100 characters"_, _"Title can be at most 60 characters"_, _"Section title can be at most 24 characters"_, _"Description can be at most 72 characters"_, _"Button value can be at most 20 characters"_, _"Footer value can be at most 60 characters"_, _"Shortcode cannot be more than 8 characters."_, _"Username must be at least 3 characters"_, _"Organization must be at least 2 characters"_.
- Pattern: _"Only lowercase alphabets and underscore is allowed."_, _"Only lowercase alphanumeric characters and underscores are allowed."_, _"Name can only contain alphabets and spaces"_, _"Organization name can only contain alphabets and spaces"_, _"Invalid Pincode"_, _"Name can only contain lowercase alphanumeric characters and underscores"_.
- Numeric: _"TDS should not be negative"_, _"TDS amount should be less than or equal 10%"_, _"Duplication factor must be between 1 and 5"_, _"Please select a day"_, _"Please select a date"_.
- Conditional: _"At least one category must be selected."_, _"Please agree to the creation of staff account."_, _"Please agree to the terms and conditions."_, _"Please confirm if contacts are opted in."_.
- Date: _"End date should be greater than the start date"_, _"Start time should be greater than current time"_.
- Duplicates: _"Title already exists."_.

---

## Keyboard Shortcuts & Tips

- **Ctrl/Cmd + Enter** in chat input → send message.
- **Esc** in dialogs → close (cancel).
- **Eye icon** in contact profile → toggles masked/full phone.
- **Copy icon** anywhere → copies value to clipboard (requires HTTPS; otherwise _"Sorry, cannot copy content over insecure connection"_).
- **Hover a flow on the list** → tooltip shows next trigger / repeat schedule.
- **Hover a failed message** → shows WhatsApp error reason.
- **Hover a failed knowledge-base file** → shows upload failure reason.
- In flow editor, type-ahead works on most autocompletes (templates, flows, collections, contacts).
- Reusing a saved search: bookmark `/chat/saved-searches/:contactId` directly to deep-link into a search context.
- For long-running async actions (bulk import, sheet sync, knowledge-base build, HSM sync), the answer is always: open `/notifications`.

---

## Cheat sheet — URLs

| Path                                                                                                  | Screen                                                                                                         |
| ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `/chat`, `/chat/:contactId`                                                                           | Chat with contact                                                                                              |
| `/chat/collection`, `/chat/collection/:id`                                                            | Chat with collection                                                                                           |
| `/chat/saved-searches`, `/chat/saved-searches/:contactId`                                             | Saved-search results                                                                                           |
| `/group/chat`, `/group/chat/:id`                                                                      | WhatsApp group chat                                                                                            |
| `/group/chat/collection`                                                                              | Group collections chat                                                                                         |
| `/group/collection`, `/group/collection/add`, `/group/collection/:id/edit`                            | Group collections admin                                                                                        |
| `/group/polls`, `/group/polls/add`, `/group/polls/:id/edit`                                           | WA group polls                                                                                                 |
| `/group-details/:id/*`                                                                                | WA group details                                                                                               |
| `/flow`, `/flow/add`, `/flow/:id/edit`, `/flow/:id/view`                                              | Flows                                                                                                          |
| `/flow/configure/:uuid`                                                                               | Flow editor                                                                                                    |
| `/sheet-integration`, `/sheet-integration/add`, `/sheet-integration/:id/edit`                         | Google Sheets                                                                                                  |
| `/webhook-logs`                                                                                       | Webhook logs                                                                                                   |
| `/contact-fields/`                                                                                    | Contact variables (custom fields)                                                                              |
| `/ticket`                                                                                             | Support tickets                                                                                                |
| `/certificates`, `/certificate/add`, `/certificate/:id/edit`                                          | Certificates                                                                                                   |
| `/interactive-message`, `/interactive-message/add`, `/interactive-message/:id/edit`                   | Interactive messages                                                                                           |
| `/template`, `/template/add`, `/template/:id/edit`                                                    | HSM templates                                                                                                  |
| `/whatsapp-forms`, `/whatsapp-forms/add`, `/whatsapp-forms/:id/edit`, `/whatsapp-forms/:id/configure` | WhatsApp forms                                                                                                 |
| `/trigger`, `/trigger/add`, `/trigger/:id/edit`                                                       | Triggers                                                                                                       |
| `/search`, `/search/add`, `/search/:id/edit`                                                          | Saved searches                                                                                                 |
| `/speed-send`, `/speed-send/add`, `/speed-send/:id/edit`                                              | Speed sends                                                                                                    |
| `/tag`, `/tag/add`, `/tag/:id/edit`                                                                   | Tags                                                                                                           |
| `/notifications`                                                                                      | Notifications                                                                                                  |
| `/assistants`, `/assistants/add`, `/assistants/:assistantId`                                          | AI assistants                                                                                                  |
| `/collection`, `/collection/add`, `/collection/:id/edit`                                              | Collections                                                                                                    |
| `/collection/:id/contacts`, `/collection/:id/groups`                                                  | Collection membership                                                                                          |
| `/staff-management`, `/staff-management/:id/edit`                                                     | Staff                                                                                                          |
| `/contact-management`                                                                                 | Bulk contacts admin                                                                                            |
| `/contact-profile/:id/*`                                                                              | Contact profile                                                                                                |
| `/blocked-contacts`                                                                                   | Blocked contacts                                                                                               |
| `/role`, `/role/add`, `/role/:id/edit`                                                                | Roles                                                                                                          |
| `/organizations`                                                                                      | Organizations (Glific_admin)                                                                                   |
| `/consulting-hours/`                                                                                  | Consulting (Glific_admin)                                                                                      |
| `/settings`                                                                                           | Settings landing                                                                                               |
| `/settings/organization`                                                                              | Organization settings                                                                                          |
| `/settings/organization-flows`                                                                        | Org flow defaults                                                                                              |
| `/settings/billing`                                                                                   | Billing                                                                                                        |
| `/settings/{provider}`                                                                                | Provider config (gupshup, google_sheets, bigquery, google_cloud_storage, google_slides, maytapi, exotel)      |
| `/myaccount`                                                                                          | My account                                                                                                     |
| `/ai-evaluations`, `/ai-evaluations/create`, `/ai-evaluations/intro`                                  | AI evaluations                                                                                                 |
| `/analytics`                                                                                          | Data Analytics                                                                                                 |
| `/group/phones`                                                                                       | WhatsApp phones (WA Groups)                                                                                    |
