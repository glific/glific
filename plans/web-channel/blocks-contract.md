# Blocks — frozen wire contract (v1)

Supersedes `custom-ui-contract.md`. **Every repo implements against this file.** Field names,
enum atoms, socket event names and block schemas here are FROZEN — if something needs to change,
change it here first and tell the other repos.

Renamed from "Custom UI" to **Blocks** in v1. The term "custom UI" no longer appears in any
identifier, enum value, label or user-facing string.

Repos and branches (all on `web-channel-prototype`):

| Repo | Working copy |
|------|--------------|
| glific (backend) | `.../glific/.claude/worktrees/custom-ui` |
| glific-frontend (staff console) | `.../glific-frontend-custom-ui` |
| glific-web-channel (widget) | `.../glific-web-channel` |
| floweditor | `.../floweditor` |

## v1 decisions taken without an explicit answer

Recorded so they are cheap to reverse. Each is one place in this file:

| # | Decision | Alternative if reversed |
|---|---|---|
| A | Flow results stay **flat** (`@results.picker.course`); no `raw` wrapper. Protected by a reserved-id validator (§5). | Nest values under `raw` |
| B | Typed node key is **`kind`**; six kinds; `image_alt` is a sibling node; `translate` reserved but ignored in v1 (§2). | `type` as the node key |
| C | Blocks templates are **auto-translate only**; the manual CSV export skips them (§10). | Path-keyed CSV round-trip |

---

## 1. Enums

- `message_type_enum` gains **two** values: `blocks` (outbound) and `blocks_response` (inbound).
- `interactive_message_type_enum` gains **one** value: `blocks` (the template type).
- GraphQL enum value for the template type: `BLOCKS`.
- `@message_type_const` and `@interactive_message_type_const` in
  `lib/glific/enums/constants/enums.ex` must match.

**The two migrations are edited in place, not superseded.** `custom_ui` / `custom_ui_response`
exist only in unmerged migration files and local dev/preview databases — they are absent from
`structure.sql`. Renaming therefore costs an `ecto.reset`, not a second `ADD VALUE`. Do not add
new enum values alongside the old ones.

Migrations keep the `20260715085249_add_web_message_flow_type.exs` pattern
(`@disable_ddl_transaction true`, `@disable_migration_lock true`, `ADD VALUE IF NOT EXISTS`).

## 2. The stored template payload (`interactive_templates.interactive_content`)

Authored content is **typed**: every leaf a human wrote is a node, so the translation walker and
the validator can find it without knowing the component's schema.

```jsonc
{
  "type": "blocks",                      // REQUIRED. Plain scalar. Existing plumbing derives the
                                         // message type from interactive_content["type"]
                                         // (contact_action.ex:109)
  "version": 1,                          // REQUIRED. Plain scalar, integer
  "component": "glific/carousel",        // REQUIRED. Plain scalar
  "props": {                             // schema-checked for glific/*, opaque otherwise
    "id": "product",                     // structural — plain string
    "body": { "kind": "text", "value": "Browse our courses" },
    "cards": { "kind": "list", "value": [
      { "id": "p1",                                                    // structural
        "title":     { "kind": "text",  "value": "Course A" },
        "image":     { "kind": "image", "value": "https://…/a.png" },
        "image_alt": { "kind": "text",  "value": "Students at desks" } }
    ]}
  },
  "context": { }                         // OPTIONAL, echoed back verbatim, never typed
}
```

There is **no `fallback` field.** It is removed in v1 — see §9 for what replaced it.

### 2.1 Typed nodes

A **typed node** is a JSON object containing exactly the key `kind`, the key `value`, and
optionally `translate`. No other keys. Anything else is a plain value.

| `kind` | `value` must be | Translated? |
|---|---|---|
| `text` | string | yes (unless `translate: false`) |
| `alt` | string | yes (unless `translate: false`) |
| `image` | string, an absolute `http(s)` URL | no |
| `url` | string, an absolute `http(s)` URL | no |
| `number` | JSON number | no |
| `boolean` | JSON boolean | no |
| `list` | JSON array; each element is a plain object whose leaves may be typed nodes | recurses |

`alt` is a distinct kind, not a flavour of `text`, precisely so the body derivation (§9) can skip
it. Alternative text is accessibility metadata, not body copy: were it `text`, every carousel's
`messages.body` — and therefore the staff conversation-list preview and the message search index —
would read `Browse our courses — Course A — Students at desks — Six weeks, evenings`. Kinds carry
semantics, so the walker stays key-agnostic rather than special-casing the key name `image_alt`.

