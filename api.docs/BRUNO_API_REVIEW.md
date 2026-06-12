# Glific Bruno API Collection — Review, Deviation & Design-Quality Report

> Scope: `api.docs/bruno/glific_api` (the Bruno collection) and `api.docs/includes/*.md`
> (the Slate reference) compared against the **real** GraphQL/REST surface in
> `lib/glific_web/schema/*` and `lib/glific_web/router.ex`.
> Generated for the `claude/glyphic-bruno-api-review` review.

---

## 1. Executive Summary

| Metric | Value |
|--------|-------|
| **Overall documentation score** | **54 / 100** |
| Real root operations in backend | **329** (148 queries · 165 mutations · 16 subscriptions) |
| Real top-level API modules | ~45 |
| Modules with **any** Bruno coverage | ~23 |
| Modules with **zero** Bruno coverage | **~22 (≈49%)** |
| Documented Bruno requests | 175 (≈167 GraphQL + 8 auth/onboard REST) |
| Unique real operations actually covered | ~110 |
| **Operation coverage** | **≈33%** |
| Documented requests that are **broken / wrong / nonexistent** | **≈24 (≈14%)** |
| Requests pointing at operations **that do not exist in the backend** | **11** (auto-score **0**) |

**Bottom line.** The Bruno collection is well-presented for the *happy-path* modules it
covers — each request carries a rich `docs` block (description, parameter tables, curl
example, sample response, FAQ) and the environment + auth-token bootstrap works out of the
box. But it has two systemic problems:

1. **Large coverage gap.** Only ~a third of the real API is documented. Roughly half of
   all backend modules (Billing, Tickets, Consulting Hours, Sheets, Interactive Templates,
   Webhook Logs, Notifications, Certificates, WA Groups / Managed Phones / Polls,
   Contacts Fields, Extensions, Roles CRUD, Flow Labels, Credentials, Template Tags,
   AI Evaluations, Ask Glific, WhatsApp Forms, …) have **no Bruno requests at all**.
2. **Copy-paste rot.** ~14% of the documented requests invoke the *wrong* operation or an
   operation that **does not exist** in the schema (e.g. "Delete a Flow" actually calls
   `updateFlow`; the entire "Messages Tags" folder is a clone of "Contact Tag";
   "Message Group" calls `createMessageGroup` which is not in the schema).

The design of the *underlying* APIs is mostly sound and generic (clean CRUD + filter/opts
pattern). The notable exceptions are the **Search/Conversation**, **Simulator**,
**dashboard-count subscriptions**, **unread/clear**, and **flow-editor lock** operations,
which are modeled directly around the Glific front-end and score low on reusability.

---

## 2. Scoring Rubric

**Per-API design score (0–5)** — rates how *generic / reusable* the API is, vs. how
*tightly coupled to the Glific UI* it is:

| Score | Meaning |
|------:|---------|
| **5** | Clean, generic, reusable. Standard CRUD or filter/opts pattern, no UI assumptions. |
| **4** | Generic with minor coupling, naming quirks, or batch/add-delete-ids shape. |
| **3** | Usable but moderately coupled to a Glific workflow, or returns opaque `json`. |
| **2** | Heavily coupled to the Glific UI (simulator, sidebar counts, conversation model). |
| **1** | Effectively a private UI backend endpoint; little general-purpose value. |
| **0** | **Documented operation does not exist in the backend, OR no documentation exists.** |

**Overall documentation score (0–100)** is a weighted blend of Readability (0.3),
Testability (0.3), and Ease-of-use/Completeness (0.4) — see §7.

---

## 3. Deviation Analysis — Defect Catalog

These are confirmed defects where the `.bru` request does **not** match the real API.
"Score 0" = the documented operation does not exist as written.

### 3a. Requests that call a NON-EXISTENT operation (score 0)

