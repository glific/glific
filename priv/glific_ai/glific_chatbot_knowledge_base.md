# Glific Chatbot Knowledge Base — Comprehensive Companion Guide

> **Purpose of this document.** This file is a structured, retrieval-optimized companion to the main Glific documentation (`merged_documentation 2.md`). The main file relies heavily on screenshots; when those images are stripped (as in the chatbot's knowledge base), key syntax and step-by-step details get lost in narrative paragraphs. This document re-states every important fact in plain text, in self-contained chunks, with the exact syntax in code blocks. Each section is written so that a retrieval system can return a single chunk and the LLM can answer the question without needing surrounding context.
>
> **Vocabulary note.** Users ask about the same concept with different words. This doc deliberately includes synonyms ("sub-flow" = "child flow" = "linked flow" = "called flow"; "result variable" = "flow variable" = "@results variable"; "contact variable" = "contact field" = "@contact.fields variable"). If a user asks using one term, the answer should still surface.

---

# 1. Glific Vocabulary & Concepts (read this first)

## 1.1 Variables in Glific — the four kinds

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Flow%20variables%20vs%20Contact%20variables/

Glific has **four** distinct kinds of variables. The `@` prefix is required when referencing any of them inside a flow node.

| Kind                                           | Prefix                                              | Scope                                          | Created by                                                        |
| ---------------------------------------------- | --------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| Contact variable (a.k.a. contact field)        | `@contact.fields.<name>`                            | Persists across **all** flows for that contact | `Update Contact` node, or auto-created                            |
| Predefined contact variable                    | `@contact.<name>`                                   | Persists across all flows; system-managed      | Auto-populated by Glific (name, phone, language, etc.)            |
| Flow variable (a.k.a. result, result variable) | `@results.<name>`                                   | Lives only inside the **current** flow run     | `Wait for Response` node, `Save Flow Result` node, `webhook` node |
| Parent/child flow variable                     | `@results.parent.<name>` or `@results.child.<name>` | Crosses the parent ↔ child flow boundary       | Defined in the other flow                                         |

**Rule of thumb:**

- Need the value only in this flow? → use `@results.<name>` (a flow result).
- Need the value in another flow run, or another flow entirely? → save it to `@contact.fields.<name>` using `Update Contact`.
- Need a value from a flow that called this one (parent flow)? → `@results.parent.<name>.input`.
- Need a value from a flow this flow called (child / sub-flow)? → `@results.child.<name>.input`.

## 1.2 Parent flow vs child flow vs sub-flow — terminology

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Parent%20and%20Child%20variable/

These all describe the same parent/child relationship. When one flow uses the **Enter another flow** node to call another flow:

- The flow that **does** the calling = **parent flow** (also called "main flow", "calling flow").
- The flow that **gets** called = **child flow** (also called **sub-flow**, **linked flow**, **called flow**, **nested flow**).

If a user asks "How do I read a variable from the calling flow?" or "How do I get a parent flow's result inside a sub-flow?" — the answer is the same: `@results.parent.<variable_name>.input`. See section 3.4.

## 1.3 Result vs Result Name vs Variable — same thing, different words

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Flow%20variables%20vs%20Contact%20variables/

When a `Wait for Response` node or `Save Flow Result` node is given a name, that name becomes a **result variable**. Users may call this:

- "the result"
- "the result name"
- "the variable"
- "the flow variable"
- "the saved value"

All of these resolve to `@results.<that_name>`. To access the raw response, append `.input`. To access the categorized response, append `.category`.

## 1.4 `.input` vs `.category` vs other suffixes

Result variables have several suffixes:

| Suffix                                       | What it returns                                                                               |
| -------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `@results.<name>` or `@results.<name>.input` | The raw text the contact entered                                                              |
| `@results.<name>.category`                   | The category bucket the response fell into (e.g., "M" for Male, "Yes" for any of "yes/y/yup") |
| `@results.<name>.url`                        | For media: the URL of the uploaded file                                                       |
| `@results.<name>.caption`                    | For media: the caption sent with the file                                                     |

For webhook results: `@results.<webhook_name>.<json_key>` — see section 4.3.

---

# 2. Quick Syntax Reference (cheatsheet)

Every code-block below is a **complete, copy-pasteable** expression that goes inside a flow node.

## 2.1 Reading values

```
@contact.name                          # contact's display name
@contact.phone                         # contact's phone number
@contact.id                            # internal Glific id
@contact.language                      # the contact's language
@contact.fields.gender                 # gender, if you created it as a contact variable
@contact.optin_status                  # true / false
@contact.optin_time                    # timestamp of opt-in
@contact.optout_time                   # timestamp of opt-out
@contact.optin_method                  # how they opted in (whatsapp/website/etc.)
@contact.status                        # processing / valid / invalid / blocked / failed
@contact.bsp_status                    # none / session / session_and_hsm / hsm
@contact.list_profiles                 # all profiles linked to this contact
@contact.in_groups                     # collections this contact belongs to
@contact.last_message_at               # timestamp of last inbound message
@contact.fields.<custom_field_name>    # any custom contact field
```

```
@results.<result_name>                 # raw response, same as .input
@results.<result_name>.input           # raw text response
@results.<result_name>.category        # categorized bucket value
@results.<result_name>.url             # media URL
@results.<result_name>.caption         # media caption
@results.flow_keyword.input            # the keyword that started this flow
@results.flow_keyword.category         # full sentence the contact sent
```

## 2.2 Cross-flow variables (parent ↔ child)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Parent%20and%20Child%20variable/

```
@results.parent.<variable_name>.input      # value from the parent (calling) flow
@results.child.<variable_name>.input       # value from the child (called/sub) flow
```

Concrete example: parent flow has a result named `state`. From inside the child / sub-flow:

```
@results.parent.state.input
```

The mirror direction — parent reading from child:

```
@results.child.city.input
```

## 2.3 Webhook response

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

If a webhook node was named `mywebhook` and its JSON response was `{"success_message":"...", "status_code":200}`:

```
@results.mywebhook.success_message
@results.mywebhook.status_code
@results.mywebhook.<any_key_in_response>
```

Webhook responses **must** be a JSON object, not an array.

## 2.4 Google Sheet result

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

When a Google Sheet integration node named `sheet` reads a row, columns become keys:

```
@results.sheet.<column_header>
@results.sheet.image                   # for example, an "image" column with a public URL
```

## 2.5 Custom expressions (Elixir-style, `<%= ... %>`)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

```
<%= @contact.fields.counter + 1 %>                              # increment a counter
<%= (@contact.fields.counter || 0) + (@contact.fields.add_counter || 0) %>   # safe add of two counters
<%= Timex.today("Asia/Kolkata") |> Date.to_string() %>          # today's date in IST
<%= DateTime.now!("Asia/Kolkata") |> DateTime.to_string() %>    # today's date and time in IST
<%= DateTime.now!("Asia/Kolkata") |> Calendar.strftime("%H:%M:%S") %>   # current time HH:MM:SS in IST
<%= Time.diff(Time.from_iso8601!("@contact.fields.time_end"), Time.from_iso8601!("@contact.fields.time_start"), :second) %>   # seconds between two times
<%= "@contact.fields.batch_start_date" |> Timex.parse!("{D}/{0M}/{YYYY}") |> then(&(Timex.diff(Timex.now(), &1, :day))) %>   # days since a stored date
<%= String.downcase("@results.resultname") %>                   # convert to lowercase
<%= if "collection 1" in @contact.in_groups, do: 1, else: if "collection 2" in @contact.in_groups, do: 2, else: 3 %>  # branch by collection membership
<%= if "@contact.fields.is_registered" == "1", do: 1, else: 0 %>   # branch by registration flag
<%= if @contact.optin_status == true, do: 1, else: 2 %>           # branch by opt-in status
<%= case "@results.assigned_arm_id" do "@results.control_arm_id" -> "Control"; "@results.treatment_arm_id" -> "Treatment"; end %>   # match value against multiple variables
```

## 2.6 Calendar variable

```
@calendar.current_date                 # today, formatted D/0M/YYYY (e.g., 2/01/2025, 11/10/2024)
```

## 2.7 Common regex patterns

```
^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$        # DD/MM/YYYY any year
^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/(?:202[5-9]|2030)$   # DD/MM/YYYY 2025-2030
([01][0-9]|2[0-3]):([0-5][0-9])$                            # HH:MM 24-hour time
```

---

# 3. Variables — the most common questions

## 3.1 How do I save a user's response so I can use it later in the same flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/

Use a **Wait for Response** node. Give it a Result Name (e.g., `contact_email`). Reference it later as `@results.contact_email` (raw) or `@results.contact_email.category` (the categorized bucket).

Naming rules: lowercase, no spaces, no special characters, underscores `_` allowed. So `user_age` is valid; `User Age!` is not.

```
@results.contact_email
@results.contact_email.category
```

## 3.2 How do I save a value so I can use it across multiple flows?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

Use an **Update Contact** node to write the value to a contact field. From then on (in any flow, for that same contact), reference it as `@contact.fields.<field_name>`.

```
@contact.fields.collegename
@contact.fields.email
@contact.fields.contactname
```

The contact field is created automatically the first time you use it in an Update Contact node.

## 3.3 What's the difference between `@results` and `@contact`?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Flow%20variables%20vs%20Contact%20variables/

- `@results.<name>` — only exists during the current flow run. New flow run = empty.
- `@contact.fields.<name>` — persists permanently on the contact. Available in every flow that contact ever runs.

Use `@results` for one-off, mid-flow logic. Use `@contact.fields` when the data has long-term meaning (registration details, preferences, identifiers).

## 3.4 How do I read a result variable from the parent flow inside a sub-flow / child flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Parent%20and%20Child%20variable/

(Equivalent phrasings: "parent flow variable in sub-flow", "access calling flow's variable from called flow", "use main flow result in child flow", "read variable from outer flow in inner flow".)

**Syntax:**

```
@results.parent.<variable_name>.input
```

**Concrete example.** Parent flow has a Wait for Response with Result Name `state`. The parent then calls a child flow via the **Enter another flow** node. Inside the child flow you reference the parent's `state` value as:

```
@results.parent.state.input
```

This works in any node of the child flow — Send Message, Update Contact, Split By, webhook body, etc.

If the parent variable was a webhook result or Save Flow Result rather than a Wait for Response, the same `@results.parent.<name>.input` pattern still applies; `.input` returns the stored raw value.

## 3.5 How do I read a result variable from the child / sub-flow inside the parent flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Parent%20and%20Child%20variable/

After the **Enter another flow** node returns control to the parent, the parent can read any result that was created in the child flow:

```
@results.child.<variable_name>.input
```

**Concrete example.** Child flow defined a result named `city`. Back in the parent flow:

```
@results.child.city.input
```

## 3.6 How do I find the keyword that started this flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/How%20to%20identify%20which%20keyword%20triggered%20the%20flow/

Use the built-in `flow_keyword` result, no setup required:

```
@results.flow_keyword.input        # the matched keyword (e.g., "key1")
@results.flow_keyword.category     # the full sentence the user typed
```

**Caveat.** If a staff member starts the flow for a contact from the Glific dashboard (rather than the contact triggering it via WhatsApp), `@results.flow_keyword.category` will be either null or literally the string `@results.flow_keyword.category`.

## 3.7 How do I increment a counter inside a flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Create%20a%20Counter%20Variable%20in%20a%20Flow/

Three steps:

1. **Initialize** — Add an `Update Contact` node, choose `counter` (or any field name) from the dropdown, set the value to `0`.
2. **Increment** — At the spot where you want to count an event, add another `Update Contact` node on `counter` with value:
   ```
   <%= @contact.fields.counter + 1 %>
   ```
3. **Read** — Reference the counter anywhere as `@contact.fields.counter`.

To branch on the counter (e.g., "stop nudging after 3 attempts"), use a **Split by Contact Field** node on `counter`.

To safely add two counters that may not be initialized:

```
<%= (@contact.fields.counter || 0) + (@contact.fields.add_counter || 0) %>
```

## 3.8 How do I see all custom contact variables I've created?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/List%20of%20Custom%20Contact%20Variables%20created%20in%20Flows/

Login → left menu → **Flows** → **Contact variables** link at the bottom of the Flows screen. The list shows every custom field with:

- **Variable Name** — full reference syntax (e.g., `@contact.fields.age_group`)
- **Input Name** — how the variable is stored in BigQuery
- **Short Name** — abbreviated form

You can search by any of these names, edit the input/short name (click the pencil icon, then the green tick to save), or delete a variable (three-dot menu).

## 3.9 List of all predefined `@contact.*` variables

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Predefined%20Contact%20Variables%20in%20Glific/

You don't have to create any of these — they exist by default on every contact:

**Basic identity:**

- `@contact.name` — display name
- `@contact.phone` — phone number
- `@contact.id` — internal id

**Language:**

- `@contact.language` — current language (resolves to the language label)

There is **no built-in `@contact.gender`**. Gender is a contact variable you create yourself at **Manage → Contact variables**, so it is read as `@contact.fields.gender`. The same goes for age, district, and every other demographic.

**Opt-in tracking:**

- `@contact.optin_status` — `true` / `false`
- `@contact.optin_time` — timestamp
- `@contact.optout_time` — timestamp
- `@contact.optin_method` — channel through which they opted in (whatsapp, website, etc.)

There is no `@contact.consent_status`. To branch on consent, use `@contact.optin_status` (true/false) or `@contact.optout_time` (nil vs a timestamp) — see [5.6](#56-branching-by-collection--opt-in--registration).

**WhatsApp connection:**

- `@contact.status` — `processing`, `valid`, `invalid`, `blocked`, `failed`
- `@contact.bsp_status` — Gupshup session: `none`, `session`, `session_and_hsm`, `hsm`

**Profiles & groups:**

- `@contact.list_profiles` — all profiles linked to this contact
- `@contact.in_groups` — list of collections (groups) the contact belongs to. `@contact.groups` is an alias for the same thing.

**Custom fields:**

- `@contact.fields.<fieldname>` — any custom field created via Update Contact

**Interaction:**

- `@contact.last_message_at` — timestamp of contact's last inbound message
- `@contact.last_communication_at` — timestamp of the last message either way
- `@contact.optout_method` — how they opted out
- `@contact.contact_type` — whether this is a WABA contact or a WA-group contact

## 3.10 Are variable names case-sensitive? What characters are allowed?

- Lowercase only (or it may not match consistently).
- No spaces — use underscore `_` instead.
- No special characters like `!`, `?`, `&`, `-`, etc.
- No leading numbers.

Examples:

- ✅ `contact_name`, `age_group`, `score_q1`
- ❌ `Contact Name`, `age-group`, `2nd_score`, `name!`

---

# 4. Flow Action nodes — what each one does, key syntax, and gotchas

## 4.1 Send the contact a message (Send Message node)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20a%20message/

**What it does.** Sends a plain text, media, or HSM template message to the contact. No buttons or lists — for those use the Interactive Message node.

**The node body** is the message text. It supports WhatsApp formatting:

- Bold: `*text*`
- Italic: `_text_`
- Strikethrough: `~text~`
- Monospace: `` ```text``` ``

You can embed any `@results.*` or `@contact.*` variable directly: `Hi @contact.name, your score is @results.quiz_score.` Below the text box is a **Labels** picker that tags the outgoing message.

**Two tabs at the top of the node:**

1. **Attachments** — image, video, audio, document, sticker. **One attachment per node.** Either upload from your computer (needs Google Cloud Storage configured for the org) or paste a public URL — from GCS, not Google Drive; Google Drive links don't work. Sticker and audio must be sent **alone**, not combined with a body.
2. **HSM Templates** — pick a pre-approved template (used outside the 24-hour session window), and fill its variables.

There is **no quick-replies field on this node** — for buttons, use an Interactive Message ([6](#6-interactive-messages-reply-buttons-list-location)).

**Size limits (WhatsApp):**

- Image: 5.12 MB
- Video: 16.384 MB
- Audio: 16.384 MB
- Document: 102.4 MB
- Sticker: 0.09 MB, only 512 × 512 px `.webp`
- Text body: 4096 chars max
- `.gif` is **not** supported — convert to mp4.

**Sending media via expression** (e.g., URL stored in a Google Sheet column called `image`):

```
@results.sheet.image
```

## 4.2 Wait for the contact to respond (Wait for Response node)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/

**What it does.** Pauses the flow until the contact replies. Saves the reply in a result variable named by the user.

**Configure:**

1. Add the node.
2. Pick a Response Type from the dropdown.
3. Provide a Result Name — e.g., `contact_age`. Reference later as `@results.contact_age`.
4. (Optional) Tick "Continue when there is no response" to nudge or move on after a wait time.

**Response Types:**

_Text-based:_

- **has any of the words** — comma-separated list, e.g., `Yes, Y, Ya, Yup`. Empty field accepts any text.
- **has all of the words** — exact match required.
- **has a phrase** — phrase appears anywhere in input.
- **has only the phrase** — exact-match phrase.

_Numeric:_

- **has a number** — any numeric input.
- **has a number between** — range, e.g., `18-60`.
- **has a number equal to** — exact value.

_Contact details:_

- **has a phone number** — accepts:
  - 10-digit mobile (`XXXXXXXXXX`)
  - 10-digit with leading 0 (`0XXXXXXXXXX`)
  - With country code (`+91 XXXXXXXXXX`)
  - Landline `XXX XXXXXXX`, `0XXX XXXXXXX`, `+91 XXX XXXXXXX`
- **has an email** — accepts `abc@xyz.xyz`, `abc@xyz`.

_Media:_

- **has media** — jpeg, png, mp4. Stores both URL and caption:
  ```
  @results.<name>.url
  @results.<name>.caption
  ```
- **has audio** — audio file.
- **has video** — mp4.
- **has image** — jpeg, png.
- **has file** — pdf, doc.

_Other:_

- **has location** — captures longitude + latitude. For human-readable address use the Google Maps reverse geo webhook integration.
- **Matches Regex** — validate against a regex pattern. Example DOB:
  ```
  ^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$
  ```

**No-response handling.** Tick "Continue if there is no response for" and pick a duration. You can chain reminders (e.g., one every hour, up to 3 nudges).

## 4.3 Call a webhook

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

**What it does.** Sends an HTTP request to an external URL during the flow and stores the response in a result variable.

**Configure:**

1. Action: `Call a webhook`.
2. Method: **GET**, **POST**, or **FUNCTION**. `FUNCTION` means "one of Glific's built-in webhooks" (see [20](#20-built-in-webhooks-reference)) and takes the function name in the URL field instead of a URL. PUT, DELETE and PATCH are disabled in Glific.
3. URL: target URL (or the built-in function name when Method is `FUNCTION`).
4. Post Body: a JSON object with the variables to send. Example:
   ```json
   {
     "contact": "@contact",
     "results": "@results",
     "Emp_name": "Mohit",
     "Emp_age": "@results.age.input"
   }
   ```
5. Result Name: e.g., `mywebhook` (this becomes the prefix for response keys).

**Reading the response.** If your webhook returns:

```json
{ "success_message": "You are onboarded.", "status_code": 200 }
```

You access it as:

```
@results.mywebhook.success_message
@results.mywebhook.status_code
@results.mywebhook.<any_other_key>
```

**Hard rules:**

- The webhook must return a **JSON object**, not an array.
- Default timeout is **5 seconds**. For long-running calls, return `200` immediately and use the **Wait for result** node plus the `resumeContactFlow` mutation (see [4.4](#44-wait-for-result) and [17.5](#175-resuming-a-parked-flow)).

**Exits.** The node has two, **Success** and **Failure** — not a four-way client/server/network split.

**Webhook Logs.** Left panel → **Flows** → **Webhook logs**. Each row shows: time, URL, status (Success/Error), status code, error message, method, request header, request JSON, response JSON. Click a row to view or copy.

**Reference recipes & code examples:** https://github.com/glific/recipes

## 4.4 Wait for result

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/

**What it does.** Pauses the flow until an external system resumes it via the `resumeContactFlow` GraphQL mutation. Used when a webhook needs longer than the 5-second default — e.g., RAG queries, long computations. Glific's own async webhooks (`speech_to_text`, `text_to_speech`, `filesearch-gpt`, `voice-filesearch-gpt`) park at this node too, and resume through their own signed callback.

**How to use:**

1. Make a webhook call that immediately returns `200` (so the flow keeps moving).
2. Place a **Wait for result** node next and set the wait. A wait of 24 hours or more means the message after it has to be an HSM — publishing warns you if it isn't.
3. The flow pauses there.
4. When the external system finishes, it calls the **`resumeContactFlow` GraphQL mutation** with `flowId`, `contactId` and a `result` payload.
5. The flow resumes; the resumed value is available in the `result` variable.

**API details.** See [17.5](#175-resuming-a-parked-flow) for the exact mutation.

- GraphQL endpoint: `POST https://api.<your-shortcode>.glific.com/api`
- The `result` argument must be **stringified JSON** (escaped, valid JSON).
- Auth: `POST /api/v1/session` for a token; the mutation needs Manager level or above.
- Flow ids come from the `flows` query, contact ids from the `contacts` query.
- Glific's own async webhooks resume differently — via the signed `/webhook/flow_resume` callback, which you don't call yourself.

If the webhook completes **before** the wait time, the flow resumes immediately — the wait is a maximum, not a minimum.

## 4.5 Save a result for this flow (Save Flow Result node)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Save%20a%20result%20for%20this%20flow/

**What it does.** Stores a value into a flow result variable on demand (without waiting for user input). Use this when you want to derive or transform a value mid-flow.

**Configure:**

- **Result** — unique name, referenced later as `@results.<name>`.
- **Value** — literal, expression, or `@(input)` to capture the immediately-prior input. Leave blank to clear.
- **Category** (optional) — bucket label. Useful for analytics.

**Examples:**

- Capture a feedback rating:
  ```
  Result: user_rating
  Value: @(input)
  Category: Rating
  ```
  Then in the next message: `Thank you! Your rating of @results.user_rating is noted.`
- Save with title-casing:
  ```
  Value: @(title(input))
  ```

## 4.6 Update the contact (Update Contact node)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

**What it does.** Writes a value to a contact field (a permanent variable on the contact). Used to:

- Persist a value across flows
- Initialize / increment counters
- Update the contact's **language**

The property dropdown in Glific offers **Language** and **Channel** plus every contact variable you've created. **Name and Status are not offered** — you cannot set a contact's name, opt-in status or blocked status from a flow. Store a name in your own contact variable instead.

**Common pattern (collect then save):**

1. Wait for Response → result name `age`
2. Update Contact → field `age` ← value `@results.age`

**Common pattern (counter):**

1. Update Contact → field `counter` ← value `0` (initialize)
2. Update Contact → field `counter` ← value `<%= @contact.fields.counter + 1 %>` (increment)

## 4.7 Enter another flow (call a sub-flow)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Enter%20another%20flow/

**What it does.** Suspends the current flow and starts another flow for the same contact. The parent's results remain accessible to the child via `@results.parent.*`. When the child finishes, control returns to the parent and child results are accessible via `@results.child.*`.

This node is the mechanism that creates the **parent / child** relationship described in section 3.4–3.5.

## 4.8 Start somebody else in a flow

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Start%20somebody%20else%20in%20a%20flow/

**What it does.** Triggers a flow for a **different** contact or a whole collection — e.g., when teacher A finishes a quiz, automatically start the result-broadcast flow for student collection X.

**Steps:**

1. Add the node, pick **Select recipients manually**.
2. Pick the target contact or collection.
3. Pick the flow.
4. Open **Advanced** → tick "skip the contact who is currently in the flow" if needed.

**Note.** This node is enabled for all orgs — the flow editor always ships the `start_session` feature filter.

## 4.9 Send the contact an interactive message

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20an%20interactive%20message/

**What it does.** Sends a pre-created Interactive Message (Reply Buttons / List Message / Location Request). Create the interactive message first under **Quick tools → Interactive msg**, then pick it from the dropdown in this node.

See section 6 for full Interactive Message rules.

## 4.10 Open a ticket with a human agent

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Open%20a%20ticket%20with%20a%20human%20agent/

**What it does.** Hands off the conversation to a human staff member. Creates a ticket. The agent picks it up from the Chats screen.

## 4.11 Send a staff member a message

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20a%20staff%20member%20a%20message/

**What it does.** Sends a notification message to a Glific user (staff), not the contact. Useful for internal alerts: "User X just completed onboarding".

## 4.12 Add or Remove the contact to a collection

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Add%20or%20Remove%20the%20contact%20to%20a%20collection/

**What it does.** Modifies the contact's collection membership during the flow. Combine with **Split by collection Membership** later to gate access.

## 4.13 Manage profile (multi-profile feature)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Manage%20profile/

**What it does.** When a single phone number is shared by multiple end users (e.g., a household), Manage Profile lets you maintain separate profiles under one contact.

**Three actions:**

1. **Create Profile** — create a new profile. Will not allow duplicate name+type.
2. **Switch Profile** — change which profile is active. Often combined with `@contact.list_profiles` to show options and `@results.profile_index` to pick one.
3. **Deactivate Profile** — hide a profile from the UI and from `@contact.list_profiles` (data preserved in BigQuery). The default profile cannot be deactivated.

The deactivate feature is opt-in — request enablement via [Glific Discord](https://discord.gg/47mGc5PrZJ).

## 4.14 Wait for time

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20time/

**What it does.** Inserts a delay between nodes. Leave the delay blank (or set it to 0) and the flow just pauses ~4 seconds inline instead of parking; set a real delay and the contact is woken by the background worker. A delay of 24 hours or more means the next message has to be an HSM — publishing warns you if it isn't.

## 4.15 Label the incoming message

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Label%20the%20incoming%20message/

**What it does.** Tags the inbound message with a category label, useful for analytics (e.g., label messages where the contact picked English as "English"; later count how many users picked English).

## 4.16 Link Google Sheets

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

**What it does.** Reads from / writes to a Google Sheet during a flow. The sheet must be set up in Glific's Google Sheets integration first. Once linked and a row is fetched, columns are accessed as:

```
@results.sheet.<column_header>
```

where `sheet` is the result name given to the integration node.

## 4.17 Split By (the variants Glific ships)

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

The Split By node branches the flow on a condition. The variants available in Glific:

1. **Split Randomly** — split contacts randomly across N branches. Used for AB testing different journeys.
2. **Split by collection Membership** — branch by which collection(s) the contact belongs to.
3. **Split by Expression** — branch on an expression, then match it with the same operators as Wait for Response. Most powerful but most complex. See section 5.
4. **Split by Contact Field** — branch by the value of a contact variable. E.g., split on `age` to send different messages to Kids / Teens / Adults.
5. **Split by Flow Result** — branch by the value of a `@results.*` variable from earlier in this flow. Quick way to fork on a previous answer.
6. **Split by Intent** — runs the Dialogflow classifier, one exit per intent. **Only appears when the Dialogflow service is enabled** for your org.

**Split by URN Type** exists upstream but is switched off in Glific, and there is no "Consent Status" split — to branch on opt-in, use **Split by Expression** on `@contact.optin_status` (see [5.6](#56-branching-by-collection--opt-in--registration)).

---

# 5. Custom Expressions (the `<%= ... %>` block) — comprehensive reference

Custom expressions use Elixir syntax. They're evaluated server-side and substitute the result inline. Used in:

- **Update Contact** node (to compute the value being saved)
- **Save Flow Result** node (to compute the value being stored)
- **Send Message** body (occasionally, for inline computation)
- **Split by Expression** node (to drive branching)
- **Wait for time** delays

> **Treat this as a restricted subset of Elixir, not the whole language.** Orgs on Glific's safe-expression evaluator (the default going forward) run expressions through an allowlist interpreter that rejects anything outside the list below; older orgs run a denylist that blocks obviously dangerous code and returns _"Suspicious Code. Please change your code. …"_. Write to the allowlist either way — it works on both. Only these modules are callable, and only specific functions/arities within them:
>
> `String` · `Decimal` · `Enum` · `List` · `Map` · `MapSet` · `Integer` · `Float` · `URI` · `Jason` · `Date` · `Time` · `DateTime` · `NaiveDateTime` · `Calendar.strftime` · `Timex` (incl. `Timex.Timezone.convert`) · `Regex`
>
> Plus the usual operators and a handful of Kernel functions: `+ - * / rem div abs round trunc elem length == != > < >= <= <> not and or in to_string inspect is_number is_binary is_integer is_nil is_map max min then hd`, ranges, `if`, `case`, `with`, and single-clause anonymous functions of arity 1 or 2.
>
> Anything else — `System`, `File`, `:os`, `apply/3`, `import`, `alias`, module attributes, multi-clause `fn`, function-capture shorthand like `&String.upcase/1` (write `&String.upcase(&1)` instead) — is **rejected**. A rejected or malformed expression renders as `"Invalid Code"` rather than running. Expressions are also validated when you publish the flow, so you usually find out before it reaches a contact.

## 5.1 General syntax

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

```
<%= <elixir_expression> %>
```

Anything between `<%=` and `%>` is computed. The result replaces the entire expression.

## 5.2 Conditionals

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

```
<%= if <variable> == "<value>", do: <result_if_true>, else: <result_if_false> %>
```

Examples:

```
<%= if @contact.optin_status == true, do: 1, else: 2 %>
<%= if "@contact.fields.is_registered" == "1", do: 1, else: 0 %>
```

Nested:

```
<%= if "collection 1" in @contact.in_groups, do: 1, else: if "collection 2" in @contact.in_groups, do: 2, else: 3 %>
```

## 5.3 Pattern matching with `case`

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

```
<%= case "@results.assigned_arm_id" do "@results.control_arm_id" -> "Control"; "@results.treatment_arm_id" -> "Treatment"; end %>
```

This compares `@results.assigned_arm_id` against the values of two other variables and returns "Control" or "Treatment" accordingly.

## 5.4 Date & time

```
<%= Timex.today("Asia/Kolkata") |> Date.to_string() %>             # today's date IST
<%= DateTime.now!("Asia/Kolkata") |> DateTime.to_string() %>       # today's datetime IST
<%= DateTime.now!("Asia/Kolkata") |> Calendar.strftime("%H:%M:%S") %>   # current HH:MM:SS IST
```

Common pattern — capture flow start time, end time, then compute duration:

```
<%= Time.diff(
      Time.from_iso8601!("@contact.fields.time_end"),
      Time.from_iso8601!("@contact.fields.time_start"),
      :second
    ) %>
```

Days since a stored date (date in `D/0M/YYYY` format):

```
<%= "@contact.fields.batch_start_date"
    |> Timex.parse!("{D}/{0M}/{YYYY}")
    |> then(&(Timex.diff(Timex.now(), &1, :day))) %>
```

`@calendar.current_date` returns today as `D/0M/YYYY` (e.g., `2/01/2025`, `11/10/2024`). Useful for storing an onboarding date and later computing days-since.

## 5.5 String operations

```
<%= String.downcase("@results.resultname") %>     # lowercase
```

Concatenation in Glific is implicit when you place variables next to text in a node value:

- Field value: `Grade @results.grade.category ACP @contact.fields.s_acp`
- If `@results.grade.category = 2` and `@contact.fields.s_acp = 4`, the saved value becomes `Grade 2 ACP 4`.

You can also append to an existing field — the **node value** can include the field itself:

- Field value: `@contact.fields.cumulative_acp, @contact.fields.present_grade_acp`
- Each time the node runs, it appends the latest value, building a comma-separated history.

## 5.6 Branching by collection / opt-in / registration

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Collection%20Membership/

```
<%= if "collection 1" in @contact.in_groups, do: 1, else: if "collection 2" in @contact.in_groups, do: 2, else: 3 %>
<%= if @contact.optin_status == true, do: 1, else: 2 %>
<%= if "@contact.fields.is_registered" == "1", do: 1, else: 0 %>
```

The result (`1`, `2`, `3`) becomes the category which the Split By node uses to pick a branch.

## 5.7 Regex validation

Use **Wait for Response → matches regex** (`has_pattern`) or **Split by Expression** for input validation.

DD/MM/YYYY (any year):

```
^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$
```

DD/MM/YYYY (years 2025-2030):

```
^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/(?:202[5-9]|2030)$
```

24-hour HH:MM:

```
([01][0-9]|2[0-3]):([0-5][0-9])$
```

To support different separators or formats (`MM/DD/YYYY`, `DD-MM-YYYY`), adjust the sequence and separators.

## 5.8 Where to ask for help with custom expressions

If a particular expression isn't covered here, post in the [Glific Discord](https://discord.com/channels/717975833226248303/1037981805653008404). The team has tooling to help generate exact syntax for new use cases.

---

# 6. Interactive Messages (Reply Buttons, List, Location)

## 6.1 Three types

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

1. **Reply Buttons** — up to **3** quick reply buttons.
2. **List Message** — up to **10** list items, organized into one or more sections.
3. **Location Request** — a "Send Location" button to ask the contact for their location.

## 6.2 Creation steps

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

1. Left menu → **Quick tools** → **Interactive msg**.
2. Click **+ Create**.
3. Fill in:
   - **Type** (Reply buttons / List / Location request)
   - **Title** — for internal search (and optionally show on top of message)
   - **Message** — body content
   - **Footer** — subtext
   - Type-specific section (button labels, list items + descriptions, etc.)
   - **Tag** — for searchability later

## 6.3 Use in a flow

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20an%20interactive%20message/

Add a **Send the contact an interactive message** node, pick the interactive message from the dropdown.

## 6.4 Hard rules & gotchas

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

- **The Type is locked after creation.** Once saved, you can't switch a Reply-buttons message to a List message — create a new one. The title, body, footer, buttons and list items **are** editable.
- **No markdown** in headers or buttons. Markdown characters such as `*` and `_` are rejected with "Character policy violated".
- **No emojis in the title** field.
- Emojis **are** allowed inside button text and responses, but if used you must capture the response with `Wait for Response → has only the phrase` and paste the **exact** string (including emoji) for matching.

## 6.5 Auto-translate to multiple languages

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/

After creating, click **Edit** → **Translate** → **Auto translate**. The header, list name, options — everything in the message — gets translated into every language configured for your bot. The right-language version automatically fires for contacts whose `@contact.language` matches.

## 6.6 Dynamic interactive messages from a Google Sheet

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/#send-interactive-messages-using-google-sheets

For nested options (District → Block → School) or option lists exceeding the 10-item limit, drive the interactive message from a Google Sheet:

1. Set up a multi-sheet Google Sheet, one sheet per selection level. First-sheet options become keys for the next sheet.
2. Add a "Column 10" (or similar) for pagination when options exceed 10.
3. Link the Google Sheet to Glific.
4. Create an interactive message → tick **Use dynamic fields**. Set the list limit by `sheets.<column_name>`.
5. In the flow, initialize a counter at 1 and fetch the sheet row.
6. On user selection: if normal option, advance flow; if "More", increment counter, refetch next batch.

This pattern bypasses WhatsApp's 10-item list limit by paginating.

---

# 7. HSM Templates (pre-approved templates)

## 7.1 What & why

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

HSM = **Highly Structured Message**. WhatsApp-approved templates needed to message a contact **outside the 24-hour session window**. Required for reminders, alerts, broadcasts, re-engagement.

**Session window definition.** 24-hour rolling period after the contact's last inbound message. Inside it, you can send any message free-form, no extra cost. Outside it, you must use an HSM. Check remaining session time on a contact's profile under the search section in the left pane.

## 7.2 When to use HSM

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

- Initiating outside the 24-hour window (reminders, follow-ups).
- Broadcasting to many contacts at once (schedules, alerts, advisories, announcements).

**Critical rule:** the next node after an HSM must always be **Wait for Response**. This forces the system to wait for the user's reply before continuing.

## 7.3 Create & submit for approval

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

1. **Quick tools → HSM Templates → + Add Template**.
2. Fill the form:
   - **Language** — pick the language for approval.
   - **Translate existing HSM** — tick if creating a language variant of an already-approved template.
   - **Element Name** — WABA namespace title; use a short identifier.
   - **Title** — display name in Glific. Use a use-case-descriptive name (e.g., `OTP`, `OptIn`, `ActivityPreference`). **Title and Element Name must NOT be identical** to avoid mapping issues.
   - **Message** — the body. Insert variables via **Add Variable** (rendered as `{{1}}`, `{{2}}`, etc.). Provide sample values.
   - **Footer** — optional subtext.
   - **Add Buttons** — optional. Two button modes:
     - **Quick Replies** — up to **10** buttons.
     - **Call to Action** — Phone Number and/or URL buttons. Up to **2 URL** buttons + **1 Phone Number** button. Phone numbers without country code (e.g., Exotel virtual numbers) are rejected — put them in the body instead.
   - **Category** — **Utility** (transactional: order updates, account, appointments, alerts) or **Marketing** (promotions, launches, offers). These are the only two Glific offers; WhatsApp's Authentication category is not available.
   - **Attachment Type** + **Attachment URL** — optional. Use a public URL from your GCS bucket (not Google Drive).
   - **Tags** — optional.
3. Click **Submit for Approval**.
4. Click **Sync** on the template list page after a couple of minutes. Status moves Pending → Approved or Rejected.

Approval typically takes 2 minutes to 48 hours.

## 7.4 Static vs Dynamic URL buttons

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

**Static URL** — same link for everyone. Example: `https://xyz.org/register`.

**Dynamic URL** — personalized per user, with a placeholder. Example:

```
https://xyz.org/report/{{1}}
```

At send time, `{{1}}` is replaced with the contact-specific value (e.g., `12345`).

## 7.5 What happens if a template is rejected?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

- Rejected templates **cannot** be edited and re-submitted — the backend refuses any change to a non-approved HSM with _"HSM is not approved yet, it can't be modified"_.
- Create a new template with corrections.

## 7.6 Can I edit an approved template?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

- **No.** WhatsApp approval is immutable. On an approved HSM the backend accepts changes to only two things: the **Active?** toggle and the **Tag**.
- To change the body, buttons, category or anything else, create a new template and submit again.

## 7.7 Common HSM Template Errors

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

When an HSM message fails to send, you'll usually see one of these errors. The fix is almost always: create a new template, since approved templates are immutable.

- **Template not approved** — wait for approval or use a different template.
- **Variable count mismatch** — the template has `{{1}}, {{2}}` but you supplied a different number of variables.
- **Account not registered** — your Gupshup-Meta linkage isn't complete; check Gupshup account status.
- **Character policy violated** — markdown chars `*`, `_` are not allowed in template headers and buttons.

---

# 8. Common "How do I…?" recipes (paraphrased the way users ask)

## 8.1 How do I make a flow ask a question and remember the answer for later flows?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

1. **Wait for Response** node — give it a Result Name, e.g., `email`.
2. **Update Contact** node — choose (or create) a contact field also called `email`, set value to `@results.email`.

Now any future flow can reference `@contact.fields.email`.

## 8.2 How do I personalize a message with the contact's name?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Predefined%20Contact%20Variables%20in%20Glific/

In the Send Message body:

```
Hi @contact.name, welcome back!
```

## 8.3 How do I send different messages based on age?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Contact%20Field/

1. Capture age (Wait for Response → `has a number`, result name `age`).
2. Save it with **Update Contact** to a contact field `age`.
3. **Split by Contact Field** on `age`. Define branches: `1-12`, `13-19`, `20-60`.
4. After the split, attach a different Send Message node to each branch.

## 8.4 How do I send different messages based on the answer to the immediately previous question?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Result%20in%20the%20Flow/

Use **Split by Flow Result** instead of Split by Contact Field. Pick the result variable (e.g., `@results.color`) from the dropdown. Define branches per expected value (`Blue`, `Green`).

## 8.5 How do I send a reminder if the user doesn't answer?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/

In the **Wait for Response** node, tick "Continue when there is no response", set the time, and route the timeout exit to a Send Message reminder. Loop back to a second Wait for Response if you want multiple nudges (up to 3 nudges per hour is a typical pattern).

## 8.6 How do I AB test two versions of an onboarding flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Random%20Chance%20for%20AB%20Tests/

Use **Split Randomly**. Configure two branches at 50/50 (or any percentage). Each branch leads to a different sequence of nodes. Compare results in BigQuery later.

## 8.7 How do I track how many times a contact has hit a node?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Create%20a%20Counter%20Variable%20in%20a%20Flow/

See section 3.7 — counter pattern.

## 8.8 How do I get the user's location and find their address?

📖 Source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/

1. **Wait for Response → has location**, result name `location`.
2. The values `@results.location` (lat/long) are saved.
3. To convert to a human-readable address, call the Google Maps reverse geo webhook integration. See `Integrations / Google Maps API for reverse geo location` in the main docs.

## 8.9 How do I send media files dynamically (different file per contact)?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

1. Upload all media to GCS, get public URLs.
2. Put the URLs in a Google Sheet column (e.g., `image`).
3. Link the sheet to Glific.
4. In a Send Message → Attachments → choose **Expression** → reference `@results.sheet.image` (where `sheet` is the result name on the Google Sheet node).

## 8.10 How do I run a flow on a recurring schedule (e.g., every Monday at 9 AM)?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

Use **Triggers**. Left menu → **Quick tools → Triggers** → **+ Create**. Pick the flow (must be published), the date range and time, the recurrence (**Does not repeat / Hourly / Daily / Weekly / Monthly**) and the target collection. Triggers run against **collections**, not individual contacts.

## 8.11 How do I capture multiple answers to a single question?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Create%20a%20flow%20to%20capture%20multiple%20answers%20for%20a%20single%20question/

Interactive messages do **not** support this. Use a plain Send Message asking the user to reply in one message with comma-separated answers, then a Wait for Response. Add a hint and an example in the question text (e.g., "Reply with your top 3 in order, separated by commas: e.g., math, science, art").

## 8.12 How do I clear / reset a contact's flow state for testing?

📖 Source: https://glific.github.io/docs/docs/FAQ/Clear%20Flows%3A%20Resetting%20Contact%20Variables%20for%20Testing/

In **Chats**, open the contact, click the dropdown arrow in the conversation header and choose **Terminate flows** — this lists the contact's active flow runs so you can end them. The same menu has **Clear conversation**, which permanently deletes the chat history for that contact (it does not reset contact variables). To reset a contact variable itself, run an **Update Contact** node that writes an empty value to it (see [19.34](#1934-how-do-i-initialize-a-contact-field-as-a-blank--empty-string)).

## 8.13 How do I find which keyword started a flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/How%20to%20identify%20which%20keyword%20triggered%20the%20flow/

```
@results.flow_keyword.input        # the matched keyword
@results.flow_keyword.category     # the full sentence the user typed
```

No setup required — `flow_keyword` is auto-populated.

## 8.14 How do I find what contact variables I've created?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/List%20of%20Custom%20Contact%20Variables%20created%20in%20Flows/

Left menu → **Manage** → **Contact variables** (`/contact-fields`). Lists every custom contact field with its Name and Shortcode; reference them in flows as `@contact.fields.<shortcode>`.

## 8.15 How do I label a contact with a tag for analytics?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Label%20the%20incoming%20message/

Use the **Add or Remove the contact to a collection** node (collections double as analytics groups). For finer message-level tagging use the **Label the incoming message** node — labels show up in BigQuery for charting.

## 8.16 How do I copy a flow?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/

Flows page → click **Copy** on the flow row. The duplicate is named "Copy of …" and its keywords are cleared (keywords must stay unique).

## 8.17 How do I move a flow from one Glific account to another?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Import%20%26%20Export%20Flows/

Export from source: Flows page → **Export** on the flow row (downloads JSON). Import to destination: Flows page → **Import flow** → upload the JSON; a status dialog reports per-flow success or failure. Note that anything the flow references by name — collections, contact variables, interactive messages, HSM templates, sheets, assistants — has to exist in the destination org too.

## 8.18 How do I revert a flow to a previous version?

Inside the flow editor: **Revision History** button. Glific keeps a list of versions; pick one and revert. Useful when a published change broke production.

## 8.19 How do I count how many users opted-in?

📖 Source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/

Use BigQuery + Looker Studio. Note the BigQuery `contacts` table has **no `optin_status` column** — it carries `optin_time`, `optout_time` and `contact_optin_method`. Count opted-in contacts with `WHERE optin_time IS NOT NULL` (and `optout_time IS NULL` if you want currently-opted-in only).

## 8.20 How do I let staff jump in and chat with the user?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Open%20a%20ticket%20with%20a%20human%20agent/

Use the **Open a ticket with a human agent** node. The conversation is suspended (the bot stops auto-replying); a staff member picks up from Chats. They close the ticket when done, and the flow resumes (if configured to).

---

# 9. Limits & Constraints (single-line answers)

| Thing                                         | Limit                                       |
| --------------------------------------------- | ------------------------------------------- |
| Quick Reply buttons in an Interactive Message | 3 max                                       |
| List items in an Interactive Message          | 10 max (per list)                           |
| Quick Reply buttons in an HSM Template        | 10 max                                      |
| URL buttons in an HSM Template                | 2 max                                       |
| Phone Number buttons in an HSM Template       | 1 max                                       |
| Phone Number buttons without country code     | Not allowed (use body instead)              |
| Send Message text body                        | 4096 chars                                  |
| Image attachment                              | 5.12 MB                                     |
| Video attachment                              | 16.384 MB                                   |
| Audio attachment                              | 16.384 MB                                   |
| Document attachment                           | 102.4 MB                                    |
| Sticker attachment                            | 0.09 MB, 512×512 px, .webp only             |
| .gif files                                    | NOT supported (convert to mp4)              |
| Webhook methods                               | GET, POST, FUNCTION only (no PUT/DELETE/PATCH) |
| Webhook exits                                 | Success / Failure                           |
| Webhook timeout                               | 5 seconds (use Wait for Result for longer)  |
| Async webhook `wait_time` in the body         | 5 minutes max (longer is clamped, with a publish warning) |
| Wait for Result / Wait for time duration      | Days. A wait of 24 h or more means the next message must be an HSM |
| Wait for time with no delay set               | ~4 seconds inline                           |
| Session window                                | 24 hours after last contact inbound message |

---

# 10. Troubleshooting checklist (when a flow isn't working)

When a flow isn't behaving, check these in order:

1. **Is the flow active?** — Flow listing page → check `is active?` is on.
2. **Is the keyword exact?** — keywords are case-insensitive but must match exactly. Check for typos or extra spaces.
3. **Is the contact opted-in?** — for HSM-only flows, check `@contact.optin_status`.
4. **Are you within the 24-hour session window?** — outside it, only HSM messages send.
5. **Did the previous Wait for Response actually capture?** — check `@results.<name>` is populated. Use a test Send Message: `Captured: @results.<name>` to see it on simulator.
6. **Are interactive message responses matching?** — emoji-bearing buttons need `has only the phrase` with the exact string (including emoji).
7. **Did the webhook fail?** — Flows → **Webhook logs**. Look for non-200 status codes or error messages.
8. **Was the flow called from a parent and the variable reference is wrong?** — verify you're using `@results.parent.<name>.input` (not `@results.<name>` alone).
9. **HSM template approval status** — Templates page; status must be Approved.
10. **Ignore Keywords setting** — if enabled on another active flow, it may be blocking this flow's keyword from triggering.

---

# 11. Reporting & Analytics (where data goes)

## 11.1 BigQuery — primary data store

📖 Source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/

Every flow run, every contact field, every message is captured in BigQuery (if BigQuery is set up for your bot — see `Pre Onboarding / BigQuery Setup and link with Glific`).

Tables include (non-exhaustive):

- `messages` — every inbound and outbound message
- `flow_results` — every result variable saved per flow run
- `flow_contexts` — one row per flow run
- `flow_counts` — how many times each node was hit
- `contacts` — current contact state (including custom field values)
- `contact_histories` — historical changes (note the plural; there is no `contacts_history` table)
- `contacts_fields` — custom field definitions

There are ~34 tables in an org's dataset. The full column-by-column reference is in the BigQuery Tables Guide.

Typical query: "How many users completed the registration flow?" → `SELECT COUNT(DISTINCT contact_phone) FROM flow_results WHERE flow_uuid = '<id>'`.

## 11.2 DataStudio (Looker Studio) dashboards

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/Understanding%20V5%20Data%20Studio%20Reports/

Standard dashboards Glific provides:

- **HSM Delivery Dashboard** — tracks template send / delivery / read rates.
- **User Info Report** — populated from contact field views.
- **V5 reports** — current generation; see `Understanding V5 Data Studio Reports`.

To build custom reports: see `Making Custom Reports on DataStudio` in the main docs. Connect Looker Studio to BigQuery, build charts.

## 11.3 Get data for a particular flow from BigQuery

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/Get%20a%20data%20of%20a%20particular%20flow%20from%20BigQuery/

See `Get a data of a particular flow from BigQuery` in the main docs. Filter `flow_results` and `flow_counts` by the flow's UUID (visible in the URL when editing the flow).

## 11.4 Sync Google Sheets ↔ BigQuery

📖 Source: https://glific.github.io/docs/docs/FAQ/Sync%20BigQuery%20and%20Google%20Sheets/

Two-way sync supported. See `Sync BigQuery and Google Sheets`. Use case: read contact data into a sheet for the program team to review, write back enriched data.

## 11.5 Why is my Google Sheet sync failing?

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

Common reasons:

- Sheet permissions changed (service account lost access).
- Column header mismatch — Glific looks for exact header names.
- Sheet exceeded row/cell limits.
- Quota or rate limits hit.
  See `Why is the google sheet sync failing` and `Solving For Sheet Sync Failures Issues` in main docs.

---

# 12. Integrations — when to use which

| Integration                              | What it does                                                                                                                       |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **GPT (OpenAI)**                         | Send a contact's message to ChatGPT and use the reply in flow. See `ChatGPT using OpenAI APIs`.                                    |
| **GPT for image recognition**            | Pass an image URL to GPT-4 vision; receive description / answer. See `GPT integration for image recognition`.                      |
| **Filesearch (OpenAI Assistants)**       | RAG over uploaded PDFs/docs. See `Filesearch Using OpenAI Assistants`.                                                             |
| **Structured GPT responses**             | Force GPT to return JSON with named fields, parsable as `@results.gpt.<key>`. See `Structured responses in GPT webhook functions`. |
| **AI Assistants — file attachments**     | Send PDF / doc files as attachments via OpenAI Assistants. See `AI Assistants To Send Files As Attachments`.                       |
| **Gemini (speech)**                      | Speech-to-text and text-to-speech, used by `speech_to_text`, `text_to_speech` and `voice-filesearch-gpt`. Replaced the older Bhashini webhooks, which are removed. |
| **Exotel**                               | Telephony / IVR routing. See `Setting up Exotel`.                                                                                  |
| **Google Maps API**                      | Reverse geo-locate a `has location` response into an address. See `Google Maps API for reverse geo location`.                      |
| **Google Cloud Storage (GCS)**           | Required for sending/receiving media. See `Google Cloud Storage Setup - GCS`.                                                      |
| **WhatsApp Groups Automation (Maytapi)** | Manage WhatsApp Groups, send polls. See `WhatsApp Groups Automation Features`.                                                     |

---

# 13. Pre-launch checklist (before turning a chatbot live)

The "12 Pre-launch Chatbot Checks" condensed:

1. **Flows are tested** end-to-end on the simulator and a real WhatsApp number.
2. **Keywords are unique** across active flows (or `Ignore Keywords` is properly set).
3. **HSM templates are approved** for any out-of-session messaging.
4. **Default flow** (auto-reply when no keyword matches) is set up.
5. **Out-of-office hours** flow is configured if applicable.
6. **Opt-in flow** is in place and the consent variable updates correctly.
7. **Opt-out flow** works and updates `optin_status`.
8. **GCS** is set up and active (or media won't send).
9. **BigQuery** is linked (or you'll have no analytics).
10. **Staff roles** are configured — at least one admin, and agents for the Chats screen.
11. **Triggers** for any scheduled broadcasts are scheduled correctly.
12. **Gupshup wallet** has sufficient balance and is not suspended.

See `Starter Kit / 12 Pre-launch Chatbot Checks` for the full list.

## 13.1 Other pre-launch tasks

📖 Source: https://glific.github.io/docs/docs/Starter%20Kit/12%20Pre-launch%20Chatbot%20Checks/

- **Icebreakers** (Meta-side): up to 4 short suggested questions shown to contacts on first chat. Set them up in your Meta Business account; see `How to set up icebreakers by Meta`.
- **Green Tick** (verified business badge): apply via Meta after meeting volume + traffic criteria. See `How to get Green Tick in Whatsapp Business`.
- **WhatsApp Quality Rating** check: monitor in Meta Business Manager. Low rating risks throttling. See `Check WhatsApp Quality Rating and Messaging Limits`.

---

# 14. Onboarding / setup (single-glance answers)

| Task                                               | Where                                                                            |
| -------------------------------------------------- | -------------------------------------------------------------------------------- |
| Pre-onboarding requirements                        | `Glific Overview` (top-level)                                                    |
| Onboarding form                                    | `Pre Onboarding / Onboarding Form Fill Up`                                       |
| Facebook business verification                     | `Pre Onboarding / Facebook Verification Process for WhatsApp Business API`       |
| Gupshup setup                                      | `Pre Onboarding / Gupshup Setup`                                                 |
| GCS setup                                          | `Pre Onboarding / Google Cloud Storage Setup - GCS`                              |
| BigQuery setup                                     | `Product Features / Reporting & Dashboard / BigQuery Setup and link with Glific` |
| Migrating from another tool                        | `Pre Onboarding / Migration to Glific`                                           |
| Suspending or deleting an account                  | `FAQ / Managing an Organization's Glific Account: Suspension and Deletion`       |
| Manage Gupshup wallet & suspension                 | `FAQ / Managing Gupshup Wallet Balance and Suspension`                           |
| Get Glific support (Discord, weekly Tuesday calls) | `FAQ / Get Glific Support`                                                       |

## 14.1 Operating cost rule of thumb

NGO running ~500 users with weekly reminders typically spends **₹10,000-15,000 per month** on WhatsApp messaging fees.

## 14.2 Getting support

📖 Source: https://glific.github.io/docs/docs/FAQ/Get%20Glific%20Support/

- **Discord**: https://discord.gg/47mGc5PrZJ — primary support channel, fastest responses.
- **Weekly Tuesday support call**: any NGO can join.
- **Consulting** for deeper help: paid; see consulting overview document linked in main docs.

---

# 15. Speed Sends, Searches, Notifications, Tags (less-common features)

## 15.1 Speed Sends

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Speed%20Sends/

Pre-written message snippets that staff pick from the chat window's down-arrow → **Speed sends** tab, so they don't retype common replies. Each has a Title, a Message body (with `@variable` support) and an optional attachment; they are multilingual. They are **not** a broadcast tool — to message a whole collection, use the **Collections** tab in Chats, or a trigger + flow.

## 15.2 Searches

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Searches/

Save filtered views of contacts/messages (e.g., "all contacts who answered Q3 incorrectly"). Reusable filters, plus the ability to act on the result (start a flow for them, label them, etc.).

## 15.3 Notifications

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

In-Glific alerts for failed flows, sync failures, template problems, contact-upload results, etc., at **Notifications** in the sidebar (Manager+). It is a read-only log — there is nothing to configure. Rows carry a category, a severity (Critical / Warning / Info) and a **Check** action that jumps to the entity. Separately, org admins can opt into low-balance warning emails at `/settings/organization`.

## 15.4 Tags

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Tags/

Lightweight labels you can attach to messages, contacts, HSM templates, interactive messages — for categorization and search.

## 15.5 Custom Certificates

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Custom%20Certificates/

Generate personalized certificates from a **Google Slides** template, using data captured in flows. The output is an image hosted on Google Cloud Storage, delivered via the `create_certificate` webhook ([20.11](#2011-create_certificate--generate-a-personalized-certificate)) — not a PDF. Only visible when the Certificates feature is enabled for your org.

## 15.6 Triggers

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

Schedule a flow to run for a contact / collection at a future date or on a recurrence. See `Product Features / Triggers`.

## 15.7 WhatsApp Forms

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

A form-builder UX for collecting structured data from contacts (newer feature). See `Product Features / WhatsApp Forms`.

## 15.8 Interactive Messages Re-response

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages%20Re-response/

Lets you re-send / re-prompt the same interactive message if the user's first reply didn't match. See `Product Features / Interactive Messages Re-response`.

## 15.9 Staff Management & Role Management

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

Roles: **Staff** (chats and assigned collections), **Manager** (adds flows, templates, triggers, searches, notifications), **Admin** (adds settings and bulk contact management), **Glific_admin** (platform-level: organizations, consulting hours), plus **Dynamic** roles for orgs that define their own. Set per user under **Manage → Staff**.

## 15.10 Collections

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Collections/

Named groups of contacts. A collection has a Title, a Description and optional assigned staff — membership is **not** rule-based; contacts are added manually, by CSV import, or by the **Add to Collection** / **Remove from Collection** flow nodes. Used for targeted broadcasts, AB-test cohorts, and **Split by collection Membership**. (For a rule-based view of contacts, use a **Saved Search** instead.)

---

# 16. Where to find specific things in the platform UI

| To find…                                             | Click…                                                                  |
| ---------------------------------------------------- | ----------------------------------------------------------------------- |
| Flows list                                           | Left panel → **Flows** → **Flows**                                      |
| Flow listing page filters (Active / Inactive)        | Flows page → filter dropdown (top-left of list). There is no Template filter — flow templates are on hold. |
| Webhook logs                                         | Left panel → **Flows** → **Webhook logs**                               |
| Google sheets integration                            | Left panel → **Flows** → **Google sheets**                              |
| Custom contact variables list                        | Left panel → **Manage** → **Contact variables**                         |
| HSM Templates                                        | Left panel → **Quick tools** → **HSM Templates**                        |
| Interactive Messages                                 | Left panel → **Quick tools** → **Interactive Msg**                      |
| Triggers (scheduled flows)                           | Left panel → **Quick tools** → **Triggers**                             |
| Saved searches                                       | Left panel → **Quick tools** → **Searches**                             |
| Speed sends                                          | Left panel → **Quick tools** → **Speed Sends**                          |
| Chats with contacts                                  | Left panel → **Chats**                                                  |
| Contact profile & history                            | Click any contact → opens their profile                                 |
| Collections                                          | Left panel → **Manage** → **Collections**                               |
| Tags                                                 | Left panel → **Manage** → **Tags**                                      |
| Staff / role management                              | Left panel → **Manage** → **Staff**                                     |
| Blocked contacts                                     | Left panel → **Manage** → **Blocked contacts**                          |
| Settings (org config)                                | Avatar / user menu → **Settings** (Admin only)                          |
| Notifications                                        | Left panel → **Notifications** (shows an unread badge)                  |
| AI assistants                                        | Left panel → **AI toolkit** → **AI Assistant**                          |
| Reset flow counts                                    | Inside a flow → editor header → **More** → **Reset flow count**         |
| Flow Revision History                                | Inside a flow → editor → **Revision History**                           |
| Generate WhatsApp link / QR for a flow               | Flow row → **Share** icon (needs the flow to have keywords)             |
| Export / Import a flow                               | Flow row → Export ↔ Flows page → **Import flow**                        |

---

# 17. API summary (for developers)

## 17.1 Base URL

```
https://api.<your-shortcode>.glific.com/
```

`<your-shortcode>` is your Glific subdomain. Find it in the URL of your Glific dashboard.

## 17.2 Authentication

`POST /api/v1/session` with the user's phone and password returns an access token. Send it as `Authorization: <token>` on subsequent calls. `POST /api/v1/session/renew` refreshes it.

## 17.3 Everything else is GraphQL

Apart from the auth endpoints above, Glific's API is a **single GraphQL endpoint**:

```
POST https://api.<your-shortcode>.glific.com/api
Authorization: <access token>
Content-Type: application/json
```

The full schema (queries, mutations, argument names) is documented at https://api.glific.com/. Common operations:

- `session` (REST, `POST /api/v1/session`) — get an access token
- `flows` query — list flows with ids, names, uuids and keywords
- `contacts` / `contact` queries, `updateContact` mutation
- `startContactFlow` / `startGroupFlow` mutations — start a flow
- `resumeContactFlow` mutation — resume a flow parked on a **Wait for result** node

## 17.4 OTP flow via Glific APIs

📖 Source: https://glific.github.io/docs/docs/FAQ/Using%20Glific%20APIs%20for%20OTP%20Authentication/

See `FAQ / Using Glific APIs for OTP Authentication`. Pattern: external app calls Glific to start an OTP-sending flow on a contact, then verifies the contact's response. `POST /api/v1/registration/send-otp` is the REST entry point for the registration OTP.

## 17.5 Resuming a parked flow

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/

**From your own system** — use the `resumeContactFlow` GraphQL mutation (requires a Manager-or-above token):

```graphql
mutation resumeContactFlow($flowId: ID!, $contactId: ID!, $result: Json) {
  resumeContactFlow(flowId: $flowId, contactId: $contactId, result: $result) {
    success
    errors { key message }
  }
}
```

`result` is a JSON scalar — pass it as a **stringified JSON object**. Its keys land in the flow under the Wait for result node's result variable.

**Glific's own async webhooks** (`speech_to_text`, `text_to_speech`, `filesearch-gpt`, `voice-filesearch-gpt`) do not use that mutation. They call back to `POST /webhook/flow_resume`, which is HMAC-signed: the callback must carry `organization_id`, `flow_id`, `contact_id`, `timestamp` and `signature`, and an unsigned or incomplete callback is silently dropped (it still answers 200). You do not call this endpoint yourself — Glific builds the signed callback URL when the node fires.

---

# 18. Final mappings — questions to canonical answers

A flat list of "user phrasing → answer key" so retrieval is robust.

| If the user asks something like…                                              | The canonical answer is in section…                            |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------- |
| "How do I get a parent flow's variable in a sub-flow?"                        | 3.4 — `@results.parent.<name>.input`                           |
| "How do I read a child flow result back in the parent?"                       | 3.5 — `@results.child.<name>.input`                            |
| "What's the syntax to access a result from a calling flow?"                   | 3.4                                                            |
| "How do I save user input?"                                                   | 3.1 (within flow), 3.2 (across flows)                          |
| "Difference between contact field and result variable?"                       | 3.3                                                            |
| "How do I make a counter?"                                                    | 3.7                                                            |
| "How to find which keyword triggered the flow?"                               | 3.6 / 8.13                                                     |
| "Where do I see all my custom variables?"                                     | 3.8 / 8.14                                                     |
| "How do I send media that changes per user?"                                  | 8.9                                                            |
| "Why isn't my flow working?"                                                  | 10                                                             |
| "What's the size limit for video / image?"                                    | 9                                                              |
| "How do I AB test?"                                                           | 8.6, 4.17 (Split Randomly)                                     |
| "How do I send a reminder if no response?"                                    | 8.5, 4.2 ("Continue when there is no response")                |
| "How do I branch on age?"                                                     | 8.3                                                            |
| "How do I read a webhook response?"                                           | 4.3 / 2.3                                                      |
| "Webhook is timing out, what do I do?"                                        | 4.4 (Wait for Result)                                          |
| "What's the syntax for today's date?"                                         | 2.5 / 5.4                                                      |
| "How do I validate a date input?"                                             | 2.7 / 5.7                                                      |
| "Can I edit an HSM after approval?"                                           | 7.6 — No, create new                                           |
| "Why was my HSM rejected?"                                                    | 7.5 — can't edit, create new                                   |
| "How many buttons can I have in an interactive message?"                      | 6.1 / 9 — 3 quick replies, 10 list items                       |
| "Why does my interactive message say 'Character policy violated'?"            | 6.4 — markdown `*` `_` not allowed                             |
| "How do I run a flow on a schedule?"                                          | 8.10 / 15.6 (Triggers)                                         |
| "How do I clear a contact's variables for testing?"                           | 8.12 — Terminate flows, then blank the variable                |
| "Where's the data for analytics?"                                             | 11 — BigQuery + DataStudio                                     |
| "How do I get support?"                                                       | 14.2 — Discord, Tuesday calls                                  |
| "What's the cost?"                                                            | 14.1 — ~₹10-15k/month for 500 users weekly                     |
| "How do I copy / move a flow?"                                                | 8.16 (copy), 8.17 (across accounts)                            |
| "How do I update another user's contact data from a flow?"                    | 19.1 — not possible from flow, use updateContact API + webhook |
| "How often does BigQuery / Looker Studio refresh?"                            | 19.2                                                           |
| "Are there session IDs in Glific?"                                            | 19.3                                                           |
| "Can I export user questions to CSV?"                                         | 19.4                                                           |
| "Can I add the bot to a WhatsApp group?"                                      | 19.5 — no, use Maytapi                                         |
| "How do I set the default flow?"                                              | 19.6                                                           |
| "How do I route flow on the first line of an LLM response?"                   | 19.7                                                           |
| "How do I change the GCS account linked to Glific?"                           | 19.8                                                           |
| "Can I integrate PayU / a payment gateway?"                                   | 19.9 — no                                                      |
| "Is there a limit on contacts in a collection?"                               | 19.10                                                          |
| "Where are result variables stored in Looker Studio?"                         | 19.11 — `flow_results` table                                   |
| "How do I send an audio file via webhook?"                                    | 19.12                                                          |
| "Sharing Google Sheets with PII data?"                                        | 19.13 — share with service account only                        |
| "How do I bulk import thousands of users?"                                    | 19.14                                                          |
| "Can the AI assistant read images inside PDFs?"                               | 19.15 — no                                                     |
| "Can I use a result variable in 'has a number between'?"                      | 19.16 — yes                                                    |
| "Can I trigger a flow from an image instead of a keyword?"                    | 19.17 — no                                                     |
| "How do I set up hourly triggers?"                                            | 19.18                                                          |
| "How do I enable OpenAI for filesearch-gpt?"                                  | 19.19 — Glific provides it, no key needed                      |
| "How do I set up RAG to web search fallback?"                                 | 19.20 — prompt-based                                           |
| "Chatbot is not responding at all"                                            | 19.21                                                          |
| "LLM is returning partial data / not all records"                             | 19.22                                                          |
| "How do I add Bengali / Marathi / new languages?"                             | 19.23                                                          |
| "Can I create a flow directly from an HSM template?"                          | 19.24 — no                                                     |
| "Google Sheet writes only once and stops"                                     | 19.25                                                          |
| "How do I capture both pin location and typed address?"                       | 19.26                                                          |
| "Unauthorized access error creating a WhatsApp form"                          | 19.27                                                          |
| "Can I use longer than 10-character single-choice options in WhatsApp Forms?" | 19.28 — no, Meta restriction                                   |
| "Form date field publish error"                                               | 19.29                                                          |
| "Bhashini speech_engine setup"                                                | 19.30 — Bhashini webhooks removed; Gemini now                  |
| "LLM webhook returns 200 but no message"                                      | 19.31                                                          |
| "Gupshup App ID field not clickable / locked credentials"                     | 19.32                                                          |
| "Staff can't create account, 'cannot send OTP'"                               | 19.33                                                          |
| "How do I initialize a contact field as empty string?"                        | 19.34                                                          |
| "BigQuery replica table out of sync"                                          | 19.35                                                          |
| "Staff account got auto-deleted"                                              | 19.36                                                          |
| "Can I get OpenAI usage metrics for our org?"                                 | 19.37 — no                                                     |
| "GCS shows inactive / subscription cancelled"                                 | 19.38                                                          |
| "Editing a flow says someone else is editing — Take Over"                     | 19.39                                                          |
| "Flow shows in preview but not on the Flows screen"                           | 19.40                                                          |
| "Where is the Call AI / LLM node?"                                            | 4.3 / 20 — there is none; use Call a webhook with method FUNCTION |
| "How do I send an email from a flow?"                                         | Not supported — the Send Email node is disabled in Glific       |
| "How do I connect Zapier?"                                                    | Not supported — the Call Zapier (resthook) node is disabled     |
| "How do I send airtime?"                                                      | Not supported — the Send Airtime node is disabled               |
| "How do I set a contact's name / status from a flow?"                         | 4.6 — not possible; Update Contact offers Language, Channel and your own contact variables |
| "Why won't my flow publish — deprecated webhook?"                             | 20.5 — migrate the Bhashini webhook nodes                       |

---

# 19. Operational FAQs and corrections (high-frequency wrong answers)

> This section addresses questions where the chatbot has historically given incorrect, technical, or "I don't have this in my docs" answers. Each entry is the **canonical correct answer**, written in plain language. Keep responses short and non-technical — refer users to support when the answer truly requires backend access.

## 19.1 Can I update another user's contact data from inside a flow?

**No.** A flow can only update the contact who is currently in the flow — you cannot directly update _another_ user's contact fields from inside a flow node.

**Workaround:** use Glific's **updateContact API** from your own backend, then call that backend via a webhook in the flow. Pattern:

1. Capture the input you want to write (e.g., `@results.target_phone`, `@results.new_value`).
2. Call your backend via a `Call a webhook` node, passing the target contact's identifier and the new value.
3. Your backend calls Glific's updateContact API to write the field on the target contact.

## 19.2 How often does BigQuery sync, and how often does Looker Studio refresh?

- **BigQuery** — the sync job runs **every 2 minutes** and does both new inserts and updates, so a row written in Glific normally appears in BigQuery within **2–4 minutes**. Each pass moves at most **500 rows per table**, so a big backlog drains over several ticks. A separate job at **23:58 UTC** does duplicate cleanup only. Sync is skipped for orgs with no message traffic in the last 12 hours, and stops entirely if BigQuery returns `PERMISSION_DENIED` (the credential is auto-disabled). If your dataset isn't refreshing at all, check Notifications for sync errors.
- **Looker Studio** — uses BigQuery as its source. By default the cache is **12 hours**; you can shorten this in the Looker Studio data source settings, or click "Refresh data" manually for an immediate refresh.

If your replica table looks stale, see 19.35.

## 19.3 Are there session IDs in Glific to identify a conversation?

- For **LLM conversations** (OpenAI Assistants, etc.) every conversation has a `thread_id` — this acts as a session identifier and is stored against the contact.
- For **regular WhatsApp messaging** there is no explicit `session_id` stored. The closest equivalent is the WhatsApp 24-hour session window (see 7.1) and the contact's flow run, but neither exposes a session ID you can query.

If you need conversation grouping for analytics, query messages from BigQuery and group by contact + time-window.

## 19.4 Can I export all the questions users are asking the chatbot as a CSV?

📖 Source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/

**Yes — via BigQuery.** Glific does not have a built-in "export questions" button, but every inbound message is captured in BigQuery. Steps:

1. Open the BigQuery console for your Glific project.
2. Run a query against the `messages` table, filtering on inbound direction and (optionally) a date range.
3. Use BigQuery's "Save results" → "CSV (local file)" option.

If you don't have BigQuery set up, see `Pre Onboarding / BigQuery Setup`.

## 19.5 Can the Glific chatbot be added to WhatsApp groups?

📖 Source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/WhatsApp%20Groups%20Automation%20Features/

**No.** WhatsApp does not allow business chatbots to be added to WhatsApp groups directly through the Cloud API.

**Workaround:** use **Maytapi** integration. Glific supports WhatsApp Groups Automation via Maytapi for sending messages, polls, etc. into groups. See `WhatsApp Groups Automation Features` and `Setting up WhatsApp Groups Automation for existing NGOs` in the main docs.

## 19.6 How do I set up the Default Flow so any unmatched message triggers it?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/New%20Contact%2C%20Default%20flow%20Out%20of%20office%20hours%20notifications/

The Default Flow runs whenever a contact sends a message that doesn't match any active keyword and isn't already in a flow.

**UI steps:**

1. Open **Settings** from the user/avatar menu at the bottom of the sidebar (Admin only).
2. Open the **Flows** tile (`/settings/organization-flows`).
3. Tick **Default flow** and pick the flow.
4. The same checkbox exposes the out-of-hours settings: **Select days**, **All day** or **Start**/**Stop** times, and a fallback **Select flow (all other days & times)**.
5. Click **Save**.

The same screen carries the other org-level flows:

- **New contact flow** — runs the first time a new contact messages the bot.
- **Optin flow** — runs when an opted-out contact comes back.
- **Regular expression flow** — runs when an incoming message matches a regex you supply.

There is no separate "Out of Office Flow" setting — out-of-office is the day/time configuration inside **Default flow**.

See `Product Features / Others / New Contact, Default flow Out of office hours notifications` in the main docs.

To know **which keyword/sentence** triggered the flow, use `@results.flow_keyword.input` (the matched keyword) or `@results.flow_keyword.category` (the full sentence the user typed). See section 3.6.

## 19.7 How do I read the first line / first word of an LLM response and route the flow?

📖 Source: https://glific.github.io/docs/docs/Integrations/Structured%20responses%20in%20GPT%20webhook%20functions/

The cleanest pattern is **prompt-based**, not expression-based:

1. **In your prompt to the LLM**, instruct it to return a single-word route label as the first thing — for example, "Reply with one of: COMPLAINT, FEEDBACK, ESCALATE, followed by the answer on the next line."
2. **Save the LLM response** in a webhook result, e.g., `@results.gpt.response`.
3. **Add a Split by Expression** node and branch on the route label. If you asked the LLM to return _only_ the route label (recommended), branch directly on the value. Otherwise, use a small expression to extract the first word.

For structured outputs (where the LLM returns JSON), use the **Structured GPT responses** integration — see main docs `Structured responses in GPT webhook functions`. Then branch on `@results.gpt.<your_field>`.

Avoid trying to slice the response with raw string operations — it's brittle. Make the LLM do the structuring.

## 19.8 How do I change the GCS account linked to Glific?

📖 Source: https://glific.github.io/docs/docs/Pre%20Onboarding/Google%20Cloud%20Storage%20Setup%20-%20GCS/

**UI steps:**

1. Open **Settings** from the user/avatar menu (Admin only).
2. Open the **Google Cloud Storage** tile (`/settings/google_cloud_storage`).
3. Click **Change credentials** and paste the new service-account JSON.
4. Click **Save**.

After saving, run a test (send a media file in a flow) to confirm the new bucket is being used.

## 19.9 Can I integrate a payment gateway like PayU / Razorpay / Stripe with Glific?

**No.** Glific does not have a built-in payment gateway integration. Payment links can be sent as plain URLs in a Send Message node, but no native processing/capture flow is supported.

If you need payment confirmation, you can:

- Send a payment link in a Send Message.
- Use a webhook to your backend to check payment status (your backend handles the gateway).
- Resume the flow with the payment outcome via the `resumeContactFlow` mutation ([17.5](#175-resuming-a-parked-flow)).

## 19.10 Is there a limit on the number of contacts in a collection?

**No hard limit.** However, very large collections cause delivery delays when broadcasting (each message has to be queued and sent individually within Gupshup's rate limits).

**Recommendation:** split very large audiences into multiple smaller collections (e.g., 5,000–10,000 each) so broadcasts complete in a reasonable time.

## 19.11 Where are result variables and contact variables stored in Looker Studio / BigQuery?

📖 Source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/

- **Result variables (`@results.*`)** — stored in the **`flow_results`** table in BigQuery. Each row = one result captured during a flow run for a contact.
- **Contact variables (`@contact.fields.*`)** — the field *definitions* are in **`contacts_fields`**; the *values* are on the contact's row in **`contacts`** (a repeated `fields` record, plus a flattened `raw_fields` text column for search). Changes over time show up in **`contact_histories`** (note the plural — there is no `contacts_history` table).

For Looker Studio dashboards: connect Looker Studio to BigQuery, then use `flow_results` for per-flow analytics and `contacts` for per-contact attributes. Joining them on `contact_phone` / `contact_id` is the most common pattern.

## 19.12 How do I upload an audio file from the user and send it to my backend via a webhook?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20a%20message/#chatbot-sending-the-media-to-the-end-user

1. Add a **Wait for Response** node, set Response Type to **has audio**, give it a result name (e.g., `voice_note`).
2. The audio URL becomes available as `@results.voice_note` (or `@results.voice_note.url`).
3. Add a **Call a webhook** node pointing to your backend API. In the Post Body, include the audio URL:
   ```json
   {
     "contact": "@contact",
     "audio_url": "@results.voice_note"
   }
   ```
4. Your backend downloads the audio from the URL and processes it (transcription, storage, etc.).

You don't need to base64-encode anything inside Glific — the webhook just sends the URL string, and your backend fetches the audio.

## 19.13 Google Sheets needs 'Anyone with the link' but we have PII — is there another way?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

**Yes.** Do **not** share the sheet as "Anyone with the link". Instead:

1. Find your Glific service account email (from your GCP project, the same one used for GCS / BigQuery).
2. In your Google Sheet, click **Share**.
3. Add the **service account email** as an editor.
4. The sheet will now be readable by Glific without making it public.

This is the recommended setup for any sheet containing PII.

## 19.14 How do I onboard tens of thousands of users at once?

Use the **Bulk Import Contacts** feature:

1. Go to **Manage** → **Contacts** (Admin only).
2. Click **Continue** to open the **Upload Contacts** dialog.
3. Upload a CSV (grab **Download Sample CSV** for the shape — Phone is mandatory; add columns matching your contact-variable shortcodes), pick a **Select collection**, and tick **Please confirm if contacts are opted in.**
4. The import runs in the background — track it under **Notifications** (Contact Upload category), where **Check** downloads a per-row status CSV.

For very large imports (tens of thousands), break the CSV into batches of around **5,000 contacts** to keep the import responsive and avoid timeouts. For 27,000 users, that's ~6 batches.

## 19.15 Can the AI assistant read images inside a PDF?

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

**No.** The OpenAI Assistant filesearch feature only extracts and indexes **text** from PDFs. Images embedded in the PDF are not analyzed.

If you need image understanding, use the **GPT integration for image recognition** integration separately, passing image URLs explicitly. See `Integrations / GPT integration for image recognition`.

## 19.16 Can I use a result variable inside a 'has a number between' condition in Wait for Response?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/

**Yes.** You can put `@results.<name>` or `@contact.fields.<name>` as either bound of the range. Example: if a previous step saved `@results.min_age` and `@results.max_age`, the range field can use those variables instead of fixed numbers.

## 19.17 Can I trigger a flow from an image instead of a keyword?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Keywords/

**No.** Flows can only be started by:

- A keyword (text the contact types)
- The **Default flow** (any unmatched message), the **New contact flow**, the **Optin flow**, or the **Regular expression flow** — all set at `/settings/organization-flows`
- A **Trigger** (scheduled, against a collection)
- **Enter another flow** or **Start somebody else in a flow** (from another flow)
- A staff member using **Start a flow** from the Chats screen
- The `startContactFlow` / `startGroupFlow` GraphQL mutations from your backend

There is no "image as trigger" mechanism. (Resuming a parked flow is not a trigger — it continues a flow that is already running.)

**Workaround:** trigger on a keyword or the default flow, then use **Wait for Response** with the `has image` operator to accept the image at that point.

## 19.18 How do I set up hourly triggers?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

Triggers support hourly recurrence:

1. Go to **Quick tools** → **Triggers**.
2. Click **+ Create**.
3. Pick the flow, the contact / collection, and the start date/time.
4. Set **Repeat** to **Hourly**.
5. Save.

Daily, weekly, and monthly recurrences are also available from the same dropdown.

## 19.19 How do I enable OpenAI for filesearch-gpt / voice-filesearch-gpt webhooks?

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

**You do not need to add your own OpenAI key.** Glific provides the OpenAI integration centrally — these webhooks (`filesearch-gpt`, `voice-filesearch-gpt`, `text_to_speech`, `speech_to_text`) work out of the box for organizations on Glific.

If a specific webhook isn't working, check Webhook Logs (Flows → Webhook logs) for the error, and reach out to Glific Support on Discord.

## 19.20 How do I make the AI search the web when the answer isn't in the knowledge base?

This is **prompt-based**, not a configuration toggle. In the system/instruction prompt of your OpenAI Assistant or LLM webhook, add an instruction like:

> "If the answer is not present in the provided knowledge base, use your general/web knowledge to answer the question and clearly indicate the source."

There is no Glific-side "web search fallback" toggle. Behavior is controlled entirely by what you instruct the LLM to do.

## 19.21 The chatbot is not responding at all — what should I check?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/

1. **Gupshup wallet balance.** A depleted wallet stops all outbound messages. Top it up.
2. **Notifications** in the left sidebar. Look for delivery errors, BSP errors, or template errors.
3. **Gupshup app status.** Log into Gupshup; ensure the app is Active and the API key is valid.
4. **Contact opt-in.** If contacts are not opted in, outbound HSM templates may fail.
5. **If all of the above check out**, reach out to **Gupshup Support** — the issue is most likely on their side (BSP outage, account suspension, etc.).

Don't try to debug from the flow side first; the flow rarely is the cause of a complete no-response situation.

## 19.22 The LLM is only returning partial data / not all records from the uploaded file.

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

The fix is **prompt-side**. Update your system prompt to explicitly instruct the LLM to:

- Refer to **all documents** in the knowledge base, not just the first match.
- Return all matching records.
- Not summarize unless asked.

Example phrasing: "Search across all uploaded documents. Return every record that matches. Do not summarize or omit entries."

If the file is very large, also consider splitting it into smaller, focused documents — the assistant retrieves better against well-scoped corpora.

## 19.23 How do I add a new language (Bengali, Marathi, etc.) to our chatbot?

**Org-level setting:**

1. Open **Settings** from the user/avatar menu → **Organization** tile (`/settings/organization`).
2. Add the languages you want in **Supported languages** (multi-select), and check that **Default language** is one of them.
3. Click **Save**.

After this, you can:

- Translate HSM templates into the new languages.
- Use auto-translate on Interactive Messages (see 6.5).
- Switch a contact's language mid-flow with an **Update Contact** node — pick **Language** from the property dropdown. (You read it back as `@contact.language`; you don't write to that expression.)

## 19.24 Can I create a flow directly from an existing HSM template (so the template becomes the first node)?

**No, there is no one-click "create flow from template" option.**

The manual path:

1. Create a new flow.
2. Add a Send Message node as the first node.
3. Inside it, switch to the **HSM Templates** tab and pick your approved template.
4. Add a Wait for Response immediately after (mandatory after an HSM — see 7.2).
5. Continue building the flow.

## 19.25 I linked a Google Sheet but the bot only wrote to it once, then stopped.

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

Check, in this order:

1. **Sheet permissions** — confirm the Glific service account is still an editor (see 19.13). Owners sometimes accidentally remove access.
2. **Sheet status** in Glific — **Flows → Google sheets** (`/sheet-integration`). Check the sheet row's sync status and failure reason, and that **Allowed Operations** actually includes Write. (The `/settings/google_sheets` tile holds the service-account credentials — a different screen.)
3. **Sheet quota** — Google enforces row, cell, and write-rate limits. For high-volume writes, this is the most common cause.
4. **Recommendation for scale** — for high-volume writes, fetch from BigQuery into Sheets on a schedule rather than writing directly from the chatbot. The direct-write path is fine for low volume but not reliable at scale.

## 19.26 Some users send pin location, others type their address — how do I capture both?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/

Use **two response categories** in a single Wait for Response node:

1. Add the Wait for Response node.
2. Add response type **has location** (catches the pin drop).
3. Add a second response type **has any of the words** with the field left blank (catches any text reply, including a typed address).
4. Branch the flow based on which category fired.

The pin location is stored as longitude/latitude; the typed address stays as plain text. Process them differently downstream (e.g., reverse-geocode the lat/long, store the typed text as-is).

## 19.27 'Unauthorized access' error when creating / publishing a WhatsApp form.

This is almost always a **Gupshup-side** issue, not a flow issue.

1. Log into Gupshup and confirm your app is **Live** (not Sandbox or Pending).
2. Confirm your WABA (WhatsApp Business Account) is verified and active.
3. Confirm the API key in Glific Settings matches the live Gupshup app.
4. If all the above are correct and the error continues, reach out to Gupshup Support.

## 19.28 How do I use longer than 10-character text in a single-choice option in WhatsApp Forms?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

**You can't.** This is a **Meta-side restriction** on WhatsApp Forms — single-choice option labels are capped at 10 characters by WhatsApp's API. There is no Glific-side workaround.

If you need longer option text, redesign the form to use a different field type (free-text, dropdown, etc., depending on what's available), or shorten the option label and put the explanation in the question text.

## 19.29 'An error occurred' when publishing a WhatsApp Form with a custom date range.

Two things to check:

1. **Form JSON validity** — open the form's JSON view and confirm it's well-formed. Date field validation rules are a common source of malformed JSON.
2. **Reach out to Glific Support** — form publish errors often need backend inspection. Don't try to debug Meta's response codes on your own.

## 19.30 How do I configure the speech engine for voice?

📖 Source: https://glific.github.io/docs/docs/Integrations/Speech-to-text%20and%20Text-to-speech%20in%20Glific/

Glific uses **Gemini** for speech-to-text and text-to-speech. The old Bhashini webhooks (`speech_to_text_with_bhasini`, `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini`) have been **removed** — a flow that still calls one fails to publish. Use `speech_to_text` ([20.3](#203-speech_to_text--transcribe-a-voice-note)) and `text_to_speech` ([20.4](#204-text_to_speech--generate-a-voice-note-from-text)) instead.

The only engine knob left is the optional `speech_engine` key in the `voice-filesearch-gpt` body: omit it for Gemini (the default), or set it to `open_ai` for OpenAI TTS.

## 19.31 The LLM webhook returns 200 but no answer is sent to the user.

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

Don't try to diagnose this from the flow JSON or message tables. Check, in order:

1. **Webhook Logs** (Flows → Webhook logs). Click the relevant log row and view the **Response JSON**. Confirm it actually contains the answer field your flow is reading (`@results.gpt.message` or whichever key).
2. **Webhook configuration in the flow** — the Result Name on the webhook node and the JSON key being referenced must match exactly. A typo (e.g., `messsage` vs `message`) silently produces an empty body.
3. If the response JSON has the answer but the flow still doesn't send it, the Send Message node downstream may be referencing the wrong variable name.

## 19.32 Gupshup verification — App ID field is not clickable, or credentials are locked.

📖 Source: https://glific.github.io/docs/docs/Pre%20Onboarding/Gupshup%20Setup/

**Once Gupshup credentials (App Name, API Key, App ID) are saved in Glific, they become non-editable from the UI.** This is intentional, to prevent accidental misconfiguration.

To change them, **reach out to the Gupshup team** (or Glific Support) — they will update the credentials on their side. There is no self-service way to overwrite locked credentials from Glific.

## 19.33 A staff member can't create a Glific account — 'cannot send OTP' error.

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

1. Check the staff member's **BSP status** on their phone number — if `bsp_status` is `none` or `invalid`, OTPs can't be delivered to that number.
2. Check **Notifications** in Glific for any explicit "OTP send failed" errors.
3. Make sure the staff member is using a **personal phone number**, not the chatbot number.
4. Glific recommends signing up via **Google** with a shared/common email like `info@yourorg.org` so multiple team members can access the same staff account.
5. If none of the above resolves it, reach out to Glific Support.

## 19.34 How do I initialize a contact field as a blank / empty string?

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

Use the **Update Contact** node:

1. Add an Update Contact node.
2. Pick the contact field you want to initialize.
3. **Leave the value field empty** (don't type anything, including not typing `""`).
4. Save.

When the flow runs, the field is set to empty. The field is created the first time you write to it — there's no separate "create blank field" step.

## 19.35 Our BigQuery replica table is out of sync with the primary table.

Don't try to debug this from BigQuery directly. From the Glific side:

1. Check **Notifications** for any BigQuery-related errors (auth failures, schema drift, permission denials).
2. Confirm BigQuery is **Active** in Settings → BigQuery (the integration toggle).
3. If the integration is Active and there are no errors but the table is still stale, **reach out to Glific Support** with your org shortcode and the table name. Sync issues usually need backend investigation.

## 19.36 A staff account was 'auto-deleted' — how does this happen?

Staff accounts are not auto-deleted by the system on a schedule. The most common cause:

- **The contact behind the staff user was deleted.** In Glific, every staff user is tied to a contact record. If the contact is deleted (often during testing or cleanup), the staff account becomes unusable / appears deleted.

To prevent this, **never delete the contact record** of someone who has staff access. To remove staff access, change their **Role** to None instead of deleting the contact.

## 19.37 Can I get OpenAI usage / token / cost metrics for our org from Glific?

**No, not currently.** Glific does not expose per-org OpenAI usage in its UI. If your org uses Glific's central OpenAI integration (no own key), you don't get a usage breakdown.

If you have your own OpenAI key configured, view usage at https://platform.openai.com/usage in your OpenAI account.

## 19.38 GCS / our Glific subscription says 'cancelled' or 'inactive' but we didn't cancel.

📖 Source: https://glific.github.io/docs/docs/FAQ/Managing%20an%20Organization%27s%20Glific%20Account%3A%20Suspension%20and%20Deletion/

Check, in this order:

1. **BigQuery integration status** in Settings — sometimes a "cancelled" message is actually a BigQuery / GCS service account expiry showing up in the UI.
2. **Gupshup wallet balance** — a long depletion can lead to suspension warnings.
3. **Glific Support** — reach out immediately on Discord (https://discord.gg/47mGc5PrZJ) or email support@glific.org. Don't try to fix this from settings; account-status changes need backend inspection.

Glific subscriptions don't cancel automatically — there's almost always an underlying service issue or a misread message.

## 19.39 The flow editor says someone else is editing — how do I take over?

Glific shows a banner with **View Only Mode** and a **Take Over** button when another user has the flow open.

1. Click **Take Over** to switch to edit mode. The other user is dropped into View Only.
2. Coordinate with that person if you don't want to interrupt their work — only one editor at a time can save changes.

This is the only step needed. (The "archive the published revision" path is only relevant in very rare backend scenarios and isn't part of normal flow editing.)

## 19.40 The flow is visible in Preview but doesn't show on the Flows screen.

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/

Preview only runs the flow in the simulator — it doesn't change visibility on the Flows list. Likely causes:

1. **Filter** at the top of the Flows page. It defaults to **Active**, and the only other option is **Inactive** — there is no "All". If your flow is inactive it simply won't appear until you switch the filter.
2. **`is active?`** is unchecked — visible-but-faded flows are often inactive. Toggle it on (Edit → `is active?`).
3. **Search field** — clear any text in the search box; it filters the list.
4. **Pagination** — scroll down or check page 2; long lists paginate.

If after all of these the flow is still not visible, reach out to support.

---

# 20. Built-in Webhooks Reference

Glific ships a set of built-in webhook functions you call from a **Call a webhook** node. They cover the common things flows need to do: LLM calls, speech-to-text, text-to-speech, file-search assistants, geolocation, certificate generation, and WhatsApp group polls.

**How to use any of these:**

1. Add a **Call a webhook** node (see [4.3](#43-call-a-webhook)).
2. Set **Method** to `FUNCTION` (not GET or POST) and put the function name in the **URL** field, exactly as spelled below.
3. Paste the body shape shown below and fill in the variables (typically `@contact`, `@results.<...>`, or a literal).
4. Set a **Result Name** — that becomes the prefix you read response keys from: `@results.<result_name>.<key>`.

Every webhook returns a JSON object with a `success` (true/false) field. If `success` is false, check **Flows → Webhook logs** for the error payload.

**The complete list.** These eleven names are the only built-in functions Glific recognises; any other name in the URL field with method `FUNCTION` fails at runtime:

`parse_via_chat_gpt` · `parse_via_gpt_vision` · `speech_to_text` · `text_to_speech` · `filesearch-gpt` · `voice-filesearch-gpt` · `geolocation` · `send_wa_group_poll` · `create_certificate` · `get_buttons` · `check_response`

## 20.1 `parse_via_chat_gpt` — call a GPT model with a prompt

**What it does.** Sends a user question and a system prompt to a specified GPT model and returns the model's reply.

**Body:**

```json
{
  "question_text": "@results.user_question",
  "prompt": "You are a helpful assistant for an NGO helpline.",
  "model": "gpt-4o",
  "temperature": 0
}
```

- `question_text` is **required** — an empty one errors with _"question_text is empty"_.
- The model key is `model`, not `gpt_model`. It defaults to `gpt-4o`; `temperature` defaults to `0`.
- `response_format` is optional — use it for structured JSON responses.

**Response:**

```json
{
  "success": true,
  "parsed_msg": "I'm sorry, but I need the specific details of the issues reported..."
}
```

**Read in flow:** `@results.<name>.parsed_msg`

**Use it for:** one-shot LLM calls — classification, summarization, Q&A on text the flow already has. For knowledge-base / document Q&A use `filesearch-gpt` instead.

## 20.2 `parse_via_gpt_vision` — analyze an image with GPT Vision

**What it does.** Sends an image URL and a prompt to a GPT Vision model and returns the model's structured analysis.

**Body:**

```json
{
  "prompt": "Describe what is in this photo and list the objects as JSON.",
  "url": "@input.media_url",
  "organization_id": "@organization.id"
}
```

- `url` is validated as an image first — a bad or unreachable URL fails with the media-validation message.
- Pass `organization_id` so Glific can download the image from Gupshup and inline it (Gupshup media URLs expire, so a bare link handed to OpenAI would 404).
- `response_format` is optional, for structured JSON output.

**Response:**

```json
{
  "success": true,
  "response": {
    "summary": "A car parked near trees on a sunny road.",
    "detected_objects": ["car", "tree", "road"]
  }
}
```

**Read in flow:** `@results.<name>.response.summary`, `@results.<name>.response.detected_objects`

**Use it for:** classifying user-uploaded photos, extracting fields from documents, OCR-style tasks. The exact shape of `response` depends on what you ask for in `prompt` — ask for JSON keys explicitly if you want stable parsing.

## 20.3 `speech_to_text` — transcribe a voice note

**What it does.** Takes a WhatsApp voice-note URL and returns the transcribed text. This is an **async** webhook: it acknowledges immediately, parks the flow, and resumes it via callback when the transcription is ready — so put a **Wait for result** node after it ([4.4](#44-wait-for-result)).

**Body:**

```json
{
  "speech": "@input.media_url",
  "organization_id": "@organization.id",
  "flow_id": "@flow.id",
  "contact_id": "@contact.id"
}
```

`organization_id`, `flow_id` and `contact_id` are **required** — they are how the callback finds the parked flow. Missing or non-numeric values give _"Invalid or missing flow metadata for Kaapi webhook"_. The `speech` URL must be `https` or you get _"Media URL is invalid"_ / _"Media URL is needed"_.

Optional tuning keys: `provider`, `model`, `language`, `output_language`.

**Read in flow:** the transcription arrives in the resume payload, under the result name you gave the node.

**Rate limit:** speech_to_text and text_to_speech share a per-org rate limit; when it trips the job snoozes and retries rather than failing.

## 20.4 `text_to_speech` — generate a voice note from text

**What it does.** Synthesizes audio from text and returns a hosted media URL you can send back to the user. Also **async** — same park-and-resume pattern as `speech_to_text`, so follow it with a **Wait for result** node.

**Body:**

```json
{
  "text": "@results.answer",
  "organization_id": "@organization.id",
  "flow_id": "@flow.id",
  "contact_id": "@contact.id"
}
```

Optional tuning keys: `provider`, `model`, `language`, `voice`.

**Read in flow:** the media URL arrives in the resume payload, under the result name you gave the node — send it with a Send Message node's attachment.

## 20.5 Deprecated: `speech_to_text_with_bhasini`, `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini`

These three Bhashini webhooks have been **removed**. They are gone from the flow-editor dropdown, and publishing a flow that still calls one fails validation with, e.g., _"The 'speech_to_text_with_bhasini' webhook is deprecated. Please migrate this node to the 'speech_to_text' node before publishing."_

Migration:

| Old | Use instead |
| --- | --- |
| `speech_to_text_with_bhasini` | `speech_to_text` ([20.3](#203-speech_to_text--transcribe-a-voice-note)) |
| `text_to_speech_with_bhasini` | `text_to_speech` ([20.4](#204-text_to_speech--generate-a-voice-note-from-text)) |
| `nmt_tts_with_bhasini` | `text_to_speech` ([20.4](#204-text_to_speech--generate-a-voice-note-from-text)) |

If an existing flow refuses to publish, this is the most likely reason — open each Call a webhook node and swap the function name.

## 20.6 The "call and wait" pattern — long-running LLM calls

**`call_and_wait` is not a webhook function.** It is the name of a sample flow ("Call and Wait Flow") that Glific seeds, demonstrating how to run an LLM call that may take longer than the webhook timeout.

The pattern:

1. **Call a webhook** node, Method `FUNCTION`, URL `filesearch-gpt`, with a `callback_url` in the body pointing at Glific's flow-resume endpoint.
2. A **Wait for result** node right after it (see [4.4](#44-wait-for-result)). This parks the flow until the callback arrives or the wait expires.

   Separately, if you put a `wait_time` key in the **Call a webhook** node's own body (the async-webhook form), the backend caps it at **5 minutes** — configure more and publishing warns you and uses 5 minutes anyway.
3. When the assistant finishes, the callback resumes the flow and the answer is available under the webhook node's result name.

Body shape for step 1:

```json
{
  "question": "@results.user_question",
  "flow_id": "@flow.id",
  "contact_id": "@contact.id",
  "assistant_id": "asst_xxxxxxxx",
  "callback_url": "https://<your-org>.glific.com/webhook/flow_resume"
}
```

## 20.7 `filesearch-gpt` — chat with an OpenAI Assistant that has files attached

**What it does.** Sends a question to a specified OpenAI Assistant (configured with file-search enabled and your documents uploaded) and returns the answer. Maintains a `thread_id` so follow-up questions in the same conversation stay in context.

This is an **async** webhook — it acknowledges immediately, parks the flow, and resumes it when the answer arrives — so follow it with a **Wait for result** node ([4.4](#44-wait-for-result)).

**Body:**

```json
{
  "question": "@results.user_question",
  "assistant_id": "asst_xxxxxxxx",
  "organization_id": "@organization.id",
  "flow_id": "@flow.id",
  "contact_id": "@contact.id",
  "thread_id": "@contact.fields.thread_id"
}
```

- `organization_id`, `flow_id` and `contact_id` are **required** — they are how the resume callback finds the parked flow.
- `assistant_id` is **required** (_"assistant_id is required"_ otherwise) and must resolve to an assistant configured in your org.
- `thread_id` is optional. Omit it and a new conversation is created; pass a saved one to continue an existing conversation.

**Response:**

```json
{
  "thread_id": "resp_0942351ee8cef32b0068f1e9c178808197b5802d79b26ec5eb",
  "success": true,
  "message": "The document does not contain that information.\n\nIf you have any specific questions about the ASER Report 2024, feel free to ask!"
}
```

**Read in flow:** `@results.<name>.message`, `@results.<name>.thread_id`

**Multi-turn:** save `thread_id` to a contact variable and pass it back in the `thread_id` body key on subsequent calls to preserve conversation context.

**Use it for:** knowledge-base Q&A. See [19.19](#1919-how-do-i-enable-openai-for-filesearch-gpt--voice-filesearch-gpt-webhooks) for OpenAI key configuration (you do not need your own key) and [19.22](#1922-the-llm-is-only-returning-partial-data--not-all-records-from-the-uploaded-file) for prompt-tuning tips.

## 20.8 `voice-filesearch-gpt` — voice in / voice out file-search

**What it does.** End-to-end voice pipeline on top of `filesearch-gpt`: takes a voice note, transcribes it with **Gemini**, translates if needed (Google Translate), asks the OpenAI Assistant, translates the answer back, and synthesizes audio in the target language. Bhashini is no longer in this path.

Optional body key `speech_engine`: leave it out (or empty) for the default **Gemini** TTS, or set it to `open_ai` for OpenAI TTS.

**Body:**

```json
{
  "contact": "",
  "speech": "",
  "assistant_id": "",
  "source_language": "",
  "target_language": ""
}
```

Pass `@contact` for `contact`, the voice-note URL (`@input.media_url`) for `speech`.

**Response:**

```json
{
  "translated_text": "\"To be yourself in a world that is constantly trying to make you something else is the greatest accomplishment.\" — Ralph Waldo Emerson\n\nIt seems like you might be expressing a sense of feeling overwhelmed or misunderstood...",
  "thread_id": "thread_UBXPd3VOCDIOux5TMwsT1qYQ",
  "success": true,
  "media_url": "https://storage.googleapis.com/cc-tides/uploads/Bhasini/outbound/7472cd34-...mp3"
}
```

**Read in flow:** `@results.<name>.translated_text` (send as text), `@results.<name>.media_url` (send as audio), `@results.<name>.thread_id` (save for multi-turn).

**Use it for:** voice-first multilingual chatbots where users send voice notes and expect voice replies in their own language.

## 20.9 `geolocation` — reverse-geocode a pin location

**What it does.** Takes latitude/longitude (typically from a WhatsApp pin-location message) and returns a structured address: city, state, country, postal code, district, full address.

**Body:**

```json
{
  "lat": "",
  "long": ""
}
```

Use `@input.location.latitude` and `@input.location.longitude` when the incoming message is a pin location.

**Response:**

```json
{
  "success": true,
  "city": "Lucknow",
  "state": "Uttar Pradesh",
  "country": "India",
  "postal_code": "226016",
  "district": "Gomti Nagar",
  "address": "B-4/32, Vivek Khand, Gomti Nagar, Lucknow, Uttar Pradesh 226016, India"
}
```

**Read in flow:** `@results.<name>.city`, `@results.<name>.state`, `@results.<name>.address`, etc.

**Use it for:** location-based routing, saving address to a contact field, region-specific responses. See [19.26](#1926-some-users-send-pin-location-others-type-their-address--how-do-i-capture-both) for the "user typed address vs sent pin" pattern.

## 20.10 `send_wa_group_poll` — push a poll to a WhatsApp group

**What it does.** Sends a pre-configured poll (built in Glific) to a target WhatsApp group.

**Body:**

```json
{
  "wa_group": "@contact.id",
  "poll_uuid": "the-poll-uuid",
  "organization_id": "@organization.id"
}
```

`wa_group` is the WhatsApp group ID; `poll_uuid` is the UUID of the poll you've created in Glific (find it in the Polls section); `organization_id` is required.

**Response:**

```json
{
  "success": true,
  "message": "Poll sent successfully to the WhatsApp group."
}
```

**Read in flow:** `@results.<name>.message`

**Note:** WhatsApp groups in Glific have their own constraints — see the WhatsApp Groups setting and [19.5](#195-can-the-glific-chatbot-be-added-to-whatsapp-groups).

## 20.11 `create_certificate` — generate a personalized certificate

**What it does.** Renders a certificate template (configured in Glific's Custom Certificates section) by substituting in contact-specific text, and returns the URL of the generated image.

**Body:**

```json
{
  "certificate_id": 5,
  "contact": "@contact",
  "replace_texts": { "name": "@contact.name", "course": "Module 4" },
  "organization_id": "@organization.id"
}
```

All four keys are **required**:

- `certificate_id` — ID of the certificate template you created in Glific (integer, or a string that parses to one).
- `contact` — pass `@contact`.
- `replace_texts` — object mapping placeholder keys in the template to values.
- `organization_id` — pass `@organization.id`.

**Response:**

```json
{
  "certificate_url": "https://storage.googleapis.com/glific-media-bucket/certificate_id_5_contact_12345.png",
  "success": true
}
```

**Read in flow:** `@results.<name>.certificate_url` — pass into a **Send Message** node as an image to deliver the certificate to the contact.

**Use it for:** course-completion certificates, participation badges, leaderboard awards. See [15.5](#155-custom-certificates) for template setup.

---

_End of companion knowledge base. For UI screenshots and visual examples, refer back to the main `merged_documentation 2.md` or the live docs at https://glific.github.io/docs/._

## 20.12 `get_buttons` — split text into quick-reply buttons

**What it does.** Purely local, no external call. Takes a `|`-delimited string and splits it into numbered buttons — handy when the button labels come from an LLM answer or a Google Sheet cell rather than being fixed in the flow.

**Body:**

```json
{
  "buttons_data": "@results.options"
}
```

**Response:**

```json
{
  "buttons": { "button_1": "Yes", "button_2": "No", "button_3": "Maybe" },
  "button_count": 3,
  "is_valid": true
}
```

Read them as `@results.<result_name>.buttons.button_1`, etc. If `buttons_data` is missing or isn't text, the node errors with _"get_buttons requires buttons_data as a `|`-delimited string"_.

## 20.13 `check_response` — compare an answer to the expected one

**What it does.** Purely local, no external call. Compares two strings (Unicode-equivalent comparison) — useful for quizzes where the correct answer is stored in a contact variable or a sheet rather than hard-coded in a Wait for Response case.

**Body:**

```json
{
  "correct_response": "@results.answer_key",
  "user_response": "@results.user_answer"
}
```

**Response:**

```json
{ "response": true }
```

Branch on `@results.<result_name>.response`. If either field is missing or isn't text, the node errors with _"check_response requires correct_response and user_response as text"_.