`translate: false` is **accepted and validated in v1 but has no effect** — v1 translates every
`text` node. It exists now so brand names and codes do not require re-validating stored payloads
later.

**Structural keys are never typed**: `type`, `version`, `component`, `context`, `props.id`, and
every `id` inside a list item. Ids are **always strings**.

### 2.2 The unwrap rule

Every typed node collapses to **exactly its `value`**, recursively, with no exceptions. Uniformity
is the point: it makes the unwrapped output byte-identical to what the widget already renders, so
the widget needs no change for typing.

```
unwrap(m) when m is a map with keys ⊆ {kind, value, translate} and both kind and value present
  → unwrap(m.value)
unwrap(m) when m is a map    → map over values
unwrap(l) when l is a list   → map over elements
unwrap(v)                    → v
```

This is why the node key is `kind` and not `type`. The walker descends the whole payload; were the
key `type`, the envelope itself (`{"type": "blocks", "component": …}`) would match as a typed node
and collapse, and `contact_action.ex:109` reads `interactive_content["type"]` to set the message
type. The same collision would hit v2 form fields, where `type` will mean input-widget type
(`number` / `date` / `select`).

**Where unwrap runs:** `contact_action.ex`, after `MessageVarParser.parse_map/2` (line 103) and
before the attrs map (line 106). Order is `translation → dynamic params → parse_map → unwrap →
validate → persist`. `parse_map` reaches string leaves inside typed nodes, so `@contact.*` and
`@results.*` substitution is unaffected.

**Who sees which form:**

| Consumer | Form | Change needed in v1 |
|---|---|---|
| glific-web-channel (widget) | unwrapped wire | **none** |
| `messages.interactive_content` | unwrapped | — |
| `interactive_templates.interactive_content` | typed | — |
| glific-frontend editor / preview / inbox | typed → unwraps client-side | shared JS `unwrap()` helper |
| floweditor canvas | typed | walker to derive canvas text (§9) |

## 3. Outbound: backend → widget

`MessageSerializer.serialize/1` for a blocks message. `interactive_content` here is the
**unwrapped** payload:

```jsonc
{
  "id": 4211,
  "body": "Browse our courses",          // the derived body — see §9
  "type": "blocks",
  "flow": "outbound",
  "inserted_at": "…",
  "media": null,
  "interactive_content": {
    "type": "blocks",
    "version": 1,
    "component": "glific/carousel",
    "props": { "id": "product", "body": "Browse our courses", "cards": [ … ] },
    "context": { },
    "answered": false,                   // added on response receipt
    "answer_summary": null               // added on response receipt
  }
}
```

`answered` / `answer_summary` are written INTO the outbound message's stored
`interactive_content` when the response is accepted, so `serialize/1` stays a pure map read (no
per-message query — history fetches a page at a time).

## 4. Inbound: widget → backend

Socket event name: **`blocks_response`** on topic `web_channel:<contact_id>`.

```jsonc
{
  "message_id": 4211,                    // the outbound blocks message being answered
  "component": "glific/carousel",        // echo
  "values": { "product": "p1" },         // keyed by ids from props
  "summary": "Course A",                 // REQUIRED plain string; §6 is normative for glific/*
  "context": { }                         // OPTIONAL echo
}
```

Reply convention follows the existing channel: `{:reply, :ok, socket}` or
`{:reply, {:error, %{reason: "…"}}, socket}`.

### Persisted inbound message

- `type: :blocks_response`
- `body:` the `summary` string
- `context_message_id:` the outbound message id (correlation; no new column)
- `channel: "web"`, `flow: :inbound`, `bsp_status: :delivered`, `status: :received`
- `interactive_content:`
  ```jsonc
  { "type": "blocks_response", "component": "…", "values": { }, "summary": "…", "context": { } }
  ```

## 5. Flow results

New clause in `router.ex`'s `update_context_results/4` cond, alongside `[:quick_reply, :list]`:

```elixir
msg.type in [:blocks_response] ->
  json =
    default_results                                  # "input" (= summary), "category", "inserted_at"
    |> Map.merge(normalized_values)                  # the values map, flattened in
    |> Map.put("summary", summary)
    |> Map.put("component", component)

  %{key => json}
```

Values are **flat** (decision A). `@results.picker.course` == `"p1"`,
`@results.picker.summary` == the summary, `@results.picker.input` == the summary too.

### 5.1 Reserved result ids (the price of flat)

Flattening means an author-chosen id can overwrite a reserved key. **Every `props.id`, option id,
card id and field id is rejected at save if it is one of:**

```
input   category   inserted_at   summary   component   value
```

