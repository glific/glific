--- entry
heading: 1. Flow Execution Engine › 1.1 Flow Lifecycle: Draft → Published → Active → Executing › What makes a flow "active" vs "inactive"
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/
---

`flows.is_active` (boolean) on the `flows` table itself. When set to `false`:

- Any running `FlowContext` for that flow is terminated with `reason = "Flow terminated because it has been set to inactive."`.
- The flow will not be looked up from the keyword/trigger cache.

--- entry
heading: 1. Flow Execution Engine › 1.1 Flow Lifecycle: Draft → Published → Active → Executing › What happens when a flow is published (`Flow.publish`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/
---

1. **Guard**: If an already-published revision exists, raises
 `"Flow is already published with id #{flow_revision.id}, please archive it instead"`.
2. A new `flow_revision` row is created with `status: "published"` and incremented `version`.
3. The previous published row is switched to `status: "archived"`.
4. **Cache invalidation** is triggered so `Flows.get_cached_flow(org, {:flow_id, id, "published"})` reloads.
5.
 - `"published"` → `where fr.status == "published"`
 - `"draft"` → `where fr.revision_number == 0`

**DB signatures for "flow not publishing":**

- New published revision missing → check `flow_revisions WHERE flow_id = X ORDER BY id DESC` — must have a row with `status='published'` dated after the edit.
- Published but stale in cache → restart or touch the flow to force re-cache (24h TTL).

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Priority order inside `ConsumerFlow.move_forward/4`
---

```
1. continue_the_context?(context) -- active flow with ignore_keywords=true
2. draft keyword ("draft:XXX") -- simulator only
3. template keyword ("template:XXX") -- simulator only
4. start_new_contact_flow? -- contact tagged as brand-new + org_default_new_contact configured
5. flow_keyword? -- EXACT match in published keyword map
6. is_draft? -- draft flow keyword match
7. No match → Regex flow check → Periodic flows → no-op
```

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Keyword matching details
source: https://glific.github.io/docs/docs/Product%20Features/Others/Keywords/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Keywords/

- **Exact, case-insensitive, full-message match.** Keywords are stored downcased, message body is cleaned and downcased, then looked up with `Map.has_key?(state.flow_keywords["published"], body)`. **Word-in-sentence matching is NOT supported.**
 ```
 %{
 "published" => %{"hi" => flow_id, "help" => flow_id},
 "draft" => %{...},
 "template" => %{flow_name => flow_id},
 "org_default_new_contact" => flow_id,
 "org_default_optin" => flow_id,
 "outofoffice" => flow_id,
 "defaultflow" => flow_id
 }
 ```

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Opt-out → opt-in flow interception
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

If `contact.optout_time` is not null AND contact is not already in an opt-in flow → immediately start `org_default_optin`, marking all other contexts complete.

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Periodic flows
---

If no active context AND no keyword AND no regex match:
Evaluated in order: `monthly → weekly → {monday..sunday} → daily → outofoffice` (or `defaultflow` if out-of-office disabled). Unless `run_flow_each_time=true`, a periodic flow only runs once per period (tracked via `Flows.flow_activated(flow_id, contact_id, since)`).

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Manual & API-triggered flows
---

- Validates contact belongs to caller's org.
- Calls `Flows.get_cached_flow(org_id, {:flow_id, flow_id, "published"})`.
- Calls `Broadcast.broadcast_contacts(flow, [contact], default_results)`.
- Silently no-ops if `flow.is_active == false`.

Other mutations: `startWaGroupFlow`, `startGroupFlow`, `resumeContactFlow`.

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Scheduled trigger flows
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

See [Section 7](#7-triggers--scheduling). Every minute `Triggers.execute_triggers/1` runs and calls `Flows.start_group_flow` / `start_wa_group_flow` for matured triggers.

--- entry
heading: 1. Flow Execution Engine › 1.2 How a Flow Gets Triggered — Every Path › Priority order recap when multiple flows could match
---

1. Currently-active flow with `ignore_keywords=true` — beats everything.
2. Opt-out interception (if `optout_time` set).
3. Draft/template simulator overrides.
4. New-contact default flow (only for newly-tagged contacts).
5. Keyword match (published, then draft).
6. Regex match.
7. Periodic flows (monthly → weekly → daily → outofoffice).

--- entry
section: 1.3
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field
---

Table `flow_contexts`.

| Field | Set where | Meaning |
| --- | --- | --- |
| `node_uuid` | `seed_context:700` | Current node the flow is at |
| `flow_uuid` | `seed_context:701` | Flow uuid (redundant with flow_id, used for uuid_map lookup) |
| `flow_id` | `seed_context:704` | FK to `flows` |
| `contact_id` | `seed_context:697` | FK to `contacts` (nil for wa_group flows) |
| `wa_group_id` | `seed_wa_group_context:739` | Set for WhatsApp-group flows instead of contact_id |
| `parent_id` | `seed_context:682` | Points to parent FlowContext for sub-flows |
| `uuid_map` | `seed_context:707` | Copy of flow.uuid_map — lookup table for nodes/exits |
| `results` | `update_results/seed_context:719` | Map of `@results.xxx` variables collected so far |
| `status` | `seed_context:702` | `"published"` or `"draft"` |
| `wakeup_at` | `Wait.execute:105` | Future datetime for `wait_for_time` nodes |
| `is_background_flow` | default false; set true for periodic/broadcast | Background flows aren't killed when new flows start |
| `is_killed` | See §1.4 | Terminated context; `reason` populated alongside |
| `is_await_result` | `ContactAction.send_message` | True when waiting for contact response |
| `delay` | `seed_context:708` / `ContactAction:411` | Incremented per outbound message to stagger sends |
| `reason` | Set only with `is_killed=true` | Human-readable termination reason |
| `completed_at` | `reset_one_context:258, reset_context:313` | Flow finished normally |
| `message_broadcast_id` | `seed_context:699` | Set when flow started from a broadcast |

--- entry
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field › Init flow
---

1. Reject empty flow.
2. If `parent_id` is nil (top-level): call `mark_flows_complete(contact_id, flow.is_background, source: "init_context")` — kills prior non-background flows.
3. `seed_context/2` — inserts DB row.
4. `load_context/2` — loads the start node from uuid_map.
5. `execute([])` — begins execution.

--- entry
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field › Step-by-step node execution
---

- `Node.execute` checks infinite-loop guards.
- Routes to actions/router:
 - `wait_for_time` / `wait_for_result` → sets `wakeup_at` and returns `{:wait, ctx, []}`.
 - Actions + Router → run all actions, then router with message.
 - Actions only → sequential execution; `{:ok, ctx, messages}` or `{:wait,...}`.
 - Router only → switch by case; route to matching exit.
- Exits execute via `Exit.execute`: if `destination_node_uuid` is nil → `FlowContext.reset_context` (flow ends). Otherwise load next node and recurse.

--- entry
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field › Wait nodes
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20time/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20time/

- **wait_for_time**: `wakeup_at = DateTime.utc_now + wait_seconds`. Flow pauses; `Periodic.wakeup_flows` (batch 500, `wake_up_flow_limit`) picks up contexts where `wakeup_at < now AND completed_at IS NULL`.
- **wait_for_response**: Blocks in `Router.execute`. No wakeup_at; next inbound message resumes.

--- entry
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field › Sub-flows
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Enter%20another%20flow/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Enter%20another%20flow/

- New FlowContext with `parent_id = current_id`.
- "parent" and "child" keys stripped from results (lines 287-290).
- On child termination (`reset_context:306-346`):
 - Loads parent if still active (not completed/killed).
 - Merges child results into `parent.results["child"]`.
 - Calls `step_forward` with synthetic message `"completed"`.
- **If parent is dead when child finishes, the chain ends silently** — this is a common cause of "flow stops mid-sub-flow".

--- entry
heading: 1. Flow Execution Engine › 1.3 FlowContext — Every Field › Background flows (`is_background_flow = true`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Background%20Flows/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Background%20Flows/

- Set by `Periodic.init_common_flow` and some broadcast operations.
- `mark_flows_complete(contact_id, is_background=true)` is a no-op — so starting a new top-level flow does NOT kill background flows.
- When a background flow wakes up, it kills all _other_ background flows for the same contact.

--- entry
section: 1.4
heading: 1. Flow Execution Engine › 1.4 Why Flows Get Killed (`is_killed = true`)
---

Every code path that sets `is_killed=true`. The `reason` column is populated in the same write.

| Call site | Reason string | When |
| --- | --- | --- |
| `reset_all_contexts` | `event_label` from `get_event_label/1` | Catch-all error handler |
| `reset_one_context` | `"Flow terminated abruptly"` / `"Child Flow Completed"` / `"Flow Completed"` | Normal completion paths (these set `is_killed=true` when marking complete, not on error) |
| `mark_wa_flows_complete` | `"Flow waked up, marking all other flows as completed"` | WA group background flow wakeup kills parallel non-background flows |
| `mark_flows_complete(flow)` | `"Flow terminated because it has been set to inactive."` | User set `flows.is_active=false` |
| `mark_flows_complete(contact_id, ...)` | `"Last Active flow is killed as new flow has started"` (`:646`) / `"Last Active flow is terminated"` (`:643`) / `"Flow waked up, marking all other flows as completed"` (`:649`) | New top-level flow started for contact / explicit terminate / wakeup |

**Diagnostic query for a killed flow:**

--- entry
section: 1.5
heading: 1. Flow Execution Engine › 1.5 Why Flows FAIL Silently (no error, just stops)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/

Silent-stop signatures in DB:

- `is_killed = false, completed_at = null` and `wakeup_at IS NULL` for long time → stuck awaiting response that never came.
- Node returned `:wait` but message never matches any `case` in the router → contact stuck mid-flow.
- Session window expired between messages (24h) → contact can't receive next outbound; flow appears to halt.
- Contact opted out mid-flow → next send fails at `can_send_message_to?` gate.
- Parent sub-flow dead → child completes but chain doesn't continue.

--- entry
section: 1.6
heading: 1. Flow Execution Engine › 1.6 Flow Error Notifications
source: https://glific.github.io/docs/docs/Product%20Features/Notifications/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

Category `"Flow"`:

| Source | Message | Entity |
| --- | --- | --- |
| `notification/3` | Variable (passed in) | `{flow_id, flow_uuid, contact_id, parent_id, node_uuid}` |
| | `"Flow execution failed due to invalid regular expression"` | `{flow_uuid, node_uuid, organization_id}` |
| | `"Template expression is null in the flow"` | `{template_type}` |
| | `"Template not found, skipping templating"` | `{template_type}` |
| | `"Error from Google Sheets: #{error}"` | `{spreadsheet_id, contact_id}` |

Also raised by flow execution:

- `"Infinite loop detected, body: #{body}. Resetting flows"`.
- `"Infinite loop detected, body: #{body}. Aborting flow."`.
- `"Could not send message to contact: Empty media URL"`.
- `"Error sending message, resetting context: #{error}"`.

**Trace path: notification → flow → node → contact**

Entity JSON on a flow notification contains `flow_uuid` and `node_uuid` (plus `contact_id`). Join:

--- entry
section: 1.7
heading: 1. Flow Execution Engine › 1.7 Message Variable Parsing (`@contact.xxx`, `@results.xxx`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Flow%20variables%20vs%20Contact%20variables/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Flow%20variables%20vs%20Contact%20variables/

Regex patterns (lines 14-79) handle up to 4 levels of dotted access.

Bindings map shape (MessageVarParser `bound/2`):

```elixir
%{
 "contact" => %{
 "fields" => %{shortcode => %{"value" => v, "label" => l, "type" => t}},
 "language" => %{"id" => id, "label" => label},
 "in_groups" => [group_ids],
 "name" => name
 },
 "results" => %{key => value},
 "staff" => %{...},
 "global" => %{...},
 "calendar" => %{...}
}
```

- `@contact.fields.{shortcode}` → `fields[shortcode]["value"]`
- `@contact.language` → `fields["language"]["label"]`
- `@results.{node_name}.{key}` → `results[node_name][key]`

**If a referenced field doesn't exist, the raw `@...` string remains** (not substituted). This is visible as the literal `@contact.fields.age` appearing in sent messages.

--- entry
section: 1.8
heading: 1. Flow Execution Engine › 1.8 Common Flow Issues — DB Signatures
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/

| Symptom | Check |
| --- | --- |
| Flow not triggering | `flows.is_active=true`? Latest `flow_revisions.status='published'` exists? `contact.optin_status=true`? Keyword in `flow_keywords` cache? Another flow active (`flow_contexts` where `completed_at IS NULL AND is_killed=false`)? |
| Flow stops at node X | `flow_contexts.node_uuid` == that node + `notifications` category='Flow' with matching `entity->>'node_uuid'` |
| Works in simulator/preview but not real | Simulator bypasses `can_send_message_to?` session check; real sends blocked by `bsp_status` gate |
| Flow triggers but does nothing | Node has no exits with destinations, or all router cases fail match. Check `flow_revisions.definition` for the node uuid |

---

--- entry
section: 2.1
heading: 2. Message Delivery Pipeline › 2.1 Message status & bsp_status
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Message%20Events/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Message%20Events/


```elixir
@message_status_const [
:sent,:delivered,:enqueued,:error,:read,:received,
:contact_opt_out,:reached,:seen,:played,:deleted
]
```

Both `messages.status` and `messages.bsp_status` use this enum.

| Value | Meaning |
| --- | --- |
| `:sent` | Accepted by provider API (Glific-side status) / BSP confirmed send (bsp_status) |
| `:delivered` | BSP confirms recipient device received |
| `:read` | BSP confirms recipient read (blue ticks) |
| `:received` | Inbound message |
| `:contact_opt_out` | Blocked because contact opted out |

--- entry
section: 2.2
heading: 2. Message Delivery Pipeline › 2.2 Message lifecycle with column updates
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Message%20Events/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Message%20Events/

Creation: `status::enqueued`, `bsp_status: nil`.


```
bsp_message_id = provider_id
bsp_status =:enqueued
status =:sent
sent_at = now
```


- `/gupshup/message-event/enqueued` → `bsp_status =:enqueued`
- `/.../sent` → `bsp_status =:sent`
- `/.../delivered` → `bsp_status =:delivered`
- `/.../read` → `bsp_status =:read`
- `/.../failed` → `bsp_status =:error`, `errors` populated


```
status =:sent (still marked as attempted)
bsp_status =:error
errors = %{message: body} -- or preserved if already a map
```

**Special error codes processed:**

- `1002` "Number does not exist" → `Contacts.number_does_not_exist/2` marks contact invalid.
- `471` Rate-limit → `Partners.suspend_organization/1` (full-day suspension).
- `1003` Insufficient balance → `Partners.suspend_organization(org, 3)` (3-day suspension).

--- entry
section: 2.3
heading: 2. Message Delivery Pipeline › 2.3 Session vs HSM — the 24h Window
source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

Gate function: `Contacts.can_send_message_to?/2,3`.

**HSM (template) send requirements (`:636-660`):**

```elixir
contact.status ==:valid
contact.bsp_status in [:session_and_hsm,:hsm]
contact.optin_time != nil
organization.suspended == false
```

Errors:

- `"Contact status is not valid."`
- `"Cannot send hsm message to contact, invalid BSP status."`
- `"Cannot send hsm message to contact, not opted in."`
- `"Cannot send hsm message...organization is in suspended state"`

**Session send requirements (`:665-680`):**

```elixir
contact.status ==:valid
contact.bsp_status in [:session_and_hsm,:session]
```

Error (session expired): `"Sorry! 24 hrs window closed. Your message cannot be sent at this time."`

**24h window logic**: The BSP (WhatsApp) owns the actual window. Glific encodes it via `bsp_status`:

- `:session` / `:session_and_hsm` → session sends allowed (i.e., there's been an inbound within 24h).
- When 24h elapse since `last_message_at`, a scheduled job downgrades `bsp_status` to `:none` (if opted out) or `:hsm` (if opted in).

Explicit check in optin flow path: `Glific.in_past_time(contact.last_message_at,:hours, 24)`.

**How Glific decides HSM vs session**: The caller (flow action, broadcast, API) sets the `is_hsm: true/false` flag when creating the message. `check_for_hsm_message/1` routes to HSM path. There is no auto-fallback from session to HSM — if you try to send session content outside window, it fails.

--- entry
section: 2.4
heading: 2. Message Delivery Pipeline › 2.4 Send Pipeline
---

```
Messages.create_and_send_message(attrs)
 → check_for_interactive → check_for_hsm_message
 → Messages.create_message (insert row, status=:enqueued)
 → Communications.Message.send_message
 → Communications.provider_handler(org) = Gupshup.Message | Maytapi.Message
 → send_text/send_image/...
```


- Queue: `:gupshup` (or `:gupshup_high_tps`, or `:wa`)
- `max_attempts: 2`

**Worker execution:**

1. Rate-limit check: `ExRated.check_rate(org.shortcode, 1000, org.services["bsp"].keys["bsp_limit"])`.
 - On exceed: sleep 50ms, return `{:snooze, 1}` (retry in 1s).
2. Simulator contact → mock success.
3. Call provider API (`ApiClient.send_message` or `PartnerAPI.send_template`).
4. Dispatch by status:
 - 200-299 → `handle_success_response`
 - 400-499 → `handle_error_response`, return `:ok` (no retry)
 - 5xx → `handle_error_response`, often `{:snooze, N}`

Maytapi default rate limit: `@default_bsp_limit = 30 req/s` (`maytapi/wa_worker.ex`).

--- entry
section: 2.5
heading: 2. Message Delivery Pipeline › 2.5 BSP Callback Processing
---

```elixir
bsp_message_id = get_in(params, ["payload", "gsId"]) || get_in(params, ["payload", "id"])
Communications.Message.update_bsp_status(bsp_message_id, status, params)
```


```elixir
Repo.update_all(
 from(m in Message, where: m.bsp_message_id == ^bsp_message_id),
 set: [bsp_status: status, updated_at: DateTime.utc_now]
)
```

For `:error`, also sets `errors` and runs `process_errors/2` (org/contact disablement on specific codes).

--- entry
section: 2.6
heading: 2. Message Delivery Pipeline › 2.6 Media & Limits
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20a%20message/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20a%20message/

- Gupshup text/caption max: **4096 chars**.
- Maytapi text/caption max: **6000 chars**.
- Supported types: `audio, contact, document, hsm, image, location, list, quick_reply, text, video, sticker, location_request_message, poll, whatsapp_form_response`.
- Media URLs stored on `messages_media`: `source_url`, `url`, `gcs_url`, `gcs_error`.

--- entry
section: 2.7
heading: 2. Message Delivery Pipeline › 2.7 Common Message Failures — DB Signatures
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

| Symptom | DB check |
| --- | --- |
| `"Sorry! 24 hrs window closed..."` notification | `contact.bsp_status NOT IN (:session, :session_and_hsm)` |
| HSM rejected at send | `contact.optin_time IS NULL` or `contact.bsp_status NOT IN (:hsm, :session_and_hsm)` |
| Template not sent | `session_templates.status != 'APPROVED'` OR parameter count mismatch |
| Media failed | `messages_media.gcs_error` populated; URL expired/invalid |
| Sent but not delivered | `bsp_status=:sent`, never advances — recipient phone off, blocked Glific, or number invalid at WA |

---

--- entry
section: 3.1
heading: 3. Contact Management › 3.1 Contact States
---

**ContactStatus (`contacts.status`)** — line 14:

```
[:blocked,:failed,:invalid,:processing,:valid]
```

- `:valid` — normal contact, can receive messages.
- `:invalid` — number doesn't exist on WA (set after error 1002) or opted out.
- `:blocked` — manually blocked in Glific.
- `:failed` — send repeatedly failed.
- `:processing` — transient (contact import in progress).

**ContactProviderStatus (`contacts.bsp_status`)** — line 17:

```
[:none,:session,:session_and_hsm,:hsm]
```

- `:none` — can send nothing (no opt-in AND no active session).
- `:session` — can send session messages only (has recent inbound, not opted in).
- `:hsm` — can send templates only (opted in, but session is cold).
- `:session_and_hsm` — both allowed (opted in AND active session).

--- entry
heading: 3. Contact Management › 3.2 Opt-in / Opt-out End to End › Opt-in
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

Triggers:

- Gupshup webhook `POST /gupshup/user-event/opted-in` → `UserEventController.opted_in` → `Contacts.contact_opted_in(phone, org, time, method: "BSP")`.
- Flow action `optin_contact` → same function with `method: "Glific Flows"`.
- API import → `method: "Import"`.
- GraphQL mutation `optinContact`.

Column updates on opt-in:

```
optin_time = utc_now
optin_status = true
optin_method = method
optin_message_id = message_id | nil
optout_time = nil
status =:valid
bsp_status =:hsm (via set_session_status(contact,:hsm))
```

Dedup: If contact already opted-in and method is "BSP", returns without re-writing (lines 551-559).

--- entry
heading: 3. Contact Management › 3.2 Opt-in / Opt-out End to End › Opt-out
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

Triggers:

- Gupshup webhook `POST /gupshup/user-event/opted-out` → `contact_opted_out(phone, org, time)`.
- Provider error 1002 "Number does not exist" → `number_does_not_exist/2` (line 614).
- Provider response "Not on WhatsApp".
- Flow action to opt-out manually.
- **No hardcoded STOP keyword handler in the contacts module.** Opt-out is event-driven (BSP webhook, provider error, flow action), NOT keyword-driven in core. Some clients may build STOP into a flow.

Column updates on opt-out:

```
optout_time = utc_now
optout_method = method -- "Number does not exist" / "Glific Flows" / etc.
optin_time = nil
optin_status = false
optin_method = nil
optin_message_id = nil
status =:invalid
bsp_status =:none
```

History row inserted into `contact_histories` with event `:contact_opted_out`.

--- entry
section: 3.3
heading: 3. Contact Management › 3.3 Session Window Fields
---

- **`last_message_at`**: Updated when any inbound or outbound message is created (via `Messages` context). **This is what the 24h window is measured from.** Check: `now - last_message_at < 24h`.
- **`last_communication_at`**: Set on contact creation; broader meaning. Not checked in message-gate logic.

--- entry
section: 3.4
heading: 3. Contact Management › 3.4 Contact Fields (JSONB `contacts.fields`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/List%20of%20Custom%20Contact%20Variables%20created%20in%20Flows/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/List%20of%20Custom%20Contact%20Variables%20created%20in%20Flows/

`add_contact_field/5` writes:

```elixir
field_key => %{
 value: value,
 label: label,
 type: type,
 inserted_at: DateTime.utc_now
}
```

If the shortcode isn't in the `contacts_fields` metadata table, `maybe_create_contact_field/1` auto-creates it.

Allowed field types: `[:text,:integer,:number,:boolean,:date]`.

Read in flows: `@contact.fields.{shortcode}` → resolved by MessageVarParser.

**If a flow references a field that doesn't exist yet**: the `@contact.fields.xxx` string is NOT substituted — the raw placeholder is sent or compared, typically causing router case mismatches.

--- entry
section: 3.5
heading: 3. Contact Management › 3.5 Common Contact Issues
---

| Symptom | Check |
| --- | --- |
| Not receiving messages | `optin_status`, `bsp_status`, `status`, and `last_message_at` (session) |
| Shows as invalid | `status=:invalid` → `optout_time` set, or error 1002 history, or provider rejection |
| Opted out unexpectedly | Check `contact_histories` for `:contact_opted_out` event and `optout_method` |
| Field not resolving in flow | `contacts.fields->>'xxx'` missing → flow wrote label but never value, or flow path didn't reach the write |

---

--- entry
section: 4.2
heading: 4. Google Sheets Integration › 4.2 `sheet_data` Table
---

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int | PK |
| `key` | string | Unique per (sheet_id, organization_id); from sheet's `"key"` column |
| `sheet_id` | int | FK |
| `organization_id` | int | FK |
| `last_synced_at` | utc_datetime_usec | |

--- entry
section: 4.3
heading: 4. Google Sheets Integration › 4.3 Sync Mechanism
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

**What triggers a sync:**

- On create/update.
- Daily cron via `Sheets.sync_organization_sheets/0` (`minute_worker.ex` daily task) — picks sheets where `auto_sync=true AND type IN ("ALL","READ") AND is_active=true`.
- Flow action `link_google_sheet` of READ type.

**Credentials**: Service-account JSON stored at `organization.services["google_sheets"].secrets["service_account"]`. Goth obtains token with scopes for Drive and Spreadsheets.

**Read flow:**

1. Parse URL → spreadsheet_id + gid.
2. `Spreadsheets.sheets_spreadsheets_values_get` with range `'SheetName'!A:ZZ`.
3. Falls back to CSV export if no credentials.
4. First row = headers (trimmed).
5. Validate headers: no empty, no duplicates → `"Repeated or missing headers"`.
6. Zip rows to maps; keys are lowercased, spaces → underscores.
7. Delete old `sheet_data` rows; bulk insert new ones with `on_conflict::nothing`.
8. Update `sheets.last_synced_at`, `sheet_data_count`, `sync_status`.

**Unique row key**: Looks for a column named `"key"` in the CSV. Rows without a `key` column can still be stored but not looked up by flows.

--- entry
section: 4.4
heading: 4. Google Sheets Integration › 4.4 Exact Error Strings
source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/
---

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

| Scenario | String | Location |
| --- | --- | --- |
| Empty CSV / no rows | `"Unknown error or empty content"` | |
| Duplicate/empty headers | `"Repeated or missing headers"` | , |
| No credentials | `"Google API is not active"` then `"Please add the credentials for google sheet from the settings menu"` | |
| Write denied (HTTP 403) | `"No edit access to the Google Sheet. Please ensure the service account has editor permissions."` | |
| Sheet not found (HTTP 404) | `"Google Sheet not found. Please ensure the URL is correct and the service account has access."` | |
| Read denied (HTTP 403) | `"No read access to the Google Sheet. Please ensure the service account has viewer permissions."` | |
| Not public & no creds | `"Please double-check the URL and make sure the sharing access for the sheet is at least set to 'Anyone with the link' can view."` | |
| Bad service-account JSON | `"Invalid Service Account JSON"` | |
| Token fetch failed | `"Error fetching token with Service Account JSON"` | |
| Tab deleted/renamed | `"Sheet with gid #{gid} not found"` | |
| CSV parse failure | `"Sheet is not accessible or not found."` | |
| Generic sync fail notification | `"Google sheet sync failed"` (category `"Google sheets"`, severity warning) | |
| Write action error | `"Error from Google Sheets: #{error}"` (category `"Flow"`, entity has spreadsheet_id + contact_id) | |

--- entry
section: 4.5
heading: 4. Google Sheets Integration › 4.5 "Link Google Sheet" Flow Action
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Link%20Google%20Sheets/

Type: `"link_google_sheet"`. Required fields: `sheet_id`, `result_name`. Optional: `action_type` (default `READ`), `row`, `row_data`.


**WRITE action:**

1. Parse spreadsheet_id from `action.url`.
2. Substitute `@contact.*`, `@results.*` in row_data via MessageVarParser.
3. Call `GoogleSheets.insert_row` → Sheets API `values_append` with `valueInputOption: "USER_ENTERED"`.
4. Success → flow advances via `"Success"` synthetic message.
5. Failure → notification created, advances via `"Failure"`.


- 4xx → `"Invalid request, please check the spreadsheet id"`
- 5xx → `"Failed to write to the spreadsheet, please retry"`
- Other → `"Unknown error occurred, please reach out to support"`

**READ action:**

1. Look up `sheet_data` by `(sheet_id, key)` where `key` comes from substituted `action.row`.
2. Found → populate `context.results[result_name] = row_data`, advance via `"Success"`.
3. Not found → advance via `"Failure"`.

--- entry
section: 4.6
heading: 4. Google Sheets Integration › 4.6 Common Sheet Failures Map
source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/
---

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

| User symptom | Likely cause | DB/UI signal |
| --- | --- | --- |
| "Sync failed" notification | Google API error | `sheets.failure_reason`, `sync_status=:failed` |
| "Unknown error or empty content" | Sheet tab has no rows under headers; or tab name mismatch | First sheet empty; `sheet_data_count=0` |
| "Repeated or missing headers" | Two columns with same header, or a header cell is blank | Fix the header row |
| "No read access..." | Service account not shared on the sheet | Share with `organization.services["google_sheets"]` client email |
| Auth errors | Credential JSON corrupt or rotated | `"Invalid Service Account JSON"` or `"Error fetching token..."` |
| Sheet tab renamed/deleted | gid in URL no longer resolves | `"Sheet with gid X not found"` |
| Rate-limited by Google | 429 surfaces as generic write error, message from Google | `failure_reason` contains Google error body |
| "Google sheet media validation failed" notification | The sheet synced fine. A cell holds a media URL (image/video/audio/document) Glific could not use — link unreachable, file type not supported, or file too large | Open the notification details and read `media_validation_warnings`: it names each bad cell value and the reason. Only those media links are affected; the rest of the sync succeeded |
| "Unable to parse range" notification | A flow tried to write to a sheet tab or range that no longer exists — tab renamed or deleted. Filed under category Flow, not Google sheets | Match the range in the flow's Add Row node to the tab name in the sheet |

---

--- entry
section: 5.1
heading: 5. Templates (HSM) › 5.1 Lifecycle & Statuses
source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

`session_templates.status` values (`templates/session_templates.ex`):

- `"APPROVED"` — usable; `is_active=true`, `is_hsm=true`.
- `"PENDING"` — awaiting Meta/WA decision.
- `"REJECTED"` — denied; `reason` populated.
- `"FAILED"` — submission or sync error; `reason` populated.
- `"SANDBOX_REQUESTED"` — sandbox state, treated as active (line 512).

Key fields:

- `shortcode` — internal identifier, `[a-z0-9_]` only.
- `uuid` — BSP template id.
- `bsp_id` — provider template id (nil until submitted).
- `number_parameters` — derived from regex count.
- `body`, `is_hsm`, `is_active`, `quality`, `reason`, `language_id`, `category`.

--- entry
section: 5.2
heading: 5. Templates (HSM) › 5.2 Sync with Meta/WhatsApp
---

`TemplateWorker` (`template_worker.ex`, queue `:default`, `max_attempts: 2`):

- `make_job/2` — bulk CSV apply.
- `create_hsm_sync_job/1` — unique job (5-min dedup).
- `perform/1` (lines 50-92):
 - `Templates.create_session_template` for new entries.
 - `Templates.sync_hsms_from_bsp` fetches from Gupshup PartnerAPI.
 - Notifications on completion (info) or failure (critical).

Gupshup integration (`providers/gupshup/template.ex`):

- `submit_for_approval/1` (line 46-75) → stores `bsp_id`, `status`, `is_active`.
- `update_hsms/2` → `do_insert_hsm/3` (line 496-551) writes `template["status"]` directly.
- HSM sync runs hourly via MinuteWorker's `update_hsms` task.

Notifications for template state changes (`templates.ex`):

- Line 658 — `"Template {shortcode} has been approved"` (info).
- Line 675 — `"Template {shortcode} has been rejected"` (info, entity has `reason`).
- Line 692 — `"Template {shortcode} has been failed"` (info, entity has `reason`).

--- entry
section: 5.3
heading: 5. Templates (HSM) › 5.3 Rejection Causes
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

- Shortcode invalid chars (only `[a-z0-9_]`).
- Button text contains variables, newlines, emojis, or formatting — line 186.
- Total length > 1024 chars (body + buttons + footer) — line 247.
- Missing body for text templates — line 147-149.
- Meta policy violations — message in `reason` comes from BSP response.

--- entry
section: 5.4
heading: 5. Templates (HSM) › 5.4 Parameters
source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/

Count regex: `Regex.split(~r/{{.}}/, template["data"]) |> length |> - 1`.
Validation pattern: `{{([1-9]|[1-9][0-9])}}` — 1-99 params supported.

**Parameter mismatch at send time → message fails with BSP error; `messages.errors` contains the provider error.** Common cause of "template approved but can't send".

--- entry
section: 5.5
heading: 5. Templates (HSM) › 5.5 Common Template Issues
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

| Symptom | Check |
| --- | --- |
| Approved but not sendable | Parameter count mismatch; `contact.optin_time` null; org suspended |
| Not visible in UI | `is_active=false`; `status` null; sync hasn't run (`update_hsms` hourly) |
| Rejected | `session_templates.reason` field has Meta's reason |

---

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › Default Payload (exact)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

```json
{
 "contact": {
 "id": 42,
 "name": "Asha",
 "phone": "919876543210",
 "fields": {
 "age": {
 "value": "25",
 "label": "Age",
 "type": "text",
 "inserted_at": "2026-04-15T10:00:00Z"
 },
 "language": { "id": 1, "label": "English" }
 }
 },
 "wa_group": {
 "id": null,
 "label": null,
 "wa_managed_phone_id": null
 },
 "results": {
 "survey_q1": "answer_a",
 "quiz_score": 7
 },
 "flow": {
 "name": "Onboarding Flow",
 "id": 12
 },
 "organization_id": 1
}
```

Any custom body fields the user configures are merged in after variable substitution via `MessageVarParser.parse_map/2`.

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › HTTP Method, Headers, Signature
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

- Method: **GET**, **POST**, or **FUNCTION** — the flow editor offers only these three (`METHOD_OPTIONS` in the floweditor; PUT / DELETE / HEAD / PATCH are commented out). `FUNCTION` is a local dispatch, not an HTTP call (§6C).
- Headers: `X-Glific-Signature` always added; user-configured headers merged in.
- Signature format: `X-Glific-Signature: t=<unix_seconds>,v1=<hmac_sha256_hex>`.
 ```elixir
 secret = organization.signature_phrase || "This is a dummy secret"
 signed_payload = "#{timestamp}.#{body}"
 hmac =:crypto.mac(:hmac,:sha256, secret, signed_payload)
 Base.encode16(hmac, case::lower)
 ```
- Secret: `organizations.signature_phrase` column — falls back to `"This is a dummy secret"` if empty. **Customers must verify using this value.**

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › Timeout & Retry
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/

- GET: 10s (`Tesla.get(..., opts: [adapter: [recv_timeout: 10_000]])`, ).
- POST: no explicit timeout — Tesla/Hackney default.
- **Async webhook park:** if the node body carries a `wait_time` key, `Action.webhook_wait_time/1` parses it and `Action.validate/3` caps it at **300 s** (`@max_webhook_wait_time`). A larger value publishes with a Warning and the cap is applied anyway.
 - Queue: `:webhook`
 - `max_attempts: 2` (= 1 initial + 1 retry)
 - Dedup window: 60s by `(context_id, url, action_id)`
 - Default exponential backoff
- **Not user-configurable** at flow design time.

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › Response Handling
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

- Success: HTTP 200-299 AND JSON-parseable body.
- Non-JSON → logged: `"Could not decode message body: <body>"`, result = nil, flow takes "Failure" exit.
- Non-2xx → logged: `"Did not return a 200..299 status code"`, result = nil, "Failure" exit.
- Response parsed into `@results.<result_name>`. For node named `survey`, access keys as `@results.survey.<key>`.
- Arrays indexed by integer: `[a, b] → {0: a, 1: b}`.
- No explicit max size enforced — Tesla/HTTP-client defaults apply.

**Flat vs nested**: Flat `{key: value}` maps cleanly to `@results.survey.key`. Nested objects (`{user: {name: "x"}}`) are stored as-is, so access becomes `@results.survey.user.name` — works but common source of confusion.

**Exits:** the node has exactly two, **Success** and **Failure** (`ServiceCallExitNames` in the flow editor). There is no four-way client-error / server-error / network-error split — that is upstream RapidPro, not Glific.

**Deprecated URLs:** `Action.validate/3` rejects three webhook names outright at publish time — `speech_to_text_with_bhasini`, `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini` — with a Critical error naming the replacement node (§14).

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › Variable Substitution in URL & Body
---

```
header = MessageVarParser.parse_map(action.headers, fields)
url = MessageVarParser.parse(action.url, fields)
```

Supports `@contact.*`, `@results.*`, `@flow.*`, `@wa_group.*`.

--- entry
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node) › webhook_logs table
---

| Column | Meaning |
| --- | --- |
| `url` | Requested URL |
| `method` | `GET` / `POST` / `function` (downcased) |
| `request_headers` | Map sent (includes signature) |
| `request_json` | Request body |
| `response_json` | Parsed response (null if non-JSON) |
| `status_code` | HTTP status; `400` used as sentinel for local errors |
| `error` | Error message when request failed |
| `flow_id`, `contact_id`, `organization_id`, `wa_group_id`, `flow_context_id` | FKs |

**Primary debugging table for webhook issues.** Every outgoing webhook creates a row.

--- entry
heading: 6. Webhooks — Complete Reference › 6C. "Call a Function" Node
---

```elixir
defp do_action("function", function, fields, headers) do
 {:ok,:function, dispatch_function(function, fields, headers)}
end

defp dispatch_function(function, fields, headers) do
 case Registry.lookup(function) do
 module when not is_nil(module) and is_atom(module) ->
 Dispatcher.dispatch(function, fields, headers)

 _ ->
 function |> Glific.Clients.webhook(fields) |> wrap_legacy_result
 end
end
```

Two tiers: names in `Glific.Flows.Webhooks.Registry` go through `Dispatcher.dispatch/3` (typed result, instrumented); anything else falls back to the per-org client modules via `Glific.Clients.webhook/2`, whose bare map is wrapped so routing and logging stay uniform.

--- entry
heading: 6. Webhooks — Complete Reference › 6C. "Call a Function" Node › Built-in functions — the complete registry
---

These eleven names are the whole list. Any other name with method `FUNCTION` falls through to the per-org client tier, and if that has no implementation the node fails.

| Name | Module | Mode |
| --- | --- | --- |
| `parse_via_chat_gpt` | `Webhooks.ParseViaChatGpt` | sync |
| `parse_via_gpt_vision` | `Webhooks.ParseViaGptVision` | sync |
| `speech_to_text` | `Webhooks.SpeechToText` | async (Kaapi callback) |
| `text_to_speech` | `Webhooks.TextToSpeech` | async (Kaapi callback) |
| `filesearch-gpt` | `Webhooks.FilesearchGpt` | async (Kaapi callback) |
| `voice-filesearch-gpt` | `Webhooks.VoiceFilesearchGpt` | async (Kaapi callback) |
| `geolocation` | `Webhooks.Geolocation` | sync |
| `send_wa_group_poll` | `Webhooks.SendWaGroupPoll` | sync |
| `create_certificate` | `Webhooks.CreateCertificate` | sync — Google Slides → image on GCS |
| `get_buttons` | `Webhooks.GetButtons` | sync, pure-local |
| `check_response` | `Webhooks.CheckResponse` | sync, pure-local |

**Not in the registry** (they were, or are commonly assumed to be, but are not):

- `speech_to_text_with_bhasini`, `text_to_speech_with_bhasini`, `nmt_tts_with_bhasini` — removed; a flow that still references one fails validation at publish (see §14).
- `detect_language` — no implementation.
- `call_and_wait` — never a function name. It is a **seeded sample flow** ("Call and Wait Flow", `priv/data/flows/call_and_wait.json`) that demonstrates the async pattern using `filesearch-gpt` with a `callback_url`.
- `unified-llm-call` / `unified-voice-llm-call` — internal Kaapi call shapes, not flow-node names. The flow-node names are `filesearch-gpt` and `voice-filesearch-gpt`.
- There is no `CommonWebhook` module any more;

--- entry
heading: 6. Webhooks — Complete Reference › 6C. "Call a Function" Node › Async nodes and the resume path
---

The four async nodes acknowledge immediately, park the flow, and are resumed by a signed callback to `POST /webhook/flow_resume`. Their bodies must carry `organization_id`, `flow_id` and `contact_id` — `KaapiSupport.parse_flow_fields/1` rejects a missing or non-numeric one with `"Invalid or missing flow metadata for Kaapi webhook"`. STT additionally validates that `speech` is an `https` URL.

--- entry
heading: 6. Webhooks — Complete Reference › 6C. "Call a Function" Node › Per-org custom clients
---

Tap, Sol, Avanti, Stir, Lahi, ReapBenefit, MukkaMaar, Balajanaagraha, DigitalGreen, NayiDisha, ArogyaWorld, Bandhu, KEF, PehlayAkshar, SunoSunao, Udhyam, DigitalGreenJharkhand, QuestAlliance, Oblf, BharatRohan, Atecf (and more). Registered in the `plugins` map keyed by organization id, and reached only when the name is not in the Registry.

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › All routes
---

| Route | Method | Who calls | Purpose |
| --- | --- | --- | --- |
| `/gupshup/*` | POST (forwarded) | Gupshup BSP | Inbound messages, events, opt-in/out, billing |
| `/gupshup-enterprise/*` | POST | Gupshup Enterprise | Same, enterprise variant |
| `/maytapi/*` | POST | Maytapi BSP | WhatsApp multi-device via Maytapi |
| `/webhook/stripe` | POST | Stripe | Billing events |
| `/webhook/flow_resume` | POST | External services (async flow resume) | Resume suspended flows |
| `/webhook/exotel/optin` | GET | Exotel | Missed-call opt-in |
| `/kaapi/knowledge_base_version` | POST | Kaapi | KB creation callback |
| `/kaapi/prompt_generation` | POST | Kaapi | Prompt-generation callback |
| `/kaapi/assistant_chat` | POST | Kaapi | Assistant-chat callback |
| `/kaapi/improve_prompt` | POST | Kaapi | Improve-prompt callback |
| `/kaapi/evaluation_run` | POST | Kaapi | AI-evaluation run callback |
| `/dify/chatbot-diagnose` | POST | Dify | Diagnostic endpoint |

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Gupshup routes
---

Messages:

- `POST /gupshup/message/text`
- `POST /gupshup/message/image|file|audio|video|sticker|location`
- `POST /gupshup/message/quick_reply|button_reply|list_reply`
- `POST /gupshup/message/whatsapp_form_response`

Status events:

- `POST /gupshup/message-event/enqueued|sent|delivered|read|failed`

User events:

- `POST /gupshup/user-event/opted-in`
- `POST /gupshup/user-event/opted-out`

Billing:

- `POST /gupshup/billing-event/conversations`

Auth: Gupshup-configured app-level token; `GlificWeb.Providers.Gupshup.Plugs.Shunt` validates org (must be `:active`), sets `Repo.put_current_user(organization.root_user)`.

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Maytapi routes
---

- `POST /maytapi/message/text|image|video|audio|voice|ptt|document|location|sticker|poll`
- `POST /maytapi/message-event/handler`
- `POST /maytapi/status/status`

Set webhook URL in Maytapi dashboard as: `https://api.{shortcode}.glific.com/maytapi` (or `https://{domain}/maytapi`).

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Flow Resume (`/webhook/flow_resume`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/

Controller: `FlowResumeController.flow_resume_with_results`. Validates via `validate_request/2` (`:223-253`):

1. `organization_id` in body matches auth context.
2. HMAC-SHA256 signature matches (same `Glific.signature` algorithm).
3. Timestamp within **15 minutes** of now (900s window).

Request body:

```json
{
 "success": true,
 "message": "ok",
 "result_name": "my_node",
 "organization_id": 1,
 "flow_id": 12,
 "contact_id": 42,
 "timestamp": 1713180000000000,
 "signature": "<hex>",
 "data": { "response": {... } }
}
```

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Stripe webhook
---

Plug `GlificWeb.StripeWebhook` verifies via `Stripe.Webhook.construct_event/3` using `Application.fetch_env!(:stripity_stripe,:signing_secret)`. Handles `invoice.created/paid/failed`, `customer.subscription.*`, `customer.updated/deleted`.

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Exotel opt-in
source: https://glific.github.io/docs/docs/Integrations/Setting%20up%20Exotel/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Setting%20up%20Exotel/

`GET /webhook/exotel/optin?CallFrom=...&CallTo=...&To=...`. Looks up phone → flow_id in org creds, opt-in contact, starts configured flow.

--- entry
heading: 6. Webhooks — Complete Reference › 6D. Webhook Logs & Debugging
---

`webhook_logs` is the primary outgoing-webhook debug table. For incoming webhooks there's no single log table; failures appear in application logs and (for message events) in `messages.errors`.

--- entry
heading: 6. Webhooks — Complete Reference › 6D. Webhook Logs & Debugging › Signatures of outgoing webhook failures in `webhook_logs`
---

| Pattern | Diagnosis |
| --- | --- |
| `error` set, `status_code=400` | Local error before the HTTP call (DNS, connection refused, timeout). Check `error` text. |
| `status_code=0` or null, `error` populated | Network / timeout |
| `status_code=4xx` | Auth, bad URL, bad body. Check `response_json`. |
| `status_code=5xx` | Server crashed. Check receiving server logs. |
| `response_json=null`, `error="Could not decode message body..."` | Non-JSON response |
| `status_code` in 200-299 but `response_json=null` | Empty body returned |

--- entry
heading: 6. Webhooks — Complete Reference › 6E. Common Webhook Issues — Decision Tree
---

```
"Webhook not firing / no response"
├── Did the flow reach the webhook node?
│ ├── Check: flow_contexts.node_uuid for this contact
│ ├── No → flow died earlier; check prior nodes and is_killed/reason
│ └── Yes → Did webhook_logs get a row?
│ └── Row exists → inspect status_code and error columns
│ ├── Timeout (10s for GET) → external server too slow
│ ├── 4xx → auth/URL issue
│ ├── 5xx → external server error
│ ├── 2xx but null response_json → non-JSON body
│ └── 2xx + JSON but results missing → result_name typo or nesting

"Webhook works in Postman but not Glific"
├── Body differs — Glific sends {contact, wa_group, results, flow, organization_id}
├── Headers differ — Glific adds X-Glific-Signature
├── Timeout — Postman waits forever; Glific GET times out at 10s
├── IP allowlist on receiver blocks Glific
└── Self-signed SSL cert — Tesla rejects by default

"Response data not accessible in flow"
├── @results.<node_name>.<key> — node_name is the webhook node's result_name, NOT node label
├── Nested JSON — works but path deepens: @results.node.user.name
├── HTTP non-200 — any non-2xx treats response as nil
└── Response was array — use @results.node.0, @results.node.1

"Incoming BSP webhook not processing messages"
├── BSP dashboard webhook URL correct and reachable?
├── Organization is_active=true? (Shunt rejects non-active orgs)
├── BSP provider's own webhook delivery logs show success?
└── Glific server logs — controller errors, JSON decode failures
```

--- entry
heading: 6. Webhooks — Complete Reference › API to Start Flow Externally
---

GraphQL mutations (see §1.2): `startContactFlow`, `startWaGroupFlow`, `startGroupFlow`. Auth via user token scoped to org. No REST equivalent exists; external systems typically authenticate as a service user and call GraphQL.

---

--- entry
section: 7.3
heading: 7. Triggers & Scheduling › 7.3 How Triggers Fire
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

Every minute, `MinuteWorker` dispatches `triggers_and_broadcast` → `Triggers.execute_triggers(org_id)`.

Query:



```
IF last_trigger_at IS NULL OR Date.diff(today, last_trigger_date) < 0 → fire
ELSE IF frequency=["hourly"] AND last_trigger_at.hour < now.hour → fire
ELSE skip
```

On fire:

1. `update_next/1` → non-repeating trigger becomes inactive; repeating trigger recomputes `next_trigger_at` via `Helper.compute_next/1`.
2. If new `next_trigger_at > end_date` → `is_active=false`.
3. Insert `trigger_logs` row.
4. Start flow: `Flows.start_group_flow(flow, group_ids)` or `start_wa_group_flow`.

--- entry
section: 7.4
heading: 7. Triggers & Scheduling › 7.4 Frequency Computation
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

- `daily`: shift +1 day
- `hourly`: next hour in `hours` list (0-23), rolls over to next day
- `weekly`: next day in `days` (1=Mon..7=Sun)
- `monthly`: next day in `days` (1-31), variable-month-length aware
- `weekday`: next Mon-Thu (per helper logic)
- `weekend`: next Fri-Sun
- `none`: no shift — trigger marked inactive after fire

--- entry
section: 7.5
heading: 7. Triggers & Scheduling › 7.5 Common Trigger Issues
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

| Symptom | Check |
| --- | --- |
| Not firing | `is_active=true`; `next_trigger_at <= now()+1min`; `end_date` not passed |
| Fires but flow doesn't start | `flows.is_active=true`; latest `flow_revisions.status='published'`; group has contacts; contacts opted in / in session |
| Wrong fire time | `start_at` in org timezone? `Helper.compute_next` uses Timex with org tz |
| One-time trigger still active | `is_repeating=false` but not yet fired; after firing, is_active flips to false |

---

--- entry
section: 8.2
heading: 8. BigQuery Integration › 8.2 Tables Synced
source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Glific%20BigQuery%20Tables%20Guide/

Core: `contacts, contact_histories, contacts_fields, contacts_groups, contacts_wa_groups`
Flows: `flow_contexts, flow_counts, flow_labels, flow_results, flows`
Groups: `groups, wa_groups, wa_groups_collections`
Messages: `messages, messages_media, message_broadcasts, message_broadcast_contacts, message_conversations`
Templates: `interactive_templates`
Other: `profiles, stats, saved_searches, tags, tickets, trackers, whatsapp_forms, whatsapp_forms_responses, wa_messages, wa_reactions, certificate_templates, issued_certificates`
SaaS-only: `stats_all, trackers_all, trial_users`

Tables that **don't** resync on updates: `contact_histories, flow_labels, flows, message_conversations, stats, stats_all, tags`.

--- entry
heading: 8. BigQuery Integration › 8.3 Worker Cadence — How Often Sync Runs › Sync pass 1 — incremental insert + update (every 2 minutes)
---

| Item | Value |
| --- | --- |
| Cron expression | `*/2 * * * *` ([config.exs:58](glific/config/config.exs#L58)) |
| Frequency | Every 2 minutes, on every even minute (UTC) |
| Cron job | `MinuteWorker` with `args: %{job: :bigquery}` |
| Entry point | [`BigQueryWorker.perform_periodic/1`] |
| Org filter | `only_recent: true` — only orgs with `last_communication_at` within the last 720 min (12 h); see [`Partners.recent_organizations@active_minutes 720` |
| Upload batching | Rows are chunked in groups of 100 before each BigQuery streaming-insert call (`Enum.chunk_every(100)` throughout the worker) |

What it actually does each tick:

1. For every org with active BigQuery credentials and recent activity, it reads the per-table high-watermarks from `bigquery_jobs` (`table_id` for inserts, `last_updated_at` for upserts).

So a row written to Postgres is visible in BigQuery within **2–4 minutes** under normal load, and longer if the org has a backlog larger than 500 rows for that table (the worker drains 500 per tick until caught up).

--- entry
heading: 8. BigQuery Integration › 8.3 Worker Cadence — How Often Sync Runs › Sync pass 2 — daily duplicate cleanup (once a day)
---

| Item | Value |
| --- | --- |
| Cron expression | `58 23 * * *` ([config.exs:65](glific/config/config.exs#L65)) |
| Frequency | Once a day at **23:58 UTC** (≈ 05:28 IST next morning) |
| Cron job | `MinuteWorker` with `args: %{job: :daily_tasks}` |
| Org filter | `only_recent: true` (same 12-h activity gate) |


This pass exists because the 2-minute pass uses streaming inserts (which can produce duplicates on retry) and because update-tables write a new row per change rather than mutating in place; the daily DELETE collapses each `id` back to the latest `updated_at`.

--- entry
heading: 8. BigQuery Integration › 8.3 Worker Cadence — How Often Sync Runs › Worker config
---

- Queue concurrency: `bigquery: 10` ([config.exs:31](glific/config/config.exs#L31)) — at most 10 BigQuery jobs run in parallel across all orgs.
- `max_attempts: 1` means a failed job is **not retried** — it waits for the next 2-minute tick and is re-enqueued from the high-watermark.

--- entry
heading: 8. BigQuery Integration › 8.3 Worker Cadence — How Often Sync Runs › What turns sync off
---

- Org has had no inbound/outbound message in the last 12 h — skipped by `only_recent: true`.
- Credential has been auto-disabled by a `PERMISSION_DENIED` from BigQuery (see §8.4) — sync stops until the credential is re-enabled.

--- entry
section: 8.4
heading: 8. BigQuery Integration › 8.4 Error Messages
---

| Status | Behavior | Message |
| --- | --- | --- |
| `NOT_FOUND` | Re-creates dataset/schema | `"Sync schema with bigquery"` |
| `PERMISSION_DENIED` | Disables credential via `Partners.disable_credential` | From response body |
| `TIMEOUT` | Logs and retries | `"Timeout while inserting the data. {response}"` |
| `ALREADY_EXISTS` | Triggers schema refresh | — |
| `INVALID_SERVICE_ACCOUNT` | Fail hard | `"Invalid Service Account JSON"` |
| `ERROR_FETCHING_TOKEN` | Fail hard | `"Error fetching token with Service Account JSON"` |
| INSERT_ERRORS | Raises | `"BigQuery Insert Error for table {table}"` |

Log patterns (search in production logs):

- `"Insert data to bigquery for org_id: X, table: Y, rows_count: Z"`
- `"New Data has been inserted to bigquery successfully org_id: X, table: Y, max_id: N"`
- `"Updated Data has been inserted to bigquery successfully org_id: X, last_updated_at: T, table: Y"`
- `"Error while inserting the data to bigquery. org_id: X, table: Y, response: R"`

**Common failures:**

- Service account email not given BigQuery Data Editor + Data Viewer on the dataset.
- Credential JSON rotated but not updated in Glific org settings.
- Schema drift: a column added to Glific's `messages` table but not to BigQuery → `INSERT_ERRORS` with `"no such field"`.

---

--- entry
section: 9.3
heading: 9. Notifications System › 9.3 Categories & Sources (authoritative list)
---

| Category | Source file:line | Message string | Entity keys |
| --- | --- | --- | --- |
| `Message` | | `"Could not send message: contact: {id}, message: '{id}', reason: {reason}"` | contact_id, message_id |
| `Organization` | | Dynamic cleanup messages | varies |
| `Templates` | | `"Template {shortcode} has been approved"` | id, shortcode |
| `Templates` | | `"Template {shortcode} has been rejected"` | id, shortcode, reason |
| `Templates` | | `"Template {shortcode} has been failed"` | id, shortcode, reason |
| `Custom Certificates` | | `"Custom certificate generation with template_id: {id} failed for contact_id: {id} due to {reason}"` | cert_template_id, contact_id, error_reason |
| `Contact Upload` | | `"Contact upload completed"` | user_job_id |
| `Flow` | | Variable (passed in) | flow_id, flow_uuid, contact_id, parent_id, node_uuid |
| `Flow` | | `"Flow execution failed due to invalid regular expression"` | flow_uuid, node_uuid, organization_id |
| `Flow` | | `"Error from Google Sheets: {error}"` | spreadsheet_id, contact_id |
| `Assistant` | | Dynamic KB message | knowledge_base_version |
| `HSM template` | | Sync completion/failure | provider |
| `WhatsApp Forms` | | `"Syncing of whatsapp form templates has started in the background."` | provider |
| `WhatsApp Forms` | | Sync messages | provider |
| `WhatsApp Groups` | | `"Syncing of WhatsApp groups and contacts has started in the background."` | Provider: Maytapi |
| `WhatsApp Groups` | | `"Cannot send messages. WhatsApp phone {phone} is not connected with Maytapi. Current status: {status}"` | wa_managed_phone_id, phone, status |
| `Partner` | | `"Disabling {shortcode}. {error_message}"` | provider_id, shortcode, error |
| `Template` | | Template error messages | template_type |
| `Ticket` | | `"New Ticket created"` | ticket_body |
| `Google sheets` | | `"Google sheet sync failed"` | url, id, name |
| `WA Group` | `response_handler.ex` | `"Error sending message: {error_msg}"` | wa_group_id |
| `WA Group Member Upload` | `user_job_worker.ex` | Bulk group-member import result | user_job_id |
| `AI Evaluation` | `ai_evaluations.ex` | Evaluation run outcome | evaluation id |

**Categories that do not exist.** There is no `Trigger`, `Webhook`, `Contact` or `Collection` category — nothing in or calls `create_notification`. A failing trigger surfaces as a `Flow` notification (from the flow it started) or as nothing at all, so `trigger_logs` is the evidence to read; webhook failures live in `webhook_logs`. Querying `notifications` with a non-existent category returns an empty list, not an error — which reads misleadingly as "nothing is wrong".

--- entry
section: 9.4
heading: 9. Notifications System › 9.4 Critical Notification Handling
---

When severity = `"Critical"`:

- `handle_notification/2` triggers critical email via `NotificationMail.critical_mail`.
- Rate-limited: same critical mail not re-sent within 72 hours.

--- entry
section: 9.5
heading: 9. Notifications System › 9.5 Mapping Notifications → Root Causes
source: https://glific.github.io/docs/docs/Product%20Features/Notifications/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

| Notification message | Root cause | Fix |
| --- | --- | --- |
| `"Google sheet sync failed"` | API error, bad headers, empty sheet | See §4.4 for exact sub-errors in `sheets.failure_reason` |
| `"Google sheet media validation failed"` | Sheet synced fine, but a cell holds a media URL (image/video/audio/document) Glific could not use — unreachable link, wrong file type, or too large | Open the notification and read `media_validation_warnings` in its details: it lists each bad cell value and why. Fix the links in the sheet; the rest of the sync is unaffected |
| `"Unable to parse range"` | A flow wrote to a Google Sheet using a tab or range name that no longer exists (tab renamed or deleted). Filed under category Flow, not Google sheets | Match the range in the flow's Add Row node to the sheet's actual tab name |
| `"Could not send message: ... reason: ..."` | Session expired / opt-out / invalid bsp_status | Check `contact.bsp_status`, `optin_time`, `last_message_at` |
| `"Template ... rejected"` | Meta policy / invalid structure | Read `session_templates.reason` |
| `"Cannot send messages. WhatsApp phone X is not connected with Maytapi"` | Maytapi session died | Reconnect phone in Maytapi dashboard |
| `"Disabling {shortcode}. {error}"` | Credential invalid (BigQuery, Google Sheets, Gupshup) | Refresh/replace credential in Settings |
| `"Flow execution failed due to invalid regular expression"` | Bad regex in case condition | Fix regex in flow editor |
| `"Template expression is null in the flow"` | Template variable unresolved | Ensure prior node set the variable |
| `"New Ticket created"` | Flow created a ticket | Route to support tool |

---

--- entry
section: 10.1
heading: 10. Common Troubleshooting Decision Trees › 10.1 Flow Not Working
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/

```
Is flows.is_active = true?
├── No → Flow disabled. Enable in Flows screen.
└── Yes → Is there a flow_revision with status='published' for this flow?
 ├── No → Flow is in draft only. Publish it.
 └── Yes → Is contact.optin_status = true? (AND contact.status =:valid)
 ├── No → Contact opted out or invalid. Check contact_histories.
 └── Yes → Is contact.bsp_status valid for the send type?
 ├──:none → No session, no opt-in. Contact can't receive anything.
 └── OK → Check flow_contexts WHERE contact_id=X AND flow_id=Y
 ├── No contexts → Flow never triggered.
 │ ├── Keyword path: exact match in flow_keywords cache?
 │ ├── Trigger path: next_trigger_at passed, is_active=true?
 │ └── Manual: did GraphQL mutation error out?
 └── Has contexts → is_killed?
 ├── true → Read reason column. See §1.4.
 ├── false + completed_at set → completed normally
 └── false + completed_at null →
 ├── wakeup_at in future → waiting for time (normal)
 └── wakeup_at null → waiting for response. Check router cases vs last inbound.
```

--- entry
section: 10.2
heading: 10. Common Troubleshooting Decision Trees › 10.2 Message Not Sending
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

```
Is there a row in messages for this attempt?
├── No → create_and_send_message never called. Check flow_contexts / notifications.
└── Yes → What is bsp_status?
 │ ├── "1002" → Contact doesn't exist on WhatsApp → marked invalid automatically.
 │ ├── "471" → Rate limit → org suspended for day.
 │ ├── "1003" → Low balance → org suspended 3 days.
 │ └── Other → Provider-specific error string.
 ├──:sent (never advances) → Recipient phone off / blocked Glific / number bad. Days-old sent-but-not-delivered is typical.
 └──:delivered /:read → Delivered fine.
```

Also check gate errors before send (`can_send_message_to?`):

- `"Sorry! 24 hrs window closed..."` → session expired; use HSM.
- `"Cannot send hsm message... not opted in."` → `optin_time IS NULL`.
- `"Cannot send hsm message... invalid BSP status."` → `bsp_status` lacks `:hsm`.

--- entry
section: 10.3
heading: 10. Common Troubleshooting Decision Trees › 10.3 Sheet Not Syncing
source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/
---

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

```
├── is_active=false → Enable.
├── sync_status=:failed → read failure_reason:
│ ├── "Unknown error or empty content" → Sheet tab empty or wrong tab referenced by gid.
│ ├── "Repeated or missing headers" → Duplicate or blank header in row 1.
│ ├── "No read access..." / "No edit access..." → Share sheet with service account email.
│ ├── "Google Sheet not found." → URL wrong or sheet deleted.
│ ├── "Invalid Service Account JSON" / "Error fetching token..." → Re-upload credentials.
│ └── "Sheet with gid X not found" → Sheet tab renamed or deleted.
├── sync_status=:success but old last_synced_at → Cron not running OR auto_sync=false.
└── No sheet row for this URL → Sheet not registered. Add in Settings → Google Sheets.
```

--- entry
section: 10.4
heading: 10. Common Troubleshooting Decision Trees › 10.4 Template Not Working
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

```
├── status='PENDING' forever →
│ └── bsp_id set → Still awaiting Meta. Can take hours to days.
├── status='REJECTED' → Read `reason` field (Meta's message). Fix and resubmit.
├── status='FAILED' → Submission or sync error. Read `reason`.
├── status='APPROVED' + can't send →
│ ├── Check messages.errors for parameter mismatch.
│ ├── Check contact.optin_time (HSM requires opt-in).
│ └── Check contact.bsp_status IN (:hsm,:session_and_hsm).
└── Not visible in UI → is_active=false, or sync hasn't run (update_hsms runs hourly).
```

--- entry
section: 10.5
heading: 10. Common Troubleshooting Decision Trees › 10.5 Trigger Not Firing
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

```
├── is_active=false →
│ ├── is_repeating=false AND last_trigger_at set → already fired once (expected).
│ ├── end_date passed → trigger expired.
│ └── Otherwise → manually disabled.
├── is_active=true → When was last MinuteWorker run?
│ ├── Check oban_jobs WHERE worker='Glific.Jobs.MinuteWorker' — recent completions?
│ ├── next_trigger_at in future → not yet matured.
│ └── next_trigger_at past + last_trigger_at recent + hourly → already fired this hour, waits next.
└── Trigger fired but flow didn't start → Check flow.is_active, group has contacts, trigger_logs.flow_context_id.
```

--- entry
section: 10.6
heading: 10. Common Troubleshooting Decision Trees › 10.6 Contact Issues
---

```
"Contact not receiving":
├── status=:invalid → opted out / number doesn't exist
├── bsp_status=:none → no session, no opt-in
├── Session expired (now - last_message_at > 24h) AND opt-in missing → use HSM
└── Organization suspended → Partners.is_suspended check

"Contact opted out unexpectedly":
├── Check contact_histories for:contact_opted_out event
├── optout_method tells you what triggered it:
│ - "BSP" → user sent STOP in WhatsApp
│ - "Number does not exist" → error 1002 from provider
│ - "Glific Flows" → a flow action opted them out
│ - "Import" → CSV import set optout_time
```

--- entry
section: 10.7
heading: 10. Common Troubleshooting Decision Trees › 10.7 BigQuery Not Syncing
source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/BigQuery%20Setup%20and%20link%20with%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/BigQuery%20Setup%20and%20link%20with%20Glific/

```
├── No rows → Worker never ran for this org. Check credentials.
│ ├── "Invalid Service Account JSON" → re-upload.
│ ├── "PERMISSION_DENIED" → grant BigQuery Data Editor to service account.
│ ├── "NOT_FOUND" → Worker will auto-create schema; monitor next run.
│ └── "no such field" → schema drift; resync schema from Settings.
```

--- entry
section: 10.8
heading: 10. Common Troubleshooting Decision Trees › 10.8 Webhook Failing / No Data
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

```
Did flow reach the webhook node? → Check flow_contexts.node_uuid.
├── No → Flow died earlier. Check is_killed/reason and prior nodes.
└── Yes → Check webhook_logs WHERE flow_context_id=? AND url LIKE '%...%'
 ├── error set, status_code=400 → Local failure (DNS, SSL, timeout).
 │ ├── GET timeout = 10s. If external server slower, switch to async pattern:
 │ │ return 200 immediately, process, POST result to /webhook/flow_resume.
 │ └── SSL errors → external server using self-signed cert.
 ├── status_code 4xx → Auth (401/403), URL wrong (404), bad body (400).
 ├── status_code 5xx → External server error. Check their logs.
 ├── status_code 2xx, response_json null →
 │ ├── Response not valid JSON — set Content-Type: application/json and return valid JSON.
 │ └── Empty body — return at least {}.
 └── status_code 2xx, response_json set, but @results.X not accessible in flow →
 ├── result_name typo — must match exact value in flow node config.
 ├── Nested JSON needs deeper path: @results.node.user.name.
 └── Array → @results.node.0, @results.node.1.
```

--- entry
section: 10.9
heading: 10. Common Troubleshooting Decision Trees › 10.9 Webhook Works in Postman But Not Glific
---

- Glific body structure is fixed — `{contact, wa_group, results, flow, organization_id}` — not whatever you send in Postman.
- Glific adds `X-Glific-Signature` header; receiver may reject unknown headers (rare) or expect to validate it.
- Glific GET times out at 10s (hardcoded). Postman waits indefinitely.
- External server may allowlist IPs — Glific server IP needs allow.
- SSL: Glific uses Tesla+Hackney and rejects self-signed certs by default.

--- entry
section: 10.10
heading: 10. Common Troubleshooting Decision Trees › 10.10 Webhook Response Not Saving to Contact Fields
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

Webhook response alone doesn't write to contact fields. Must have an "Update Contact" node after:

```
webhook (result_name="lookup") → update_contact (field=age, value=@results.lookup.age)
```

Check:

- Is there a contact-field update node after the webhook?
- Is the path right (`@results.<result_name>.<key>`)?
- Does the contact_fields metadata row exist? If not, `maybe_create_contact_field` auto-creates — but if the value is nil, nothing gets stored.
- Did webhook actually return that key? Verify in `webhook_logs.response_json`.

--- entry
section: 10.11
heading: 10. Common Troubleshooting Decision Trees › 10.11 Incoming BSP Messages Not Being Processed
---

```
Are messages appearing in Glific's messages table at all?
├── No →
│ ├── BSP webhook URL in provider dashboard correct?
│ ├── Glific server reachable (DNS, SSL, public)?
│ ├── BSP delivery logs show success to Glific endpoint?
│ ├── organization.is_active=true? (Shunt plug rejects non-active orgs)
│ └── Check Glific server logs for parse errors.
├── Messages appear but flow doesn't trigger →
│ ├── Another flow already active (flow_contexts incomplete)?
│ ├── Keyword didn't match exactly (full-message, case-insensitive)?
│ ├── Contact opted in?
│ └── See §1.2 priority order.
└── Messages appear, flow triggers, but webhook inside flow fails → See §10.8.
```

---

--- entry
section: 11.1
heading: 11. All Webhook Endpoints Reference › 11.1 Outgoing (Glific → External) — Call Webhook Node
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

- **URL**: user-configured in flow editor (variables substituted).
- **Method**: GET, POST, or FUNCTION (FUNCTION is a local dispatch, no HTTP — §6C).
- **Headers sent**:
 - `X-Glific-Signature: t=<unix_seconds>,v1=<hmac_sha256_hex>` (always)
 - `Content-Type: application/json` (POST)
 - User-configured headers (substituted via `@contact.*`, `@results.*`)
- **Body (POST)** — exact structure:
 ```json
 {
 "contact": { "id": 42, "name": "...", "phone": "...", "fields": {...} },
 "wa_group": { "id": null, "label": null, "wa_managed_phone_id": null },
 "results": { "<result_name>": { "<k>": "<v>" } },
 "flow": { "name": "...", "id": 12 },
 "organization_id": 1
 }
 ```
 Plus any merged custom body fields.
- **Body (GET)**: Converted to query-string.
- **Timeout**: GET 10s; POST Tesla default.
- **Response expected**: HTTP 200-299 with JSON body.
- **Response success example**:
 ```json
 { "result": "ok", "score": 42, "name": "Asha" }
 ```
 Accessible as `@results.<node_name>.result`, `@results.<node_name>.score`.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.1 Outgoing (Glific → External) — Call Webhook Node › Signature Verification (external server)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

```python
import hmac, hashlib
def verify(signature_header: str, body_str: str, secret: str) -> bool:
 parts = dict(p.split('=', 1) for p in signature_header.split(','))
 timestamp = parts['t']
 expected = parts['v1']
 signed = f"{timestamp}.{body_str}".encode
 computed = hmac.new(secret.encode, signed, hashlib.sha256).hexdigest
 return hmac.compare_digest(computed, expected)
```

Secret = value of `organizations.signature_phrase` for the calling org. Default fallback: `"This is a dummy secret"`.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Gupshup (`/gupshup/*`, forwarded to `Providers.Gupshup.Plugs.Shunt`)
---

| Path | Purpose |
| --- | --- |
| `POST /gupshup/message/text` | Inbound text |
| `POST /gupshup/message/image` | Inbound image |
| `POST /gupshup/message/file` | Inbound document |
| `POST /gupshup/message/audio` | Inbound audio |
| `POST /gupshup/message/video` | Inbound video |
| `POST /gupshup/message/sticker` | Inbound sticker |
| `POST /gupshup/message/location` | Inbound location |
| `POST /gupshup/message/quick_reply` | Quick reply |
| `POST /gupshup/message/button_reply` | Button reply |
| `POST /gupshup/message/list_reply` | List reply |
| `POST /gupshup/message/whatsapp_form_response` | WA form response |
| `POST /gupshup/message-event/enqueued` | BSP accepted send |
| `POST /gupshup/message-event/sent` | BSP confirms sent |
| `POST /gupshup/message-event/delivered` | Delivered |
| `POST /gupshup/message-event/read` | Read |
| `POST /gupshup/message-event/failed` | Failed |
| `POST /gupshup/user-event/opted-in` | Opt-in |
| `POST /gupshup/user-event/opted-out` | Opt-out |
| `POST /gupshup/billing-event/conversations` | Billing |

Auth: Shunt plug validates org active, sets root user context.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Maytapi (`/maytapi/*`)
---

| Path | Purpose |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `POST /maytapi/message/text | image | video | audio | voice | ptt | document | location | sticker | poll` | Inbound messages |
| `POST /maytapi/message-event/handler` | Status events |
| `POST /maytapi/status/status` | Connection status |

Set webhook URL in Maytapi dashboard: `https://api.<shortcode>.glific.com/maytapi`.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Other
---

| Path | Purpose |
| --- | --- |
| `POST /webhook/stripe` | Stripe billing events (Stripe-signed) |
| `POST /webhook/flow_resume` | Async flow resume (HMAC-SHA256 signed, 15-min window) |
| `GET /webhook/exotel/optin` | Missed-call opt-in |
| `POST /kaapi/knowledge_base_version` | KB creation callback |
| `POST /kaapi/prompt_generation` | Prompt-generation callback |
| `POST /kaapi/assistant_chat` | Assistant-chat callback |
| `POST /kaapi/improve_prompt` | Improve-prompt callback |
| `POST /kaapi/evaluation_run` | AI-evaluation run callback |
| `POST /dify/chatbot-diagnose` | Diagnostic (header `x-dify-api-key`) |

There is **no `/kaapi/voice_flow_resume`** route. Every async flow node — STT, TTS, `filesearch-gpt` and `voice-filesearch-gpt` alike — resumes through `POST /webhook/flow_resume`.

--- entry
section: 11.3
heading: 11. All Webhook Endpoints Reference › 11.3 External API for Starting Flows
---

GraphQL (auth: user bearer token, org-scoped):

```graphql
mutation {
 startContactFlow(flowId: 123, contactId: 456, defaultResults: { x: "y" }) {
 success
 }
}
```

Also `startWaGroupFlow(flowId, waGroupId)` and `startGroupFlow(flowId, groupId)`.

To **resume** a flow parked on a Wait-for-result node from your own system, use `resumeContactFlow(flowId, contactId, result)` — `result` is a JSON scalar, and the mutation is gated at Manager level. That is a different path from the signed `/webhook/flow_resume` callback Glific's own async nodes use.

No REST equivalent for any of these. External integrations create a service user, obtain a token via `POST /api/v1/session`, and call the GraphQL endpoint at `POST /api`.

--- entry
section: 11.4
heading: 11. All Webhook Endpoints Reference › 11.4 Webhook Signing Summary
---

| Direction | Who signs | Algorithm | Header | Secret source |
| --- | --- | --- | --- | --- |
| Outgoing webhook | Glific | HMAC-SHA256 | `X-Glific-Signature: t=...,v1=...` | `organizations.signature_phrase` |
| Incoming flow_resume | External caller | HMAC-SHA256 | In body (`signature` + `timestamp`) | `organizations.signature_phrase`, 15-min window |
| Incoming Stripe | Stripe | Stripe Webhook sig | `Stripe-Signature` | Stripe signing secret in config |
| Incoming BSP (Gupshup/Maytapi) | — | None beyond URL secrecy | — | Org-specific URL path + org identifier in payload |

--- entry
section: 11.5
heading: 11. All Webhook Endpoints Reference › 11.5 Setting Up BSP Webhooks
---

**Gupshup:**

1. Gupshup dashboard → Settings → Webhook URL.
2. Set to: `https://api.<shortcode>.glific.com/gupshup` (or your deployment domain + `/gupshup`).
3. Enable events: messages, message-event, user-event (opt-in/opt-out), billing.

**Maytapi:**

1. Maytapi dashboard → Webhook.
2. Set to: `https://api.<shortcode>.glific.com/maytapi`.
3. Enable: messages, status, events.

**Kaapi:**

1. Kaapi callback URL for async LLM: configured in Kaapi-side per request via `signature_payload`.
2. Glific's `signature_phrase` is shared secret.

---

--- entry
section: 12.1
heading: 12. Interactive Messages › 12.1 Supported Types
source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/


```elixir
@interactive_message_type_const [:list,:quick_reply,:location_request_message]
```

| Type | API value | Purpose |
| --- | --- | --- |
| `list` | `list` | Scrollable menu with sections, items (title + subtitle), multiple options |
| `quick_reply` | `quick_reply` | Up to 3 reply buttons with body/header/footer |
| `location_request_message` | `location_request_message` | "Send Location" native button request |

--- entry
section: 12.2
heading: 12. Interactive Messages › 12.2 Character / Count Limits
source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages/

| Element | Max chars | Source |
| --- | --- | --- |
| Quick Reply header/title | 60 | |
| Quick Reply body text | 1024 | |
| Quick Reply button title | 20 | |
| List body text | 1024 | |
| List global button title | 20 | |
| List item title | 24 | |
| List item subtitle | 24 | |
| List option title | 24 | |
| List option description | 72 | |
| Location Request body | 1024 | |
| **Aggregate content across all fields** | 1024 | |

Aggregate check — `validate_interactive_content_length/1`:

```elixir
if total_length > 1024 do
 {:error, "The total length of the body and options exceeds 1024 characters"}
```


> "Trimming has been done for the following languages due to exceeding character limits: [Language Names]. Please verify the content before saving."

--- entry
section: 12.4
heading: 12. Interactive Messages › 12.4 Translations Field
---

Shape: `translations[<language_id_as_string>] = <full content map>`.

Resolution at send time: `InteractiveTemplates.formatted_data/2` → `translated_content/2` → `get_translations/2`. Falls back to `interactive_content` if language missing.

--- entry
section: 12.5
heading: 12. Interactive Messages › 12.5 Dynamic Population (Webhook/Flow → List Items)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20an%20interactive%20message/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20the%20contact%20an%20interactive%20message/


```elixir
interactive_content
|> get_in(["items"])
|> hd()
|> Map.put("options", build_list_items(params))
```

Each param becomes:

- `title` ← `param["label"]` (auto-trimmed to 20 via `meet_waba_button_spec/1`)
- `id` / `postbackText` ← `param["id"]`

Before dynamic content is applied, `MessageVarParser.parse_map/2` walks the entire content map substituting `@contact.*`, `@results.*`, `@global.*`, `@calendar.*`.

**There is no built-in "populate from Google Sheet" — it flows through a webhook whose response is used as `params`.**

--- entry
section: 12.6
heading: 12. Interactive Messages › 12.6 Button-Response Matching in Wait-for-Response
source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages%20Re-response/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Interactive%20Messages%20Re-response/

Case handlers in, compared against `msg.clean_body`.

| Case type | Matcher | Source |
| --- | --- | --- |
| `has_number_eq` | trimmed equality | |
| `has_any_word` | any word match (case-insensitive) | |
| `has_only_phrase` | exact phrase | |
| `has_phrase` | substring | |
| `has_all_words` | all words present | |

All matching is **case-insensitive**. User typing text instead of clicking a button still routes as long as text matches a case; unmatched text → no path fires (the wait continues or times out).

--- entry
section: 12.7
heading: 12. Interactive Messages › 12.7 Common Interactive Issues (DB signatures)
---

| Symptom | DB signature | Why |
| --- | --- | --- | --- |
| Red / error chat bubble | `messages.bsp_status = :error` AND/OR `messages.status = :error`; `messages.errors` JSON with provider reason | Contact opt-out, invalid media URL, session closed, provider rejection |
| List titles truncated at 24 chars | Trim happens in code, not DB | `trim_field/2` slices with `String.codepoints` then `Enum.take(max_length)` |
| Updated template not reflected after save | Flow JSON caches template at publish time | **Re-publish the flow** — no live binding between template edits and published flow definition |
| Location widget shows empty body after CSV translation upload | `interactive_content.body.text = nil` | `import_location_message/4` does `Enum.at(translated_texts, idx)` — returns `nil` on missing column |

--- entry
section: 12.8
heading: 12. Interactive Messages › 12.8 Send-Path Validation Chain
---

`Messages.send_and_create_message/2` → `check_for_interactive/2` → provider `:send_interactive` handler.

Errors that may fire:

- `"The total length of the body and options exceeds 1024 characters"`
- `"Button text cannot contain any markdown characters..."` — (blocks `**bold**`, `*italic*`, `__x__`, `_x_`, `#h`, `[l](u)`)
- `"Could not send message to contact: Check Gupshup Setting"` — (no provider wired)
- `{:error, reason}` from BSP → `bsp_status::error`, `errors` JSON populated

---

--- entry
section: 13.1
heading: 13. LLM & AI Integration › 13.1 Providers Supported
source: https://glific.github.io/docs/docs/Integrations/ChatGPT%20using%20OpenAI%20APIs/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/ChatGPT%20using%20OpenAI%20APIs/

| Provider | Module | Shortcode / Key | Default model |
| --- | --- | --- | --- |
| OpenAI | `Glific.OpenAI.ChatGPT` | `"open_ai"` credential, `organization.services["open_ai"]["secrets"]["api_key"]` | `"gpt-4o"` |
| Gemini | `Glific.ThirdParty.Gemini` | `"gemini"` credential | Configurable |
| Kaapi (async LLM/STT/TTS orchestrator) | `Glific.ThirdParty.Kaapi` | internal service, keys in `organization.services` | — |

Assistant IDs use the OpenAI format `asst_<24 alphanumerics>`.

**Model catalogue.** The model list shown in the Assistants UI is served by the backend (`Glific.ThirdParty.Kaapi.list_models_with_metadata/1`), cached globally, and annotated into two buckets:

- *recommended*: `gpt-5.6-luna` (Best value), `gpt-5-nano` (Fastest), `gpt-5-mini` (Budget), `gpt-5.6-terra` and `gpt-5.4` (All-rounder)
- *to_be_deprecated*: `gpt-4o`, `gpt-4o-mini` (badged "Deprecating")

`Kaapi.default_model/0` is still `"gpt-4o"` — deliberately held back, so an assistant created without an explicit model is persisted with `gpt-4o`, not with the top recommendation.

--- entry
section: 13.2
heading: 13. LLM & AI Integration › 13.2 Flow Node Actions for AI
source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

There is **no dedicated AI node**. Every AI step is a **Call Webhook** node with Method `FUNCTION` and the function name in the URL field.

| Function name | Module | Sync? | Notes |
| --- | --- | --- | --- |
| `filesearch-gpt` | `Webhooks.FilesearchGpt` | async | Kaapi unified LLM call; resumes via `/webhook/flow_resume` |
| `voice-filesearch-gpt` | `Webhooks.VoiceFilesearchGpt` | async | Gemini STT → Kaapi LLM → TTS; also resumes via `/webhook/flow_resume` |
| `speech_to_text` | `Webhooks.SpeechToText` | async | shared STT/TTS rate limit (below) |
| `text_to_speech` | `Webhooks.TextToSpeech` | async | same rate limit |
| `parse_via_chat_gpt` | `Webhooks.ParseViaChatGpt` | sync | one-shot completion, result under `@results.<result_name>.parsed_msg` |
| `parse_via_gpt_vision` | `Webhooks.ParseViaGptVision` | sync | image analysis; downloads and inlines the image as base64 first |

There is no `parse_via_gpt` — the name is `parse_via_chat_gpt`. There is no `/kaapi/voice_flow_resume` route; the `/kaapi/*` scope carries only `knowledge_base_version`, `prompt_generation`, `assistant_chat`, `improve_prompt` and `evaluation_run`. All four async flow nodes come back through `POST /webhook/flow_resume`.


**Required body fields for every async node** (`KaapiSupport.parse_flow_fields/1`): `organization_id`, `flow_id`, `contact_id`, each parseable as an integer. Missing or malformed → `{:error,:invalid_input, "Invalid or missing flow metadata for Kaapi webhook"}`. `speech_to_text` additionally requires `speech` to be an `https` URL (`"Media URL is invalid"` / `"Media URL is needed"`).

Body params for `filesearch-gpt`:

```json
{
 "assistant_id": "asst_abc123",
 "question": "What does section 3 say?",
 "thread_id": "@contact.fields.thread_id",
 "organization_id": "@organization.id",
 "flow_id": "@flow.id",
 "contact_id": "@contact.id"
}
```

`build_unified_llm_payload/5` maps `question` → `query.input` and `thread_id` → `query.conversation.id` (omit it and `conversation.auto_create` is set). A nil `assistant_id` fails fast with `"assistant_id is required"`; an id that does not resolve to a Kaapi config for the org fails in `lookup_kaapi_config/2` and routes to Failure.

--- entry
section: 13.3
heading: 13. LLM & AI Integration › 13.3 Knowledge Base / Vector Store
source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Filesearch%20Using%20OpenAI%20Assistants/

Schemas: `assistants`, `assistant_config_versions`, `knowledge_bases`, `knowledge_base_versions`. The code lives in and — there is no.


```
csv doc docx htm html md markdown pdf txt
```

Anything else (json, py, js, pptx, source files, images) is rejected. Note that filesearch indexes **text only** — images embedded in a PDF are not analysed.

Upload goes through **Kaapi**, not direct OpenAI calls: `Assistants.upload_file/2` hands the file to Kaapi, which builds the vector store and reports back on `POST /kaapi/knowledge_base_version`. `Kaapi.upsert/…` passes `vector_store_ids_add` from `tool_resources.file_search.vector_store_ids`.

Status mapping from Kaapi (`@knowledge_base_version_status_mapping`):

| Kaapi | `knowledge_base_versions.status` |
| --- | --- |
| `PROCESSING` | `in_progress` |
| `SUCCESSFUL` | `completed` |
| `FAILED` | `failed` |

`kaapi_job_id` is nil for legacy direct-OpenAI uploads. A new assistant created without an explicit model gets `Kaapi.default_model` = `"gpt-4o"`.

--- entry
section: 13.4
heading: 13. LLM & AI Integration › 13.4 Async Callback Protocol (`/webhook/flow_resume`)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20result/

`GlificWeb.Flows.FlowResumeController.flow_resume/2` parses the callback and hands off to `Glific.Flows.Webhook`. Validation lives in `Webhook.valid_callback?/2` → `validate_request/2` → `do_validate_signature/6`:

1. The callback must carry all of `organization_id`, `flow_id`, `contact_id`, `timestamp`, `signature` — any nil and it is rejected outright.
2. `callback.organization_id` must equal the request tenant.
3. HMAC signature over `Jason.encode!(%{organization_id, flow_id, contact_id, timestamp})` must match `Glific.signature/3`.
4. The `timestamp` (unix microseconds) must be within **15 minutes** of server time.

A rejected callback is logged as a warning and **answers 200 anyway** — the caller learns nothing and Kaapi has no retry to trigger. The `FlowContext` stays in await until `wakeup_at` fires. This is the most common cause of "LLM responded but flow stuck".

On a valid callback, `parse_callback_response/1` reads Kaapi's `{metadata, data}` shape into `thread_id` (from `response.conversation_id`), `output_type` and `message` (from `response.output.content.value`). If `output_type` is `"audio"`, `maybe_upload_tts_audio/1` uploads the base64 to GCS first (§14.4).

**Which exit the flow takes** (`resume_message/3`):

| Outcome | Temp message injected | Router exit |
| --- | --- | --- |
| `success: true`, `webhook_log_id` present | `"Success"` | Success |
| `success: true`, no `webhook_log_id` | `"No Response"` | falls through the No Response category |
| `success: false` | `"Failure"` | Failure |

Note that the outcome is read from the parsed `response` **first**, falling back to the raw Kaapi `result` — so a failed TTS upload routes to Failure even though Kaapi itself reported success.

--- entry
section: 13.5
heading: 13. LLM & AI Integration › 13.5 LLM Failure Modes (diagnostic table)
---

| Symptom | Where it comes from | DB signature | Fix |
| --- | --- | --- | --- |
| "200 but no answer sent" | `Webhook.resume_message/3` injects `"No Response"` when `success: true` but no `webhook_log_id` | `messages.body = "No Response"`; flow takes the No Response exit | Make the callback carry a real message; route the No Response exit |
| Flow hangs, no reply at all | Callback signature / timestamp / missing-field validation failed in `Webhook.valid_callback?/2` — logged as a warning, answered 200 | `flow_contexts.wakeup_at` still set; no update | Fix callback signing; check the org's `signature_phrase`; check the 15-minute timestamp window |
| Audio result but nil media | `maybe_upload_tts_audio/1` failed | `error_type: "tts_upload_failed"`, `reason` set, response rewritten to `success: false` | Read `reason` — it carries the real GCS/base64 cause (§14.5) |
| Kaapi not configured for the org | `Kaapi.fetch_kaapi_creds/1` returns an error → `{:error, :missing_api_key, reason}` | Failure message sent; webhook log records the reason | Enable / activate the Kaapi credential |
| Missing or unresolvable `assistant_id` | `lookup_kaapi_config/2` → `"assistant_id is required"`, or no config for that id | `webhook_logs.error` set; node routes to Failure | Copy the assistant id exactly; confirm it exists for the org |
| Missing flow metadata in the body | `KaapiSupport.parse_flow_fields/1` | `"Invalid or missing flow metadata for Kaapi webhook"` | Add `organization_id`, `flow_id`, `contact_id` to the node body |
| Bad media URL on STT | `KaapiSupport.validate_media/1` | `"Media URL is invalid"` / `"Media URL is needed"` | Pass an `https` media URL (`@input.media_url`) |
| Upstream overloaded / rate-limited | `Kaapi.classify/1` matches the overload regex → `:service_unavailable` | `webhook_logs.error` mentions overload / rate limit | Retry; escalate to the Kaapi owner if persistent |
| `question_text` empty on `parse_via_chat_gpt` | `parse_chatgpt_fields/1` | `"question_text is empty"` | Guard the variable before the node |
| Partial data from the KB | Vector-store retrieval scope | — | Prompt-side fix: instruct the assistant to search all documents; split large files |

--- entry
section: 13.6
heading: 13. LLM & AI Integration › 13.6 WhatsApp 1024-char limit
---

No truncation in Glific code. The 1024-char limit is enforced by the BSP layer. LLM responses are sent through to Gupshup as-is. Long responses are either rejected by the BSP or split by the WhatsApp client — not by Glific. If chunking is required, do it inside the LLM's system prompt or a post-process webhook.

---

--- entry
section: 14
heading: 14. Voice & Speech (STT/TTS)
---

>
> ```
> The '<old name>' webhook is deprecated. Please migrate this node to the '<new name>' node before publishing.
> ```
>
> Mapping: `speech_to_text_with_bhasini` → `speech_to_text`, `text_to_speech_with_bhasini` → `text_to_speech`, `nmt_tts_with_bhasini` → `text_to_speech`. There is no `Glific.Bhasini` module and no `dhruva-api.bhashini.gov.in` call left.

--- entry
section: 14.1
heading: 14. Voice & Speech (STT/TTS) › 14.1 Pipeline
source: https://glific.github.io/docs/docs/Integrations/Speech-to-text%20and%20Text-to-speech%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Speech-to-text%20and%20Text-to-speech%20in%20Glific/

```
user voice (audio URL from Gupshup)
 → STT (Kaapi, async — `speech_to_text` node)
 → LLM (Kaapi, async — `filesearch-gpt`)
 → TTS (Kaapi, async — `text_to_speech` node)
 → base64 mp3 in the callback → GCS upload → HTTPS URL
 → outbound audio message
```

Every one of these is an **async** webhook (`Glific.Flows.Webhooks.Async`). Each fires a Kaapi request with a signed `callback_url`, parks the flow, and is resumed by `POST /webhook/flow_resume` (`GlificWeb.Flows.FlowResumeController`). Place a **Wait for result** node after each.

Two execution modes:

- **Unified:** `voice-filesearch-gpt` does STT → LLM → TTS in one node.
- **Split:** separate `speech_to_text` / `filesearch-gpt` / `text_to_speech` nodes — three Kaapi callbacks.

--- entry
section: 14.2
heading: 14. Voice & Speech (STT/TTS) › 14.2 Engine selection
---

Speech runs on **Gemini**, with OpenAI as an alternative TTS engine.

- `Gemini.speech_to_text(audio_url, organization_id)` — transcription.
- `Gemini.text_to_speech(organization_id, text)` — synthesis, uploads to GCS and returns the URL.
- `Gemini.nmt_text_to_speech(organization_id, text, source_language, target_language, opts)` — translate (Google Translate) then synthesize.

`opts[:speech_engine]` defaults to `"gemini"`; pass `"open_ai"` to synthesize with OpenAI instead. Anything else falls through to Gemini. In a flow this is the optional `speech_engine` body key on `voice-filesearch-gpt`.

The STT and TTS webhook bodies also accept optional `provider`, `model`, `language` and (STT) `output_language` / (TTS) `voice` keys, which are passed through to Kaapi.

--- entry
section: 14.3
heading: 14. Voice & Speech (STT/TTS) › 14.3 Supported Languages
---

| Language | Code |
| --- | --- |
| Tamil | ta |
| Kannada | kn |
| Malayalam | ml |
| Telugu | te |
| Assamese | as |
| Gujarati | gu |
| Bengali | bn |
| Punjabi | pa |
| Marathi | mr |
| Urdu | ur |
| Spanish | es |
| English | en |
| Hindi | hi |
| Odia | or |

A `source_language` or `target_language` outside this map resolves to `nil` and the translate step fails, returning `%{success: false, media_url: nil, translated_text: <original text>}`.

--- entry
section: 14.4
heading: 14. Voice & Speech (STT/TTS) › 14.4 GCS Hard Dependency
---

Kaapi returns TTS audio as **base64**, and WhatsApp only accepts an HTTPS media URL — so TTS is unusable without GCS.

The upload happens on the callback path, in `Glific.Flows.Webhook.maybe_upload_tts_audio/1` → `upload_tts_audio/2`:

```elixir
remote_name = "Kaapi/outbound/#{uuid}.mp3"

with {:ok, decoded_audio} <- Base.decode64(base64_audio),
:ok <- File.write(mp3_file, decoded_audio),
 {:ok, media_meta} <- GcsWorker.upload_media(mp3_file, remote_name, organization_id) do
 {:ok, media_meta.url}
end
```

Only responses whose `output_type` is `"audio"` take this path. The temp file is removed on every branch, success or failure.

**On upload failure the node routes to Failure, not to a silent success.** The response is rewritten to `success: false`, `message: nil`, `error_type: "tts_upload_failed"` and a `reason` — deliberately overriding Kaapi's own `success: true`, so the webhook log records the real outcome.

--- entry
section: 14.5
heading: 14. Voice & Speech (STT/TTS) › 14.5 Audio messages with a null GCS URL — cause table
---

| Cause | Detection | Fix |
| --- | --- | --- |
| No audio in the callback | `reason` = "No TTS audio content received" | Kaapi returned an empty payload; check the Kaapi request log |
| Malformed base64 | `reason` = "TTS audio is not valid base64" | Report to the Kaapi owner; the node routes to Failure |
| GCS credentials revoked | `GcsWorker.upload_media` returns 403, surfaced in `reason` | Refresh the service-account JSON; re-activate the credential |
| GCS not configured | `upload_media` error surfaces as the `reason` | Enable Google Cloud Storage for the org |
| `/tmp` full | `File.write` fails | Add a disk alert; prune tmp regularly |
| Subscription cancelled | GCS API returns `accountDisabled` | Detected in `gcs_worker.ex`; credential auto-disabled |

All of these appear as `error_type: "tts_upload_failed"` with the real cause in `reason` — the code deliberately surfaces the actual failure rather than assuming "GCS not enabled".

--- entry
section: 14.6
heading: 14. Voice & Speech (STT/TTS) › 14.6 Why voice output is a link, not inline
source: https://glific.github.io/docs/docs/Integrations/Text%20to%20speech%20capabilities%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Text%20to%20speech%20capabilities%20in%20Glific/

WhatsApp's API cannot accept base64 audio bodies — only media URLs. The base64 audio is decoded to a temp mp3, uploaded to GCS, and the returned URL is what gets sent. If the upload fails, the node's result carries `success: false` and a nil message, and the flow should route the Failure exit.

---

--- entry
section: 15.1
heading: 15. WhatsApp Forms › 15.1 Schemas
---

| Table | Fields | Source |
| --- | --- | --- |
| `whatsapp_forms` | `id`, `name`, `meta_flow_id`, `status` (`draft` \| `published` \| `inactive`), `definition`, `categories`, `organization_id`, `revision_id`, `sheet_id` | |
| `whatsapp_forms_responses` | `id`, `raw_response` (map), `submitted_at`, `contact_id`, `whatsapp_form_id`, `organization_id` | |
| `whatsapp_form_revisions` | `id`, `definition` (JSON), `revision_number`, `whatsapp_form_id`, `user_id`, `organization_id` | |

--- entry
section: 15.2
heading: 15. WhatsApp Forms › 15.2 Lifecycle
source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

1. `create_whatsapp_form/2` creates a row with `status: "draft"`.
2. `publish_whatsapp_form/1` calls Gupshup `POST /flows/{id}/publish`, flips status to `:published`.
3. `deactivate_whatsapp_form/1` → `:inactive`.
4. `activate_whatsapp_form/1` re-enables.

--- entry
section: 15.3
heading: 15. WhatsApp Forms › 15.3 Gupshup Partner API Calls
---

| Operation | Verb + Path |
| --- | --- |
| Create form | `POST /flows` body `{name, categories}` (categories uppercased) |
| Update form meta | `PUT /flows/{meta_flow_id}` |
| List forms | `GET /flows` |
| Fetch asset | `GET /flows/{flow_id}/assets` |
| Publish form | `POST /flows/{flow_id}/publish` |
| Update asset JSON | `PUT /flows/{meta_flow_id}/assets` (multipart file upload) |
| Webhook subscribe | `POST /app/subscription` (for `FLOW_MESSAGE` events) |

--- entry
section: 15.4
heading: 15. WhatsApp Forms › 15.4 Response Handling
source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

On incoming form submission:

1. `create_whatsapp_form_response/1` parses `raw_response` JSON, stores in the responses table.

--- entry
section: 15.5
heading: 15. WhatsApp Forms › 15.5 Known Issue Strings
---

- "Something unexpected happened" / "Unauthorized access" — **not** in Glific code. These originate from Meta's form renderer; check Gupshup response body on create/publish for the actual error.
- All form API errors are logged with status code + raw response and returned as-is.

--- entry
section: 15.6
heading: 15. WhatsApp Forms › 15.6 Common Form Failures
source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

| Symptom | Check |
| --- | --- |
| Draft won't publish | `meta_flow_id` null → Meta hasn't accepted form yet; check categories are from Meta's allowed list |
| Form loads but won't proceed past page 1 | Validation rule mismatch on a required field (Meta-side); inspect form JSON `data_api` and field `required` flags |
| "Unauthorized access" | Partner token expired — see §16.3 |
| Responses not arriving | Subscription for `FLOW_MESSAGE` not set, or webhook URL wrong in Gupshup — verify `POST /app/subscription` was successful |

---

--- entry
section: 16.2
heading: 16. Gupshup & BSP Integration › 16.2 Provider Shortcodes
---

| Shortcode | Purpose |
| --- | --- |
| `gupshup` | Primary BSP — message sending, HSM, OTP |
| `maytapi` | WhatsApp groups integration |
| `open_ai` | LLM calls |
| `gemini` | LLM calls |
| `goth` | Google OAuth (for Sheets/Calendar) |
| `google_cloud_storage` | Media storage |
| `bigquery` | Data export |
| `google_slides` | Custom certificates |
| `exotel` | Missed-call opt-in callback |
| `kaapi` | Async LLM / STT / TTS dispatch |

Note the Settings screen does **not** show all of these: `Glific.Partners.list_providers/1` excludes `goth`, `kaapi`, `gupshup_enterprise`, `navana_tech`, `google_asr`, `dialogflow` and `open_ai` (plus `google_cloud_storage` for trial orgs). There is no `bhashini` provider — Bhashini has been removed.

--- entry
section: 16.3
heading: 16. Gupshup & BSP Integration › 16.3 Partner API (Gupshup ISV)
---

| Endpoint | Purpose | Line |
| --- | --- | --- |
| `GET /partner/app/{app_id}/token` | Per-app token — **cached 22 hours** | 347–372 |
| `GET /partner/account/api/partnerApps` | List apps | — |
| `PUT /app/{app_id}/business/profile` | Set business profile | — |
| `PUT /app/{app_id}/appPreference` body `{isHSMEnabled: "true"}` | Enable HSM | — |
| `POST /app/{app_id}/subscription` | Register webhook events | — |

Errors from any Partner API call are wrapped in `PartnerAPI.Error` and surfaced to UI. The exact strings "Linking App to partner failed" and "Only one partner linking request per 24 hours" are **not in the codebase** — they come from Gupshup's error body verbatim.

--- entry
section: 16.4
heading: 16. Gupshup & BSP Integration › 16.4 BSP Status Gate on Send
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

`contacts.bsp_status` enum: `:none` | `:session` | `:session_and_hsm` | `:hsm`.

| Case | Required BSP status | Error string |
| --- | --- | --- |
| Send HSM | `:session_and_hsm` or `:hsm` | `"Cannot send hsm message to contact, invalid BSP status."` |
| Send HSM, not opted in | any | `"Cannot send hsm message to contact, not opted in."` |
| Send HSM, org suspended | any | `"Cannot send hsm message to contact, organization is in suspended state"` |
| Send session | `:session_and_hsm` or `:session` | `"Sorry! 24 hrs window closed. Your message cannot be sent at this time."` |
| Optin flow send | status valid + `last_message_at` within 24h | `"Cannot send session message to contact, invalid BSP status or not messaged in 24 hour window."` |

--- entry
section: 16.5
heading: 16. Gupshup & BSP Integration › 16.5 Error #131049
source: https://glific.github.io/docs/docs/FAQ/Check%20WhatsApp%20Quality%20Rating%20and%20Messaging%20Limits/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Check%20WhatsApp%20Quality%20Rating%20and%20Messaging%20Limits/

Not present in Glific source. This is a Meta / WhatsApp error code (quality-rating / spam) that arrives inside `messages.errors` JSON from the BSP. No internal Glific handler for it — it surfaces as-is.

--- entry
section: 16.6
heading: 16. Gupshup & BSP Integration › 16.6 Inbound Error Codes Handled
---

| Code | Meaning | Handler action |
| --- | --- | --- |
| 1002 | Number not on WhatsApp | Opt-out contact, mark as invalid |
| 471 | Rate limit / WABA rejecting | Suspend org |
| 1003 | Insufficient BSP balance | Suspend org |

---

--- entry
section: 17.1
heading: 17. Contact Variables & Expressions › 17.1 Variable Prefixes
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Predefined%20Contact%20Variables%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Variables/Predefined%20Contact%20Variables%20in%20Glific/

| Prefix | Source | Example |
| --- | --- | --- |
| `@contact.*` | `Contacts.get_contact_field_map/1` | `@contact.name`, `@contact.phone`, `@contact.fields.age.value` |
| `@results.*` | `context.results` | `@results.survey.input`, `@results.survey.category` |
| `@results.parent.*` | parent sub-flow lookup | `@results.parent.answer` |
| `@results.child.*` | child sub-flow lookup | `@results.child.score` |
| `@flow.*` | metadata | `@flow.name`, `@flow.id`, `@flow.uuid` |
| `@calendar.*` | injected per org timezone | `current_date`, `yesterday`, `tomorrow`, `current_day`, `current_month`, `current_year` |
| `@global.*` | `Partners.get_global_field_map/1` | org-wide constants |
| `@wa_group.*` | group flows | `@wa_group.fields.admin` |

--- entry
section: 17.2
heading: 17. Contact Variables & Expressions › 17.2 Expression Engine
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Split%20By/Custom%20Expression/

Elixir syntax — not FLOIP or Liquid. Entry: `Glific.execute_eex/1`. There are **two evaluators**, selected per org by the `:safe_expressions` FunWithFlags flag:

| Flag | Path | Behaviour |
| --- | --- | --- |
| on | `Glific.Flows.Expression.interpret/1` | Fail-closed allowlist **interpreter**. Never calls `EEx.eval_string/1` or `Code.eval_quoted/2` — it walks and executes the same AST. Anything outside the allowlist is rejected. |
| off | `legacy_eval/1` | `suspicious_code/1` denylist, then `EEx.eval_string/1`. A denylist hit returns `"Suspicious Code. Please change your code. …"`. |

Both paths return `"Invalid Code"` on `EEx.SyntaxError` or any other exception, and emit AppSignal telemetry tagged by `path` (safe / legacy / denylist) and `status` (ok / error / blocked / syntax).


- Modules: `String`, `Decimal`, `Enum`, `List`, `Map`, `MapSet`, `Integer`, `Float`, `URI`, `Jason`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Calendar.strftime/2`, `Timex` (incl. `Timex.Timezone.convert/2`), `Regex`, plus `Glific.send_template/2` and a handful of per-NGO `Glific.Clients.*` template helpers. Module resolution goes through `@mfa` only, keyed on the *literal* alias — `alias System, as: Timex` cannot smuggle a call through.
- Bare Kernel forms: arithmetic, comparison, `<>`, `and`/`or`/`not`, `in`, `to_string`, `inspect`, the `is_*` guards, `max`/`min`/`then`/`hd`/`elem`/`length`, and ranges.
- Control flow: `if`, `case`, `with`, and single-clause anonymous functions of arity 1–2. Function-capture shorthand (`&String.upcase/1`) is rejected — write `&String.upcase(&1)`.
- Everything else — `System`, `File`, `:os`, `apply/3`, `alias`, `import`, computed module names, multi-clause `fn` — has no clause in `eval_node/2` and falls to the rejecting catch-all.

`Glific.validate_flow_expression/2` runs the matching validator at publish/import time, so authors get the error before the flow goes live.

Variable pre-parse is regex-based (`message_vars_parser.ex`) — up to 4 levels of `.`-nested paths; undefined references return **the literal string** (e.g. `"@contact.fields.nonexistent"`), not nil. Flow does not crash. `@contact.language` and `@contact.in_groups` (aliased as `@contact.groups`) are special-cased.

--- entry
section: 17.3
heading: 17. Contact Variables & Expressions › 17.3 Contact Field Storage
---

```json
{
 "age": {
 "value": "25",
 "label": "Age",
 "type": "text",
 "inserted_at": "2026-04-15T10:30:00Z"
 }
}
```

Writer: `ContactField.do_add_contact_field/5`. Mirrors to `active_profile.fields` when contact has an active profile.

--- entry
section: 17.4
heading: 17. Contact Variables & Expressions › 17.4 Update Contact Node
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Update%20the%20contact/

Action type `"set_contact_field"`. Runs:

1. `MessageVarParser.parse` on both name and value.
2. Optional `Glific.execute_eex` on the final value (so `<%= @contact.fields.counter + 1 %>` works) — via the safe interpreter or legacy EEx depending on the org's `:safe_expressions` flag (§17.2).

**Only updates the current flowing contact** — no cross-contact writes.

**Which properties the node can actually set.** The flow engine has `execute/3` clauses for `set_contact_field`, `set_contact_field_valid`, `set_contact_language`, `set_contact_name` and `set_contact_profile` only. There is **no handler for `set_contact_channel` or `set_contact_status`** — an action of that type hits the catch-all `execute/3` at and raises `UndefinedFunctionError "Unsupported action type"`. In the flow editor, Glific's fork trims the property dropdown to **Language** and **Channel** plus contact fields (`getContactProperties` in — Name and Status are commented out), so Channel is selectable but not executable. Do not build on it.

Reset-all action `"reset_contact_fields"` sets `fields: %{}`.

--- entry
section: 17.5
heading: 17. Contact Variables & Expressions › 17.5 Router Case Types
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20the%20contact%20to%20respond/


- Text: `has_number_eq`, `has_number_between`, `has_number`, `has_any_word`, `has_phrase`, `has_only_phrase`, `has_only_text`, `has_all_words`, `has_multiple`, `has_phone`, `has_email`, `has_pattern` (regex), `has_beginning`
- Intent: `has_intent`, `has_top_intent` (with confidence threshold)
- Media/group: `has_group`, `has_category`, `has_location`, `has_media`, `has_audio`, `has_video`, `has_image`, `has_file`

That is what the **engine** executes. The **editor** exposes fewer: the Glific frontend passes an `excludeOperators` list that removes `has_text`, `has_value`, `has_error`, `has_group`, `has_category`, every `has_date*`, `has_time`, the numeric `<`/`>`/`<=`/`>=` comparisons, and the location operators `has_state` / `has_district` / `has_ward`. So `has_group` and `has_category` will run if present in imported flow JSON, but an author cannot pick them from the UI.

--- entry
section: 17.6
heading: 17. Contact Variables & Expressions › 17.6 Dynamic Key Access
---

`@results.webhook.page_@contact.fields.index` is **not directly supported** — parser resolves `@contact.fields.index` first, then tries the literal `@results.webhook.page_<value>` path. The `<value>` becomes part of the key string. Works if `page_5` is a real key in the webhook results, not a nested structure.

--- entry
section: 18.1
heading: 18. Language & Translation › 18.1 Org Language Config
---

- `default_language_id` — required FK.
- `active_language_ids` — integer array (default `[]`).
- Validators: `validate_active_languages/1`, `validate_default_language/1` (lines 231–243).

--- entry
section: 18.2
heading: 18. Language & Translation › 18.2 Contact Language
---

`contacts.language_id`. Defaults to org default on creation. Flow `send_msg` picks translation via `Localization.get_translation/_` — falls back to original action text if no translation exists for contact's language.

--- entry
section: 18.4
heading: 18. Language & Translation › 18.4 Auto-Translate
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/


- `Flags.get_google_auto_translation_enabled(organization)` true → `Glific.Flows.Translate.GoogleTranslate`
- otherwise → whatever `config:glific,:adaptors, translators:` points at

There is no `Glific.Flows.Translate.OpenAI` module; the implementations present are `GoogleTranslate` and `Simple`. Strings over the token threshold (`@token_chunk_size 200`) are replaced with a warning by `check_large_strings/2` rather than being translated.


```elixir
if translation == "" and language != source_language do
 # collect for translation
```

Existing non-empty translations are skipped. To retranslate, clear the target cell first.

--- entry
section: 18.6
heading: 18. Language & Translation › 18.6 CSV Import/Export
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20Auto%20translate/

Modules `Glific.Flows.Translate.Export` and `Glific.Flows.Translate.Import`. CSV row: `[Type, UUID, lang1, lang2, …, Node_uuid]`.

Interactive-template CSV import drives `import_location_message/4` (§12.7) — empty cells silently become nil bodies. Validate CSV column count against active languages before upload.

--- entry
section: 18.7
heading: 18. Language & Translation › 18.7 Machine translation for voice
source: https://glific.github.io/docs/docs/Integrations/Speech-to-text%20and%20Text-to-speech%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Speech-to-text%20and%20Text-to-speech%20in%20Glific/

The translate step in the voice pipeline uses **Google Translate**, called from `Gemini.nmt_text_to_speech/5` before synthesis. Bhashini / IndicTrans is gone — there is no `Glific.Bhasini` module. The 14 languages it covers are in §14.3.

---

--- entry
section: 19.1
heading: 19. GCS & Media › 19.1 Credentials
source: https://glific.github.io/docs/docs/Pre%20Onboarding/Google%20Cloud%20Storage%20Setup%20-%20GCS/
---

📖 Source: https://glific.github.io/docs/docs/Pre%20Onboarding/Google%20Cloud%20Storage%20Setup%20-%20GCS/


- `service_account` JSON (loaded via Goth)
- `bucket` (public)
- `private_bucket` (default `"test-private-cc"`)

--- entry
section: 19.2
heading: 19. GCS & Media › 19.2 Sync Pipeline
---

`Glific.GCS.GcsJob` drives two phases:

- **Unsynced**: retroactive, oldest-first, limited to messages within last **30 days** (Gupshup URL TTL). Resets every **20 h** (`@nightly_interval_hrs`).
- **Incremental**: continuous sync of inbound messages.

Worker: `GcsWorker.perform_periodic/2`.

File naming: `YYYYMMDDhhmmss_C{contact_id}_F{flow_id}_M{media_id}.{ext}`.
Public URL: `https://storage.googleapis.com/{bucket}/public/{path}`.
Signed URL: 300-s expiry (configurable).

`GCS_FILE_COUNT` env var (default **5**, `config/runtime.exs:112`) caps files per run; fallback **10**.

--- entry
section: 19.3
heading: 19. GCS & Media › 19.3 Supported Media
---

| type | ext on GCS |
| --- | --- |
| `image` | `.png` |
| `video` | `.mp4` |
| `audio` | `.mp3` |
| `document` | `.pdf` |


| Type | Limit | Error on breach |
| --- | --- | --- |
| `image` | 5120 KB (5 MB) | `"Size is too big for the image. Maximum size limit is 5120KB"` |
| `video` | 16384 KB (16 MB) | same shape |
| `audio` | 16384 KB (16 MB) | same shape |
| `document` | 102400 KB (100 MB) | same shape |
| `sticker` | 100 KB | same shape |

A URL that cannot be fetched fails earlier with `"This media URL is invalid"`, and a missing `content-length` header also fails the size check (`do_validate_size(_, nil) -> false`).

--- entry
section: 19.4
heading: 19. GCS & Media › 19.4 Failures & DB Signatures
---

| Symptom | DB / log signature | Code |
| --- | --- | --- |
| GCS subscription cancelled | Credential auto-disabled: `credentials.is_active = false`, reason `"Billing account is disabled"` | |
| Service account revoked | `Partners.get_goth_token` returns `nil`; log `"error while fetching the gcs token"`; sync skipped | |
| Bulk files stuck | `gcs_jobs` row stuck on old `message_media_id`; `messages_media.gcs_error` populated | |
| Source URL expired | `messages_media` older than 30 d; sync filter excludes it | — |

`messages_media.gcs_error` field is populated only in the **unsynced** phase.

--- entry
section: 20.2
heading: 20. Billing & Wallet › 20.2 Wallet (Gupshup ISV)
source: https://glific.github.io/docs/docs/FAQ/Managing%20Gupshup%20Wallet%20Balance%20and%20Suspension/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Managing%20Gupshup%20Wallet%20Balance%20and%20Suspension/

ISV wallet name constant: `"4000202160_wallet"`.
Balance query: `Partners.get_bsp_balance/1` → `{:ok, %{"balance" => amount}}`.

--- entry
section: 20.3
heading: 20. Billing & Wallet › 20.3 Low-Balance Alerts
source: https://glific.github.io/docs/docs/FAQ/Managing%20Gupshup%20Wallet%20Balance%20and%20Suspension/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Managing%20Gupshup%20Wallet%20Balance%20and%20Suspension/

Thresholds on `settings`:

- `low_balance_threshold` — default **$10** (warning cadence: every 7 days).
- `critical_balance_threshold` — default **$3** (cadence: every 72 hours).

Worker: `BSPBalanceWorker.perform_periodic/1`. Dedup via `MailLog` lookback.


- Subject: `"[URGENT Low balance]: Messages on Glific will stop soon"`
- Body includes `"Your balance is low $#{bsp_balance}. Please top up your account..."`
- `MailLog.category = "low_bsp_balance"`.

--- entry
section: 20.4
heading: 20. Billing & Wallet › 20.4 Stripe Events
---

Webhook controller: `glific_web/providers/gupshup/controllers/billing_event_controller.ex`. Handles `invoice.payment_succeeded`, `invoice.payment_failed` (sets `is_delinquent: true`), `customer.subscription.updated/deleted`.

--- entry
section: 20.5
heading: 20. Billing & Wallet › 20.5 BigQuery Billing
source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/BigQuery%20Setup%20and%20link%20with%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Reporting%20%26%20Dashboard/BigQuery%20Setup%20and%20link%20with%20Glific/

Enablement is **credential-level** only — `BigQuery.active?/1` checks presence + `is_active`. When GCP billing is revoked, the BigQuery credential must be manually re-activated after fix.

--- entry
section: 20.6
heading: 20. Billing & Wallet › 20.6 Per-Flow / Per-Trigger Expense
---

**Not tracked.** Billing is org-level only. Usage goes to Stripe via `Stripe.SubscriptionItem.Usage.report_usage/_`. No cost attribution to flow or trigger.

---

--- entry
section: 21.1
heading: 21. Geolocation › 21.1 Storage
---

Separate `locations` table — NOT embedded in `messages`.


| Field | Type |
| --- | --- |
| `contact_id` | FK |
| `message_id` / `wa_message_id` | one required |
| `latitude`, `longitude` | float |
| `organization_id` | FK |

Message type `:location` in the enum.

--- entry
section: 21.2
heading: 21. Geolocation › 21.2 Location Request Interactive
source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/

Body (from `priv/data/flows/geolocation.json:7–15`):

```json
{
 "type": "location_request_message",
 "body": { "type": "text", "text": "Please send your location" },
 "action": { "name": "send_location" }
}
```

--- entry
section: 21.3
heading: 21. Geolocation › 21.3 Pin vs Typed Address
source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/

Only lat/lon from pin drops are stored in `locations`. A typed address stays in `message.body` as plain text — **it is not parsed into coordinates**. To capture both, branch on `message.type ==:location` in the flow and save text to a contact field when it's not.

--- entry
section: 21.4
heading: 21. Geolocation › 21.4 "Flow not reading location" Debug
source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Google%20Maps%20API%20for%20reverse%20geo%20location/


2. Inside flow, use a webhook or custom action to copy lat/lon into `contact.fields` so `@contact.fields.latitude` works thereafter.
3. For the current message: `@input.location.latitude` (present only when `message.type =:location`).

---

--- entry
section: 22.1
heading: 22. WhatsApp Groups (Maytapi) › 22.1 Integration Overview
source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/Setting%20up%20WhatsApp%20Groups%20Automation%20for%20existing%20NGOs/
---

📖 Source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/Setting%20up%20WhatsApp%20Groups%20Automation%20for%20existing%20NGOs/

Maytapi is a third-party WhatsApp API for group management. Credentials at `organization.services["maytapi"]`:

- `product_id` — Maytapi product UUID
- `token` — API token

HTTP client: `Glific.Providers.Maytapi.ApiClient`.

--- entry
section: 22.2
heading: 22. WhatsApp Groups (Maytapi) › 22.2 Tables
---

| Table | Key fields |
| --- | --- |
| `wa_managed_phones` | `phone`, `phone_id` (Maytapi), `status`, `wa_managed_phone_id` |
| `wa_groups` | `label`, `bsp_id`, `wa_managed_phone_id`, `last_communication_at` |
| `wa_groups_collections` | `wa_group_id`, `group_id` (Glific collection) |
| `contacts_wa_groups` | `contact_id`, `wa_group_id` |
| `wa_messages` | `body`, `type`, `status`, `bsp_status`, `wa_group_id`, `wa_managed_phone_id` |
| `wa_polls` | `question`, `options`, `wa_group_id` |

--- entry
section: 22.3
heading: 22. WhatsApp Groups (Maytapi) › 22.3 Managed-Phone Statuses
---

`connected` | `loading` | `pending` | `disconnected`. Anything non-`active`/`loading` triggers a **critical** notification:

> "Cannot send messages. WhatsApp phone {phone} is not connected with Maytapi. Current status: {status}"

--- entry
section: 22.4
heading: 22. WhatsApp Groups (Maytapi) › 22.4 Maytapi Webhook Events
---

Events: `message`, `group_join`, `group_leave`, `message_ack`.


- 200–299 → success, extract `msgId`, mark `bsp_status::sent`.
- 400–499 → client error, no retry.

--- entry
section: 22.5
heading: 22. WhatsApp Groups (Maytapi) › 22.5 Group vs Individual Differences
source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/WhatsApp%20Groups%20Automation%20Features/
---

📖 Source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/WhatsApp%20Groups%20Automation%20Features/

| Aspect | Individual | Group |
| --- | --- | --- |
| Table | `messages` | `wa_messages` |
| Send endpoint | Gupshup messages API | Maytapi `/sendMessage` |
| BSP status set | `:sent` \| `:delivered` \| `:read` \| `:error` | `:enqueued` \| `:sent` \| `:error` |
| Rate limits | Gupshup WABA tier | Maytapi plan |

--- entry
section: 23.2
heading: 23. Platform & Login › 23.2 Roles
source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/


```elixir
[:none,:staff,:manager,:admin,:glific_admin]
```

No `saas_admin` in this enum. SaaS super-admin is handled separately via `Glific.Saas.*` modules (platform-level, not per-org).

--- entry
section: 23.3
heading: 23. Platform & Login › 23.3 OTP / Login / Password Reset
source: https://glific.github.io/docs/docs/FAQ/Using%20Glific%20APIs%20for%20OTP%20Authentication/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Using%20Glific%20APIs%20for%20OTP%20Authentication/


| Endpoint | Behavior | Error strings |
| --- | --- | --- |
| `POST /api/v1/registration/send_otp` | Body `{phone, registration: "true"\|"false"}`. For register: checks `user exists? → error`, opts-in contact, validates can-send. For login: checks `user exists? → error`. Calls `create_and_send_verification_code/1` (sends HSM-based OTP via BSP). | `"Account with phone number #{phone} already exists"` (line 146), `"Account with phone number #{phone} does not exist"` (line 176), `"Cannot send the otp to #{phone}"` (156/172) |
| `POST /api/v1/registration` (create) | Verifies OTP via `PasswordlessAuth.verify_code/2`; creates user via Pow; issues access + renewal tokens. | Error codes: `:attempt_blocked`, `:code_expired`, `:does_not_exist`, `:incorrect_code` (line 56), `"Couldn't create user"` (line 40) |
| `POST /api/v1/registration/reset_password` | Verifies OTP + resets password; returns fresh tokens. | `"Couldn't update user password"` (line 229) |

--- entry
section: 23.4
heading: 23. Platform & Login › 23.4 Staff Deletion
source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

**There is no automatic staff deletion.** Only orgs have soft-delete (`organizations.deleted_at`). Users are deactivated by assigning `roles: [:none]`. A "staff account automatically deleted" report is usually an org-level deactivation (the user still exists; just their org is deleted).

--- entry
section: 23.5
heading: 23. Platform & Login › 23.5 Send-OTP Failure Reasons
---

`"Cannot send the otp to #{phone}"` surfaces when:

- Contact `bsp_status =:none` → no WhatsApp registration.
- Org is suspended.
- BSP rejection (balance, WABA state).
- HSM template for OTP is not approved / has wrong params.

Fallback path uses Glific's own Gupshup account if org's balance is zero.

---

--- entry
section: 24.1
heading: 24. Contacts & Collections — Deep Dive › 24.1 Collections = `groups` table
source: https://glific.github.io/docs/docs/Product%20Features/Others/Collections/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Collections/


| Field | Default |
| --- | --- |
| `label` | required, unique with org |
| `description` | optional |
| `is_restricted` | false — if true, only users assigned to the group can see it |
| `last_message_number` | 0 |
| `group_type` | `"WABA"` |

Join table `contacts_groups`: `(contact_id, group_id)` unique.

--- entry
section: 24.2
heading: 24. Contacts & Collections — Deep Dive › 24.2 Adding/Removing Contacts from a Collection via a Flow
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Add%20or%20Remove%20the%20contact%20to%20a%20collection/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Add%20or%20Remove%20the%20contact%20to%20a%20collection/

Actions: `add_contact_groups` / `remove_contact_groups`.

`action.groups = [%{"uuid" => "<group_id>", "name" => "<label>"}]`. For each entry:

1. `Glific.parse_maybe_integer(group["uuid"])`.
2. `Groups.create_contact_group/_`.
3. `contact_history` event with label `"Added to collection: \"<name>\""`.

If `parse_maybe_integer` fails (group UUID not a real id): `Logger.error("Could not parse action groups:...")` — **silently skips that group**. No exception. Symptom: collection stays empty despite the flow action "running successfully."

`remove_contact_groups` accepts `["all_groups"]` to purge all memberships.

--- entry
section: 24.3
heading: 24. Contacts & Collections — Deep Dive › 24.3 Bulk Flow Start for a Collection
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Start%20somebody%20else%20in%20a%20flow/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Start%20somebody%20else%20in%20a%20flow/


- Inputs: `flow`, `group_ids`, `default_results`, opts.
- Chunks contacts into `@contact_chunk = 1000` batches.
- Creates `MessageBroadcast` row with `flow_id`, `group_id`, `started_at`.

Rate limits: provider-layer `ExRated.check_rate/3`. Exceeding → Gupshup 471 → org auto-suspend (§16.6).

--- entry
section: 24.4
heading: 24. Contacts & Collections — Deep Dive › 24.4 Opt-In Lifecycle
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

`contacts` columns:

- `optin_time` — UTC datetime when opted in. **Source of truth.**
- `optin_method` — e.g. `"Glific Flows"`, `"WhatsApp API"`, `"URL"`.
- `optin_message_id` — UUID of the opt-in message.
- `optin_status` — legacy boolean; prefer `optin_time != nil`.

Set via `Contacts.optin_contact/_` → BSP-specific provider delegate.

--- entry
section: 24.5
heading: 24. Contacts & Collections — Deep Dive › 24.5 Flow Selection Priority for an Inbound Message
---

1. `draft:<keyword>` prefix → draft flow preview.
2. `template:<name>` prefix → template preview.
3. **New contact flow** — only if `state.newcontact == true` **and** `org.newcontact_flow_id` set. State.newcontact is set by `consumer_tagger`.
4. Published keyword exact match.
5. Regex match against `org.regx_flow`.
6. Otherwise: optin flow (if opted out and no active context), else drop.


```elixir
if start_optin_flow?(message.contact, context, body),
 do: start_optin_flow(...), else: move_forward(...)
```

--- entry
section: 24.6
heading: 24. Contacts & Collections — Deep Dive › 24.6 Why "hi" from an existing user sometimes re-triggers opt-in
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

`start_optin_flow?` returns true when contact's `optin_time` is nil **or** BSP session is closed AND the incoming body matches an opt-in keyword. Flow authors who use "hi" as both the opt-in trigger and a menu keyword will see this overlap. Fix: change opt-in keyword or check `optin_time != nil` earlier in the opt-in flow.

--- entry
section: 24.7
heading: 24. Contacts & Collections — Deep Dive › 24.7 24-h Window for Non-Opted-In Users
source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/HSM%20Templates/


```elixir
contact.bsp_status in [:session_and_hsm,:session] and
 Glific.in_past_time(contact.last_message_at,:hours, 24)
```

A non-opt-in contact can receive messages only while both conditions hold. After 2 inbound messages that cross the 24-h boundary, the flow silently stops sending — no error visible to staff unless they check `notifications` / `messages.errors`.

--- entry
section: 24.8
heading: 24. Contacts & Collections — Deep Dive › 24.8 API Update Collection
---

GraphQL `updateGroup(input: {id, label, description, isRestricted})` → `Groups.update_group/2`. Validates unique `(label, organization_id)` tuple. Any label collision returns a changeset error.

---

--- entry
section: 25.1
heading: 25. Flow Builder Advanced Features › 25.1 `ignore_keywords`
---

`flows.ignore_keywords` boolean (default false). Effect in: if contact has an active FlowContext with this flag set, inbound messages are **not** checked against the keyword cache — they go straight to the flow.

Edge case: applies only once a context exists. New contacts without context still trigger keyword matches (§24.5 step 4).

--- entry
section: 25.2
heading: 25. Flow Builder Advanced Features › 25.2 Simulator vs Real
---

Simulator detection: `Contacts.simulator_contact?/1` — the phone starts with `@simulator_phone_prefix`, which is **`"9876543210"`**, not `"923"`.

Bypassed in simulator:

- No BSP send (`Providers.Gupshup.Worker.process_simulator/_` returns `:ok`).
- No optout-status side effects.
- No balance / rate-limit errors.

Still enforced:

- Keyword/flow-selection logic (hence "preview works, phone doesn't" usually = session/optin/balance).
- Translations, variable parsing.

--- entry
section: 25.3
heading: 25. Flow Builder Advanced Features › 25.3 Flow Revision & Publish
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/

`flow_revisions.status` ∈ `draft` | `published` | `archived`. Only **one** `published` row per `flow_id`.

> `"Flow is already published with id #{flow_revision.id}, please archive it instead"`

No server-side "someone else is editing" lock — that string comes from the frontend heartbeat. The backend will accept whichever save arrives last.

--- entry
section: 25.4
heading: 25. Flow Builder Advanced Features › 25.4 Sub-Flows (`enter_flow` action)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Enter%20another%20flow/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Enter%20another%20flow/

On enter:

- Loop guard: if target `flow_uuid` already in `context.uuids_seen`, aborts with `"Repeated loop, hence finished the flow"`.
- Parent id: if current node is `is_terminal`, inherit `context.parent_id`; else current `context.id`.
- Starts child via `Flow.start_sub_flow/3`.

On child error: parent's `parent_id` is preserved; child context marked `:is_killed`. Parent does **not** auto-resume — only scheduled `wakeup` or manual reset resumes it.

--- entry
section: 25.5
heading: 25. Flow Builder Advanced Features › 25.5 Wait-for-Time / Wait-for-Response
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20time/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Wait%20for%20time/

- Wait-for-time sets `flow_contexts.wakeup_at = now + seconds`.
- Wait-for-response has no DB-level expiry — waits indefinitely unless a flow-level timeout node is added.

--- entry
section: 25.6
heading: 25. Flow Builder Advanced Features › 25.6 Broadcast / Bulk Send
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20a%20staff%20member%20a%20message/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20a%20staff%20member%20a%20message/

See §24.3. Important knobs:

- `@contact_chunk = 1000` (hard-coded).
- Message ordering within a contact is preserved; across contacts it's concurrent.

--- entry
section: 25.7
heading: 25. Flow Builder Advanced Features › 25.7 First-Time-User Routing Priority
source: https://glific.github.io/docs/docs/Product%20Features/Others/New%20Contact%2C%20Default%20flow%20Out%20of%20office%20hours%20notifications/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/New%20Contact%2C%20Default%20flow%20Out%20of%20office%20hours%20notifications/


1. `draft:` prefix
2. `template:` prefix
3. New-contact flow (if configured + tagged)
4. Keyword match
5. Regex match
6. Opt-in flow (if opted out)
7. Drop

---

--- entry
section: 26.1
heading: 26. Error Code Reference › 26.1 WhatsApp / Meta Codes Handled in Code
---

| Code | Handled at | Action taken |
| --- | --- | --- |
| 1002 | | Opt-out contact, mark invalid |
| 471 | | Suspend org (rate-limit) |
| 1003 | | Suspend org (no BSP balance) |

Other Meta codes (e.g. **131049** quality/spam) are surfaced verbatim in `messages.errors`; Glific has no specific branch for them.

--- entry
section: 26.2
heading: 26. Error Code Reference › 26.2 User-Facing Error Strings (from `contacts.ex` + `contact_action.ex`)
source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/HSM%20Template%20Message%20Error/

| Error text | Cause | Source |
| --- | --- | --- |
| "Contact status is not valid." | `contact.status != :valid` | |
| "Cannot send hsm message to contact, invalid BSP status." | BSP status not in `[:session_and_hsm, :hsm]` | |
| "Cannot send hsm message to contact, not opted in." | `optin_time` nil | |
| "Cannot send hsm message to contact, organization is in suspended state" | `org.is_suspended=true` | |
| "Sorry! 24 hrs window closed. Your message cannot be sent at this time." | session send + closed window | |
| "Cannot send session message to contact, invalid BSP status or not messaged in 24 hour window." | Opt-in flow variant of the above | |
| "Could not find interactive template" | Interactive template id missing | |
| "Infinite loop detected, body: #{body}. Aborting flow." | Same body sent > `@max_loop_limit` (3) in 6 h | |
| "The total length of the body and options exceeds 1024 characters" | Interactive content too large | |
| "Button text cannot contain any markdown characters..." | Markdown detected in button | |
| "Could not send message to contact: Check Gupshup Setting" | No provider handler | |
| "Flow is already published with id ..., please archive it instead" | Publishing when one is already published | |
| "Repeated loop, hence finished the flow" | Sub-flow cycle | |
| "Flow terminated because it has been set to inactive." | `is_active` toggled while running | |
| `error_type: "tts_upload_failed"` with the GCS error in `reason` | TTS audio could not be uploaded (often no GCS credential) | `flows/webhook.ex` `upload_tts_audio/2` |
| "Suspicious Code. Please change your code. ..." | EEx suspicious pattern guard | |
| "Account with phone number #{phone} already exists" / "... does not exist" | Signup/login phone lookup | |
| "Cannot send the otp to #{phone}" | OTP HSM send failure | |

--- entry
section: 26.3
heading: 26. Error Code Reference › 26.3 Notifications Table — Categories in Use
source: https://glific.github.io/docs/docs/Product%20Features/Notifications/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

Schema: `category`, `entity` (map), `message`, `severity`, `is_read`.

Severities: `Critical`, `Warning`, `Information`. Only `Critical` sends admin email (dedup by `MailLog` 72 h lookback).

| Category | Example message | Entity payload | Source |
| --- | --- | --- | --- |
| `"Flow"` | `"Infinite loop detected, body: X"` | `contact_id, flow_id, flow_uuid, node_uuid, name` | |
| `"Contact Upload"` | `"Contact upload in progress"` | `user_job_id` | |
| `"Gupshup Setup"` | `"Setup failed: <reason>"` | integration details | |
| `"HSM template"` | `"Template rejected: <reason>"` | `template_id`, reason | |
| `"Google sheets"` | `"Sheet sync failed: <reason>"` | `sheet_id`, row count | |
| `"Organization"` | Deactivation / suspension | `org_id`, reason | |
| `"WA Group"` | `"Group message failed"` | `group_id`, `contact_id` | `wa_group_action.ex` |
| `"Ticket"` | `"Ticket creation failed"` | `ticket_id`, reason | |
| `"low_bsp_balance"` | `"[URGENT Low balance] ..."` | — | `mails/balance_alert_mail.ex` |

--- entry
section: 26.4
heading: 26. Error Code Reference › 26.4 Common `{:error, _}` Tuples to Frontend
---

- `{:error, "Resource not found"}` — flow/node UUID invalid.
- `{:error, "Could not parse action groups:..."}` — bad group UUID.
- `{:error, ["resource", "Contact not found"]}` — `Repo.fetch_by` miss.
- `{:error, "Account does not have sufficient permissions to create dataset"}` — BigQuery PERMISSION_DENIED.
- `{:error, "Account deactivated with error code X status Y"}` — generic BigQuery failure.

---

_End of manual. Every error string, line reference, limit and enum value was sourced directly from the `glific/lib/` codebase. When code changes, re-verify timeout values (§13.4), session gate logic (§24.7), BSP error code handlers (§26.1), and new notification categories — they drift fastest._