| # | Bruno request | Calls | Reality |
|---|---------------|-------|---------|
| 1 | `Message Group/Create Message Group` | `createMessageGroup` | **No such mutation anywhere in `lib/`.** Message→group sending is `createAndSendMessageToGroup`. |
| 2 | `Message Group/Delete a MessageGroup` | `deleteMessageGroup` | **No such mutation.** |
| 3 | `Contact Tag/Subscription for Create Contact Tag` | `createdContactTag` | **No `contact_tag` subscriptions exist.** Only `createdMessageTag`/`deletedMessageTag`. |
| 4 | `Contact Tag/Subscription for Delete Contact Tag` | `deletedContactTag` | **Nonexistent** (same as above). |
| 5 | `Messages Tags/Subscription for Create Contact Tag` | `createdContactTag` | Should be `createdMessageTag`; as written it is nonexistent. |
| 6 | `Messages Tags/Subscription for Delete Contact Tag` | `deletedContactTag` | Nonexistent. |
| 7 | `User Group/Subscription for Delete Contact Tag` | `deletedContactTag` | Copy-paste; **no user-group subscription exists.** |
| 8 | `Filesearch/Remove Files from Assistant` | `RemoveAssistantFile` | **No such mutation.** File removal is done via `updateAssistant`. |
| 9 | `Users/Get All Roles` | `query { roles }` | `roles` is only a **nested field**; the root query is `access_roles`. |
| 10 | `SaaS/Fetch ERP organizations` | `GET /v1/onboard/organizations` | **No such route** in `router.ex`. |
| 11 | `Users/Get a specific User by ID` | `provider(id)` | Pure copy-paste from Providers — returns provider fields, not a user. |

### 3b. Requests that call the WRONG (but existing) operation (score 0–1)

| # | Bruno request | Calls | Should call |
|---|---------------|-------|-------------|
| 12 | `Flows/Delete a Flow` | `updateFlow` | `deleteFlow` |
| 13 | `Flows/Export a Flow` | `publishFlow { export_data }` | `exportFlow` (query) |
| 14 | `Flows/Release a flow contact` | `flowGet` | `flowRelease` |
| 15 | `Languages/Count all Languages` | `language(id)` | `countLanguages` |
| 16 | `Languages/Get All Languages` | `messagesMedia` | `languages` |
| 17 | `Languages/Update a Language` | `language(id)` (query) | `updateLanguage` (mutation) |
| 18 | `Messages/Create a Message` | `countMessages` | `createMessage` |
| 19 | `Messages/Delete a Message` | `updateMessage` | `deleteMessage` |
| 20 | `Messages/Get a specific Message by ID` | `messages` (list) | `message` (singular) |
| 21 | `Messages/Send HSM Message to contacts of a collection` | `sendHsmMessage(groupId:)` | `sendHsmMessageToGroup` |
| 22 | `Messages Tags/Create Contact Tag` | `createContactTag` | `createMessageTag` |
| 23 | `Messages Tags/Update a Contact with tags…` | `updateContactTags` | `updateMessageTags` |

> The entire **"Messages Tags"** folder (4 files) is a verbatim clone of **"Contact Tag"**,
> so the real message-tag operations (`createMessageTag`, `updateMessageTags`,
> `createdMessageTag`, `deletedMessageTag`) are effectively **undocumented**.

### 3c. Minor / syntax issues

- `Organizations/Get Organization Services` uses `query organizationServices()` — an **empty
  argument list `()` is invalid GraphQL** — and selects an `errors` sub-field that the result
  type does not expose.
- Several requests keep stale variable signatures from the source they were copied from
  (e.g. `messagesMedia(filter: $filter …)` where `$filter` is never declared).
- Naming is inconsistent: PascalCase operation names (`DeleteAssistant`, `RemoveAssistantFile`,
  `Assistants`), snake_case (`create_knowledge_base`), and camelCase coexist within the same
  Filesearch folder.

---

## 4. Coverage Gap — Real Modules With NO Bruno Documentation (doc score 0)