The one that actually bites is `input`: it silently replaces what a bare `@results.picker`
resolves to, so the author's summary vanishes with no error. `value` is the second — `bound/1` in
`MessageVarParser` unwraps a map result to `substitution["value"]`. Validated in **both** the
backend (`Glific.Templates.Blocks`) and the console editor, with the same message.

### 5.2 Expression-parser limits (`MessageVarParser`)

- **At most 5 dot-segments** resolve (`@results.a.b.c.d`). Flat values leave three spare.
- **Numeric leaves are unsafe.** `bound/1` returns the raw term into `String.replace/4`, which
  treats an integer as iodata: `16` renders as byte `0x10` and `999` raises `ArgumentError`,
  crashing the flow. Therefore **every value written into flow results is stringified**
  (`to_string/1`) before the merge. This applies to `number` and `boolean` kinds.

### Routing (no new case operator)

`find_category/3` (`router.ex:325`) falls through to `router.default_category_uuid` when no case
matches. The floweditor branch emits **zero cases and a single default category "Responded"** —
mirroring `location_request_message`. Any `blocks_response` (and any text reply from a non-web
contact) takes that exit.

## 6. Built-in block schemas (`glific/*` — permanent)

Component names follow **DNS label syntax, two segments**:
`^[a-z0-9]([a-z0-9-]*[a-z0-9])?/[a-z0-9]([a-z0-9-]*[a-z0-9])?$` — lowercase alphanumerics and
hyphens, **no underscores**, exactly one `/`. The `glific/` namespace is reserved: a `glific/<name>`
not in this catalog is rejected at save. Any other namespace (`tap/*`) is opaque — envelope and
typed-node validation only, no props schema.

**Rules for every `glific/*` block** (all repos must agree — these were the drift found in v0
cross-repo review):

- Every key below is REQUIRED unless marked OPTIONAL.
- **Unknown keys are rejected** in `props` and in each list item, in both console-side and
  backend-side validation. Same rule, same message.
- **Item ids are unique within a block** and pass the §5.1 reserved-id check. Duplicates silently
  lose data — the widget keys React elements and the `values` map by id.
- Renderers stay tolerant of a missing optional value at runtime; console and backend both reject
  it at save.

Schemas are shown in **stored (typed)** form. `T(x)` abbreviates `{"kind":"text","value":x}`,
`I(x)` abbreviates `{"kind":"image","value":x}`, and `A(x)` abbreviates `{"kind":"alt","value":x}`.

### `glific/image-panel`

```jsonc
{
  "id": "course",                                   // REQUIRED, the key the answer lands under
  "body": T("Hi @contact.fields.name, pick a course"),   // OPTIONAL prompt
  "options": { "kind": "list", "value": [           // REQUIRED, 1..10
    { "id": "c1",                                   // REQUIRED
      "image":     I("https://…/english.png"),      // REQUIRED
      "image_alt": A("Adult English class"),        // OPTIONAL
      "label":     T("Spoken English") }            // REQUIRED
  ]}
}
```
- Renders: grid of tappable images with labels, single-select.
- `values`: `{ "<props.id>": "<selected option id>" }`
- Auto summary: the selected option's `label`.

### `glific/carousel`

```jsonc
{
  "id": "product",                                  // REQUIRED
  "body": T("Browse our courses"),                  // OPTIONAL
  "cards": { "kind": "list", "value": [             // REQUIRED, 1..10
    { "id": "p1",                                   // REQUIRED
      "image":       I("https://…/a.png"),          // REQUIRED
      "image_alt":   A("Students at desks"),        // OPTIONAL
      "title":       T("Course A"),                 // REQUIRED
      "description": T("Six weeks, evenings") }     // OPTIONAL
  ]}
}
```
- Renders: horizontally swipeable cards, each with a select action.
- `values`: `{ "<props.id>": "<selected card id>" }`
- Auto summary: the selected card's `title`.

### `glific/form`

```jsonc
{
  "id": "signup",                                   // OPTIONAL (fields carry their own ids)
  "body": T("Tell us about yourself"),              // OPTIONAL
  "fields": { "kind": "list", "value": [            // REQUIRED, 1..10
    { "id": "name",                                 // REQUIRED
      "label":       T("Your name"),                // REQUIRED
      "placeholder": T("e.g. Asha"),                // OPTIONAL
      "required":    { "kind": "boolean", "value": true } }   // OPTIONAL
  ]},
  "submit_label": T("Submit")                       // OPTIONAL, defaults to "Submit"
}
```
- Renders: inline labelled text fields + submit. v1 `input` primitive is **text only**.
- `values`: `{ "<field id>": "<string value>", … }` (every field, empty string if untouched)
- Auto summary: `"Your name: Asha"` pairs joined with `", "`, built from the **translated** labels
  the contact actually saw.

### Custom Block (any non-`glific` namespace)

Authored as raw JSON in the console. Envelope + typed-node validation only; no props schema, no
unknown-key rejection inside `props`. Rendered by the org's own registered renderer in the widget,
and by `FallbackCard` if none is registered. The console preview shows
**"This block has no preview"** rather than attempting a render.

### Summary rules (all blocks)

- The auto summary is exactly the value named above (option `label`, card `title`, the form's
  `label: value` pairs) — **no prefix text**.
- Form summaries skip fields the contact left empty; `values` still carries every field id, with
  an empty string for untouched fields.
- Clamped to 500 chars (§7); clamping must not split a UTF-16 surrogate pair.
- Never blank — a block that would produce an empty summary substitutes a non-empty stand-in,
  because `summary` becomes the message `body`. The stand-in wording is implementation-local.

## 7. Validation and limits

Applied at template save (console + backend) and on response receipt (backend):

| Rule | Value |
|------|-------|
| Outbound envelope size | ≤ 64 KB — measured on the **unwrapped, compactly encoded** envelope, so the typed wrapper does not count against the author |
| Stored typed payload size | ≤ 128 KB — separate cap, because typing roughly doubles the byte count |
| Inbound response size | ≤ 16 KB, compactly encoded |
| `summary` length | ≤ 500 chars |
| JSON depth | ≤ 10 on the **unwrapped** payload, where a scalar is depth 0 and each enclosing object/array adds 1 (`{"a":1}` is depth 1). Every implementation uses this same base. |
| `component` format | the DNS regex in §6 |
| `glific/*` names | must exist in the §6 catalog |
| typed nodes | `kind` in the §2.1 set; `value` matches the kind; no keys beyond `kind`/`value`/`translate` |
| ids | strings, unique within a block, not in the §5.1 reserved set |
| `glific/*` props | validated against the block schema at save |
| `glific/*` values | validated against the block's values shape on response |

Response acceptance additionally requires, in this order:
1. the socket's authenticated contact owns `message_id`;
2. that message is `type: :blocks` and **not yet answered**;
3. envelope validation above.

**A `:blocks` / `:blocks_response` message may only be created through the paths that validate
it** — the interactive-template send path and the socket response handler. Every other route into
message creation (`createMessage`, `createAndSendMessage`, `updateMessage`, and the group-message
mutations, whose `type` input accepts every `message_type_enum` value) must reject both types.
Absinthe yields the **atom** `:blocks`, not the string — guard on the atom.

Single-submit must be **atomic** — a guarded `update_all` that only marks unanswered messages and
acts on the returned row count, not a read-then-write check.

## 8. Unsupported channels

`Glific.Channels.ChannelCapability.supports?(channel, :blocks)` — `true` only for `"web"`.

When a blocks send targets an unsupported channel, send the **derived body (§9) as a plain text
message** and raise a `FlowContext.notification`. This must intercept BEFORE
`Communications.Message.@type_to_token`, which has no catch-all and would raise on `:blocks`.

Publish-time derivation in `flow.ex` warns when a flow containing a blocks node is reachable from
a non-web trigger.

## 9. The derived body (replaces `fallback`)

`fallback` is gone. Authors no longer write WhatsApp plain text for a web-only message. The
`messages.body` column is still populated, by **derivation from the typed payload**:

> Walk the payload in document order; concatenate the `value` of each `kind: "text"` node,
> joined with `" — "`, clamped to 500 chars. **`kind: "alt"` nodes are skipped** — see §2.1.
> **Text nodes whose value is empty or whitespace-only are dropped before the join**, so a blank
> authored field never produces a leading, trailing or doubled `" — "`.

The derivation itself returns `""` when a payload has no text nodes. Substituting a readable
placeholder is the *render site's* job (the floweditor canvas must never render blank), so that the
derivation stays byte-identical across all four repos.

Applied uniformly:

| Surface | Uses |
|---|---|
| `messages.body` | the derived body — feeds conversation-list preview, message search, exports |
| Staff Chat **thread** | renders the blocks UI (MUI renderer), plus the raw response JSON for Custom Blocks |
| Staff Chat **conversation list** | `body` (`ChatConversation.tsx:128` destructures `{ type, body }`) — this is why body must stay human-readable and must not be JSON |
| floweditor canvas | the same derivation, walking text nodes client-side |
| Unsupported-channel fallback (§8) | the derived body, sent as plain text |
| Custom Blocks with no text nodes | empty string — accepted |