Each of the following backend modules has **no Bruno request** (or only a broken stub).
On the documentation axis these all score **0**.

| Module | Representative real operations missing |
|--------|----------------------------------------|
| **Billing** | `billing`, `createBilling`, `createBillingSubscription`, `updatePaymentMethod`, `customerPortal`, `getCouponCode` |
| **Consulting Hours** | `consultingHours`, `createConsultingHour`, `updateConsultingHour`, `fetchConsultingHours` |
| **Tickets** | `tickets`, `ticket`, `createTicket`, `updateTicket`, `updateBulkTicket`, `fetchSupportTickets` |
| **Sheets** | `sheets`, `createSheet`, `syncSheet`, `deleteSheet` |
| **Interactive Templates** | `interactiveTemplates`, `createInteractiveTemplate`, `translateInteractiveTemplate`, `export/importInteractiveTemplate` |
| **Certificate Templates** | `certificateTemplates`, `createCertificateTemplate`, … |
| **Webhook Logs** | `webhookLogs`, `countWebhookLogs` |
| **Notifications** | `notifications`, `markNotificationAsRead` |
| **Contacts Fields** | `contactsFields`, `createContactsField`, `mergeContactsField` |
| **Extensions** | `extension`, `createExtension`, `updateOrganizationExtension` |
| **Flow Labels** | `flowLabels`, `flowLabel`, `countFlowLabels` |
| **Roles / Access Roles (CRUD)** | `accessRoles`, `createAccessRole`, … (only a broken `roles` stub exists) |
| **Credentials** | `credential`, `createCredential`, `updateCredential` |
| **Template Tags** | `createTemplateTag`, `updateTemplateTags` |
| **WA Groups** | `waGroups`, `waGroup`, `setPrimaryPhone` |
| **WA Managed Phones** | `waManagedPhones`, `countWaManagedPhones` |
| **WA Groups Collection** | `createWaGroupsCollection`, `updateCollectionWaGroup` |
| **Contact ↔ WA Group** | `listContactWaGroup`, `createContactWaGroup`, `syncWaGroupContacts` |
| **WA Polls** | `waPolls`, `createWaPoll`, `copyWaPoll` |
| **AI Evaluations** | `aiEvaluations`, `createEvaluation`, `goldenQas`, `evaluationScores` |
| **Ask Glific** | `askGlific`, `askGlificConversations`, `askGlificResponse` (subscription) |
| **WhatsApp Forms (+ Revisions/Responses)** | `whatsappForm`, `createWhatsappForm`, `publishWhatsappForm`, revisions |
| **Locations (list)** | `locations`, `location` (only `contactLocation` is documented) |

**Partially-covered modules** also miss many operations, e.g.:
- **Triggers**: only `createTrigger` documented → missing `triggers`, `trigger`, `updateTrigger`, `deleteTrigger`, `validateTrigger`, `countTriggers`.
- **Profiles**: only `createProfile` → missing `profile`, `profiles`, `updateProfile`, `deleteProfile`.
- **Session Templates**: missing `syncHsmTemplate`, `editApprovedTemplate`, `importTemplates`, `bulkApplyTemplates`, `reportToGupshup`, `createTemplateFormMessage`.
- **Organizations**: missing `organizationExportData/Config/Stats`, `dailyAppUsage`, `tracker`, `deleteOrganizationTestData`.
- **Flows**: missing `exportFlowLocalization`, `importFlowLocalization`, `inlineFlowLocalization`, `broadcastStats`, `startWaGroupCollectionFlow`.

---

## 5. UI-Coupling Analysis — APIs That Are Not Generic

These real operations are **tightly coupled to the Glific front-end** and score low on
reusability. They are legitimate product features, but a third-party integrator gets little
generic value from them.

| API | Why it is UI-coupled | Score |
|-----|----------------------|------:|
| `search` / `searchMulti` / `waSearch` | Returns a bespoke **`conversation`** object (contact + grouped messages) shaped exactly for the chat list / global search bar — not a generic query result. | 2 |
| `simulatorGet` / `simulatorRelease` (+ `simulator_release` subscription) | The "Simulator" is a Glific UI widget; these acquire/release a UI-only test contact. | 2 |
| `collection_count` / `bsp_balance` subscriptions, `collectionStats`, `savedSearchCount` | Power sidebar badges / wallet widget; opaque `json` payloads. | 2 |
| `markContactMessagesAsRead` ("Remove unread status") | Drives the unread badge; also mis-filed under the **Tags** folder. | 2 |
| `flowGet` / `flowRelease` | Acquire/release an **editor lock** on a flow for the visual builder. | 2 |
| `groupInfo`, `broadcastStats`, `validateMedia`, `bspbalance` | Return opaque `:json` blobs tailored to specific UI panels rather than typed schema. | 3 |
| `attachmentsEnabled`, `tracker`, `organizationServices` | UI feature-flag probes (booleans / service toggles). | 2–3 |
| `resetOrganization` / "Reset selected tables" | Glific-internal destructive admin op. | 2 |

**Generic, well-designed modules (score 4–5):** Contacts, Tags, Flows (CRUD), Groups,
Languages, Providers, Session Templates, Message Media, Users, Saved Searches CRUD,
Organizations CRUD, Authentication (REST). These follow a consistent
`filter` + `opts(limit/offset/order)` query pattern and `{ <entity> { … } errors { key message } }`
mutation envelope, which is clean and predictable.

---

## 6. Per-API Scored Report (by folder)

Status legend: ✅ correct · ⚠️ wrong-op (real op exists) · ❌ nonexistent op · 🧩 UI-coupled.

### Authentication (REST)
| Request | Status | Score |
|---|---|---:|
| Login / Create session / Renew / Delete session | ✅ | 5 |
| Create a new user (registration) | ✅ | 5 |
| Reset Password | ✅ | 5 |
| Send OTP (new / existing) | ✅ | 5 |

### Contacts
| Request | Status | Score |
|---|---|---:|
| Get All Contacts / Other filters / Get All Blocked | ✅ | 5 |
| Get by ID / Get by phone | ✅ | 5 |
| Count all Contacts | ✅ | 5 |
| Create / Update / Delete / Optin Contact | ✅ | 5 |
| Block / UnBlock (via `updateContact`) | ✅ recipe | 4 |
| Get Contact's Location | ✅ | 4 |
| Count / Get All Contact History | ✅ | 4 |
| Get a Simulator Contact | 🧩 `simulatorGet` | 2 |
| Release a Simulator Contact | 🧩 `simulatorRelease` | 2 |

### Contact Group / User Group / Message Group
| Request | Status | Score |
|---|---|---:|
| Create Contact Group | ✅ | 5 |
| Update group↔contacts / contact↔groups | ✅ add/delete-ids | 4 |
| Create User Group | ✅ | 5 |
| Update group↔users / user↔groups | ✅ | 4 |
| Subscription for Delete Contact Tag *(User Group)* | ❌ copy-paste | **0** |
| Create Message Group | ❌ `createMessageGroup` | **0** |
| Delete a MessageGroup | ❌ `deleteMessageGroup` | **0** |

### Contact Tag / Messages Tags
| Request | Status | Score |
|---|---|---:|
| Create Contact Tag | ✅ | 5 |
| Update contact↔tags | ✅ | 4 |
| Subscription Create/Delete Contact Tag | ❌ no such subscription | **0** |
| Messages Tags/Create Contact Tag | ⚠️ calls `createContactTag` not `createMessageTag` | 1 |
| Messages Tags/Update | ⚠️ wrong op | 1 |
| Messages Tags/Subscriptions (create/delete) | ❌ | **0** |