**BigQuery.** `get_message_row/2` (`bigquery_worker.ex:1588`) exports `body` but not
`interactive_content`. v1 **adds `interactive_content` to the messages BigQuery table** (one schema
entry + one line in `get_message_row`) so analytics gets structured JSON in a JSON column, rather
than overloading the text column that the inbox renders. Note the raw response values already
reach BigQuery via `flow_results.results` (`bigquery_worker.ex:1223-1247`).

## 10. Translation

Auto-translation only in v1 (decision C).

- **What is translated:** every `kind: "text"` node in the stored payload. Nothing else — `image`,
  `url`, `number`, `boolean`, ids and structural keys are never sent to the translator.
- **How:** collect all text nodes with their paths, batch through `GoogleTranslate.translate/4`
  in a single call, reinsert **by path**. Never positional.
- **Where stored:** `interactive_templates.translations`, existing per-language-id shape, holding
  the full typed envelope with translated text nodes.
- **Manual CSV export/import** (`interactive_templates.ex:1367-1374`, `:1507-1508`) reassigns
  positionally (`[fallback | _rest] = translated_data`), which a typed tree cannot support.
  Blocks templates are **skipped** by the export — not an error, and the skip is reported in the
  export result so it is visible rather than silent.
- The auto summary (§6) is built from the **translated** labels, so a Hindi contact's summary —
  and therefore `messages.body` and the staff conversation-list preview — is in Hindi. This
  matches how every other inbound message body already behaves.

## 11. Staff console UI

- **No "Blocks" type dropdown entry, and no second component dropdown.** The existing interactive
  message type selector becomes a **grouped** select:

  ```
  WhatsApp    Reply buttons  ·  List  ·  Location request
  Web         Image panel  ·  Carousel  ·  Form  ·  Custom Block
  ```

  All four Web entries write `type = blocks`; they differ only in `interactive_content.component`.
  Adding a block later is a jsonb value, not a migration.
- The template **list** page derives its type label from `interactive_content.component`
  ("Carousel"), not from the enum.
- **Channel badges**, matching the flow form's treatment: derived, read-only, informational.
  `quick_reply` → `WhatsApp` `Web`; `blocks` → `Web`. Shown as a column in the list and a chip in
  the form. No new column, no new validation — pure presentation over `ChannelCapability`.
- The interactive-message form is **30% wider**; the preview panel takes the remainder with a
  minimum width.
- The draggable phone simulator is **replaced** by a web-widget preview for `blocks` types, using
  an MUI reimplementation of the widget's renderer. Best-effort fidelity. The same MUI renderer is
  reused in the staff Chat thread.

## 12. Known landmines (all must be handled)

In `lib/glific/templates/interactive_templates.ex`:

| Function | Problem for `blocks` |
|---|---|
| `generate_csv_data/1` (:1049) | `case` with **no catch-all** → `CaseClauseError`; must skip (§10) |
| `import_interactive_template/2` (:1286) | same, **no catch-all** → `CaseClauseError` |
| `translate_interactive_content/6` (:711) | 3 function heads, no fallback → `FunctionClauseError` |
| `calculate_total_length/1` (:211-260) | catch-all returns 0 → length guard silently bypassed |
| `check_options/1` (:180) | catch-all `:ok` → markdown guard silently skipped |
| `get_interactive_body/1` (:470) | catch-all `""` → must return the derived body |
| `formatted_data/2` (:534-537) | reads `interactive_content["fallback"]` for the body — now derives |
| `get_clean_interactive_content/3`, `clean_template_title/1`, `process_dynamic_interactive_content/3`, `trim_content/2` | passthrough catch-alls — verify passthrough is correct against a **typed** envelope, whose shape differs from every other interactive type |

Elsewhere:
- `Message.changeset`'s `validate_media/2` — rejects any type not in its whitelist with "message
  type should have a media id". Both new types must be whitelisted.
- `Communications.Message.@type_to_token` (`communications/message.ex:26`) — no catch-all.
- `Communications.WebMessage.@type_to_token` (`communications/web_message.ex:27`) — add
  `blocks: :send_blocks`.
- `WebMessage.do_receive_message/3` (:88-110) — anything not `[:text, :quick_reply, :list]` or
  `:location` falls into `receive_media`, which is wrong for a blocks response.
- jsonb writes: do **not** `Jason.encode!` before handing a map to Postgrex for a jsonb column —
  it stores the string as a jsonb scalar. Bit us once on `mark_answered/2`.
- `ChatConversations/MessageType` in the console — closed set naming enum members.