### Tags
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get by ID | ✅ | 5 |
| Create / Update / Delete Tag | ✅ | 5 |
| Remove unread status (`markContactMessagesAsRead`) | 🧩 mis-filed | 2 |

### Messages
| Request | Status | Score |
|---|---|---:|
| Count all Messages / Get All Messages | ✅ | 5 |
| Create and send Message / Scheduled | ✅ | 5 |
| Send HSM Message | ✅ | 5 |
| Update a Message | ✅ | 5 |
| Create and send to collection / SessionTemplate / Media HSM | ✅ | 4 |
| Delete Messages of a contact (`clearMessages`) | 🧩 "clear conversation" | 3 |
| Subscriptions (received/sent/sent_group/cleared/status) | 🧩 chat real-time | 3 |
| Create a Message | ❌ calls `countMessages` | **0** |
| Get a specific Message by ID | ⚠️ calls `messages` (list) | 1 |
| Delete a Message | ⚠️ calls `updateMessage` | 1 |
| Send HSM to a collection | ⚠️ `sendHsmMessage(groupId:)` | 1 |

### Message Media
| Request | Status | Score |
|---|---|---:|
| Count / Get all / Get by ID | ✅ | 5 |
| Create / Update / Delete Message Media | ✅ | 5 |
| Upload a file / buffer (`uploadMedia`/`uploadBlob`) | ✅ | 4 |
| Validate a Media URL and type (`validateMedia`→json) | 🧩 form validation | 3 |

### Flows
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get by ID | ✅ | 5 |
| Create / Update Flow | ✅ | 5 |
| Start flow for contact / group | ✅ | 5 |
| Resume / Terminate / Start WA group flow | ✅ | 4 |
| Copy / Import / Publish Flow | ✅ | 4 |
| Reset flow counts | ✅ | 3 |
| Get a flow (`flowGet` editor lock) | 🧩 | 2 |
| Delete a Flow | ❌ calls `updateFlow` | **0** |
| Export a Flow | ❌ calls `publishFlow{export_data}` | **0** |
| Release a flow contact | ⚠️ calls `flowGet` not `flowRelease` | 1 |

### Groups
| Request | Status | Score |
|---|---|---:|
| Create / Update / Delete / Get by ID / Get All | ✅ | 5 |
| Get All Organization Groups | ✅ | 4 |
| Get Group Info (`groupInfo`→json) | 🧩 | 2 |

### Languages
| Request | Status | Score |
|---|---|---:|
| Get by ID / Delete a Language | ✅ | 5 |
| Count all Languages | ❌ calls `language(id)` | **0** |
| Get All Languages | ❌ calls `messagesMedia` | **0** |
| Update a Language | ⚠️ calls `language` query | **0** |

### Providers
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get by ID / Create / Update / Delete | ✅ | 5 |
| Get BSP balance (`bspbalance`→json) | 🧩 | 3 |

### Organizations
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get by ID / Create / Update / Delete | ✅ | 5 (admin: 4) |
| Setup new organization (REST onboard/setup) | ✅ | 4 |
| Get Org Status / Timezones | 🧩 UI dropdown lists | 3 |
| Check attachment support (`attachmentsEnabled`) | 🧩 feature flag | 3 |
| Get Organization Services | ⚠️ invalid `()` syntax + bad `errors` field | 2 |
| Subscriptions: Collection Count / Wallet Balance / Simulator release ×2 | 🧩 dashboard | 2 |

### Saved Searches / Search
| Request | Status | Score |
|---|---|---:|
| Saved Searches: Count/Get All/Get by ID/Save/Update/Delete | ✅ | 4 |
| Collection Count Stats (`collectionStats`→json) | 🧩 | 2 |
| Search Contacts and Conversations (`search`) | 🧩 conversation model | 2 |
| Search WA Group Conversations (`waSearch`) | 🧩 | 2 |
| Search multi (`searchMulti`) | 🧩 | 2 |
| Saved Search Count / Execution | 🧩 | 2–3 |

### Session Template
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get by ID / Create / Update / Delete | ✅ | 5 |
| Get WhatsApp HSM categories | 🧩 enum list | 3 |

### Users
| Request | Status | Score |
|---|---|---:|
| Count / Get All / Get Current User | ✅ | 5 |
| Update Current User (Details / Password) / Update / Delete User | ✅ | 5 |
| Get a specific User by ID | ❌ calls `provider(id)` | **0** |
| Get All Roles | ❌ `query { roles }` (no root field) | **0** |

### Profiles / Triggers (stub-only)
| Request | Status | Score |
|---|---|---:|
| Create a Profile | ✅ (only op documented) | 4 |
| Create trigger | ✅ (only op documented) | 4 |

### Filesearch (AI Assistants)
| Request | Status | Score |
|---|---|---:|
| Create / Update / Delete / Get Assistant, List Assistants, List models, Create Knowledge Base | ✅ (inconsistent casing) | 4 |
| Remove Files from Assistant (`RemoveAssistantFile`) | ❌ nonexistent | **0** |

### SaaS / Glific Contact Import
| Request | Status | Score |
|---|---|---:|
| Import Contacts API (`importContacts`) | ✅ | 4 |
| Create org + contact + BSP (REST onboard/setup) | ✅ | 4 |
| Update registration details / Reachout to support (REST) | ✅ | 3 |
| Update Org Status / Delete inactive org | ✅ admin | 3 |
| Reset selected tables (`resetOrganization`) | 🧩 destructive admin | 2 |
| Fetch ERP organizations (`GET /onboard/organizations`) | ❌ no route | **0** |

---

## 7. Overall Documentation Score — 54 / 100

| Dimension | Weight | Score | Rationale |
|-----------|------:|------:|-----------|
| **Readability** | 0.30 | **68** | Every request has a structured `docs` block (description, parameter tables, curl, sample response, FAQ); Slate `includes/*.md` are thorough for covered modules. Dragged down by stale/copy-pasted prose, undeclared variables, and the invalid `()` example. |
| **Testability** | 0.30 | **55** | Bruno collection is runnable with a working `environments/` + auth-token post-response script. But ~24 requests fail on execution (wrong/nonexistent ops), there are **no response assertions/tests**, and subscriptions cannot actually run over Bruno's HTTP transport. |
| **Ease of use / Completeness** | 0.40 | **42** | Only ~33% operation coverage; ~half of modules entirely absent; duplicated folders ("Messages Tags" = "Contact Tag"); inconsistent operation naming; partial modules (Triggers/Profiles document only `create`). |

**Weighted total = 0.30·68 + 0.30·55 + 0.40·42 = 53.7 ≈ 54 / 100.**

---

## 8. Recommended Fixes (highest ROI first)

1. **Fix the 11 nonexistent-op requests** (§3a) and the 12 wrong-op requests (§3b) — these
   actively mislead and fail when run. Easy, high-impact.
2. **Delete or correct the duplicated folders** — "Messages Tags" should use
   `createMessageTag`/`updateMessageTags`/`createdMessageTag`; "User Group" should drop the
   stray contact-tag subscription.
3. **Add the ~22 missing modules** (§4), starting with the integrator-relevant ones:
   Tickets, Billing, Interactive Templates, Sheets, Contacts Fields, WhatsApp Forms,
   WA Groups, Notifications, Webhook Logs.
4. **Complete the stub modules** (Triggers, Profiles) and add the missing operations on
   Organizations / Session Templates / Flows.
5. **Standardize operation naming** (drop PascalCase/`snake_case` in Filesearch) and add at
   least a smoke-test assertion (`res.body.data != null`) to each Bruno request so the
   collection is self-validating in CI.
6. **Label UI-coupled operations** (Search/Conversation, Simulator, dashboard subscriptions,
   editor-lock) as "front-end internal" so integrators know they are not general-purpose.
