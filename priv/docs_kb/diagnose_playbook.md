# Glific Diagnose Playbook

> This doc is consumed by the DIAG_PLANNER node. When a user reports a problem, the planner retrieves chunks from this doc to decide which tables to query, with which filters, fields, limits, and time range.
>
> The planner outputs ONLY a JSON body for `POST /dify/chatbot-diagnose`. The interpreter then explains the result to the user.

## Complaint → Query Recipes

### Recipe 1: "My flow X isn't running" / "Flow X stopped triggering"

Tables: `flows`, `flow_revisions`, `notifications`.

```json
{
  "tables": {
    "flows": {
      "filters": { "flow_name": "Registration" },
      "fields": [
        "id",
        "name",
        "uuid",
        "is_active",
        "keywords",
        "version_number",
        "updated_at"
      ],
      "limit": 5,
      "apply_time_range": false
    },
    "flow_revisions": {
      "fields": [
        "id",
        "flow_id",
        "status",
        "version",
        "revision_number",
        "inserted_at"
      ],
      "limit": 10,
      "order": "inserted_at DESC",
      "apply_time_range": false
    },
    "notifications": {
      "filters": { "category": "Flow" },
      "fields": ["id", "message", "severity", "inserted_at", "entity"],
      "limit": 15,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

If `page_url` is `/flow/configure/<uuid>`, use `"flow_uuid": "<uuid>"` instead of `flow_name`.

Problem signals:

- `flows.is_active = false` → user disabled the flow
- No row in `flows` matching → flow renamed or doesn't exist
- No `flow_revisions` row with `status = "published"` for that `flow_id` → never published
- Latest published `flow_revisions.inserted_at` much older than `flows.updated_at` → user thinks they published recent edits but the publish didn't happen
- `notifications` rows with `severity = "Critical"` and category `Flow` → publish failure or runtime crash

### Recipe 2: "User X didn't get the message" / "Why didn't <phone> receive..."

Tables: `contacts`, `messages`, `notifications`.

```json
{
  "tables": {
    "contacts": {
      "filters": { "phone": "9876543210" },
      "fields": [
        "id",
        "name",
        "phone",
        "optin_status",
        "optin_time",
        "optout_time",
        "optout_method",
        "status",
        "bsp_status",
        "last_message_at",
        "last_communication_at"
      ],
      "limit": 1,
      "apply_time_range": false
    },
    "messages": {
      "filters": { "contact_phone": "9876543210" },
      "fields": [
        "id",
        "body",
        "type",
        "status",
        "bsp_status",
        "errors",
        "flow_id",
        "template_id",
        "send_at",
        "sent_at",
        "inserted_at"
      ],
      "limit": 20,
      "order": "inserted_at DESC"
    },
    "notifications": {
      "filters": { "category": "Message" },
      "fields": ["id", "message", "severity", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

If page is `/chat/<contact_id>`, use `"filters": {"id": <contact_id>}` on contacts and `{"contact_id": <contact_id>}` on messages.

Problem signals:

- `optin_status = false` or `optout_time IS NOT NULL` → contact opted out, can't receive
- `bsp_status = "none"` → 24h session expired and no HSM was sent
- `messages.status = "error"` with `errors` populated → delivery failed; read the error
- `messages.bsp_status` differs from `status` → BSP rejected after Glific accepted
- No `messages` for this contact → message was never queued (flow didn't reach that node, or template wasn't approved)
- `messages.status = "enqueued"` for a long time → BSP queue stalled

### Recipe 3: "Sheet sync is failing" / "My Google Sheet isn't syncing"

Tables: `sheets`, `notifications`, `webhook_logs`.

```json
{
  "tables": {
    "sheets": {
      "fields": [
        "id",
        "label",
        "url",
        "is_active",
        "last_synced_at",
        "auto_sync",
        "type",
        "sync_status",
        "failure_reason",
        "sheet_data_count"
      ],
      "limit": 20,
      "order": "last_synced_at DESC",
      "apply_time_range": false
    },
    "notifications": {
      "filters": { "category": "Google sheets" },
      "fields": ["id", "message", "severity", "inserted_at", "entity"],
      "limit": 20,
      "order": "inserted_at DESC"
    },
    "webhook_logs": {
      "fields": ["id", "url", "status_code", "error", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "7d",
  "page_url": "<from input>"
}
```

Problem signals:

- `sheets.is_active = false` → user disabled it
- `sheets.sync_status = "failed"` with `failure_reason` populated → read the reason
- `last_synced_at` is days old → cron job failing or not running
- Notification messages mentioning "Google sheet sync failed" / "Unable to parse range" / "media validation failed" → see the entity for sheet ID

Time range: 7d (sheet sync is daily; recent failures may be stale by 24h).

### Recipe 4: "Webhook not firing" / "My webhook in flow X isn't working"

Tables: `webhook_logs`, `flow_contexts`, `notifications`.

```json
{
  "tables": {
    "webhook_logs": {
      "fields": [
        "id",
        "url",
        "method",
        "status_code",
        "error",
        "response_json",
        "flow_id",
        "contact_id",
        "inserted_at"
      ],
      "limit": 20,
      "order": "inserted_at DESC"
    },
    "flow_contexts": {
      "filters": { "is_killed": false },
      "fields": [
        "id",
        "contact_id",
        "flow_id",
        "node_uuid",
        "is_await_result",
        "wakeup_at",
        "completed_at",
        "inserted_at"
      ],
      "limit": 10,
      "order": "inserted_at DESC"
    },
    "notifications": {
      "filters": { "category": "Flow" },
      "fields": ["id", "message", "severity", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

There is no `Webhook` notification category — webhook failures are recorded in `webhook_logs` and, when they break the flow, as a `Flow` notification. Filter on `Flow`, not `Webhook`.

If `page_url` contains a flow uuid, scope all three tables with `"flow_uuid": "<uuid>"` (the backend resolves it to `flow_id`).

Problem signals:

- `webhook_logs.status_code = 0` or null + `error` set → network/DNS/timeout
- `webhook_logs.status_code = 4xx` → auth or URL malformed; check `response_json`
- `webhook_logs.status_code = 5xx` → remote server crashed
- `webhook_logs.status_code = 2xx` but `response_json IS NULL` → non-JSON response body
- No `webhook_logs` rows for this flow → flow never reached the webhook node; check `flow_contexts.node_uuid` to see where it stopped
- `flow_contexts.is_await_result = true` with old `wakeup_at` → waiting on a webhook callback that never came back

### Recipe 5: "Trigger didn't fire" / "Scheduled flow didn't start"

Tables: `triggers`, `trigger_logs`, `notifications`.

```json
{
  "tables": {
    "triggers": {
      "fields": [
        "id",
        "name",
        "trigger_type",
        "flow_id",
        "is_active",
        "is_repeating",
        "last_trigger_at",
        "next_trigger_at",
        "frequency",
        "days",
        "hours",
        "start_at",
        "end_date",
        "group_type"
      ],
      "limit": 20,
      "order": "next_trigger_at DESC",
      "apply_time_range": false
    },
    "trigger_logs": {
      "fields": [
        "id",
        "trigger_id",
        "flow_context_id",
        "started_at",
        "inserted_at"
      ],
      "limit": 20,
      "order": "started_at DESC"
    },
    "notifications": {
      "filters": { "category": "Flow" },
      "fields": ["id", "message", "severity", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "7d",
  "page_url": "<from input>"
}
```

Problem signals:

- `triggers.is_active = false` → user disabled
- `next_trigger_at` is in the past but no matching `trigger_logs.started_at` → missed run
- `triggers.last_trigger_at` is older than the schedule suggests + no recent `trigger_logs` rows → trigger system stalled

Note: there is **no `Trigger` notification category** — the trigger code never writes notifications. A failing trigger usually surfaces as a `Flow` notification (the flow it started errored) or as nothing at all, so `trigger_logs` is the primary evidence here, not `notifications`.

### Recipe 6: "HSM template not delivering" / "My template isn't going out"

Tables: `session_templates`, `messages`, `notifications`.

```json
{
  "tables": {
    "session_templates": {
      "filters": { "is_hsm": true },
      "fields": [
        "id",
        "label",
        "shortcode",
        "status",
        "type",
        "is_hsm",
        "category",
        "reason",
        "quality",
        "number_parameters",
        "bsp_id",
        "uuid"
      ],
      "limit": 30,
      "apply_time_range": false
    },
    "messages": {
      "filters": { "is_hsm": true },
      "fields": [
        "id",
        "status",
        "bsp_status",
        "errors",
        "template_id",
        "contact_id",
        "send_at",
        "sent_at",
        "inserted_at"
      ],
      "limit": 20,
      "order": "inserted_at DESC"
    },
    "notifications": {
      "filters": { "category": "Message" },
      "fields": ["id", "message", "severity", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

Problem signals:

- `session_templates.status != "APPROVED"` → not usable yet; check `reason`
- `status = "REJECTED"` with `reason` populated → resubmit after fixing reason
- `quality = "LOW"` → WhatsApp may rate-limit sends
- `messages.errors` mentioning template / variable count / language → send-time mismatch
- `messages.bsp_status = "error"` for HSM messages → BSP rejected the send (often parameter mismatch)

For interactive (button/list) templates, swap `session_templates` for `interactive_templates` and filter `messages` on `interactive_template_id IS NOT NULL`.

### Recipe 7: "Notifications page is empty" / "I'm not seeing notifications"

```json
{
  "tables": {
    "notifications": {
      "fields": ["id", "message", "category", "severity", "inserted_at"],
      "limit": 50,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "7d",
  "page_url": "<from input>"
}
```

Problem signals:

- Empty result → no notifications generated (possible: nothing failed, OR notification job is down)
- Notifications exist in DB but user doesn't see them → likely a UI bug or permission filter, not a backend issue

### Recipe 8: "Contact is not opting in" / "Opt-in not working"

Tables: `contacts`, `messages`, `contact_histories`.

```json
{
  "tables": {
    "contacts": {
      "filters": { "phone": "9876543210" },
      "fields": [
        "id",
        "phone",
        "optin_status",
        "optin_time",
        "optin_method",
        "optin_message_id",
        "optout_time",
        "optout_method",
        "status",
        "bsp_status",
        "last_message_at"
      ],
      "limit": 1,
      "apply_time_range": false
    },
    "messages": {
      "filters": { "contact_phone": "9876543210" },
      "fields": [
        "id",
        "body",
        "type",
        "status",
        "sender_id",
        "receiver_id",
        "inserted_at"
      ],
      "limit": 10,
      "order": "inserted_at DESC"
    },
    "contact_histories": {
      "filters": { "contact_phone": "9876543210" },
      "fields": [
        "id",
        "event_type",
        "event_label",
        "event_datetime",
        "event_meta",
        "inserted_at"
      ],
      "limit": 20,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "7d",
  "page_url": "<from input>"
}
```

Problem signals:

- `contacts.optin_status = true` with `optin_time` set → already opted in; "not working" might be a misunderstanding
- `contacts.status = "blocked" or "invalid"` → can't receive even if opted in
- No incoming messages from this contact → opt-in flow didn't reach Glific (BSP webhook issue)
- `contact_histories` shows recent opt-out events → user opted out then back in, race condition possible

### Recipe 9: "Flow stuck mid-execution" / "Flow stopped at a step"

Tables: `flow_contexts`, `messages`, `webhook_logs`. Add `flow_results` if the user wants to know what data was captured.

```json
{
  "tables": {
    "flow_contexts": {
      "filters": { "is_killed": false, "completed_at": null },
      "fields": [
        "id",
        "contact_id",
        "flow_id",
        "node_uuid",
        "status",
        "is_await_result",
        "wakeup_at",
        "inserted_at"
      ],
      "limit": 20,
      "order": "inserted_at DESC"
    },
    "messages": {
      "filters": { "status": "error" },
      "fields": [
        "id",
        "body",
        "errors",
        "flow_id",
        "contact_id",
        "inserted_at"
      ],
      "limit": 10,
      "order": "inserted_at DESC"
    },
    "webhook_logs": {
      "fields": [
        "id",
        "url",
        "status_code",
        "error",
        "flow_id",
        "flow_context_id",
        "inserted_at"
      ],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "6h",
  "page_url": "<from input>"
}
```

Problem signals:

- `flow_contexts` rows older than ~30 min with `completed_at = null` and `is_await_result = true` → waiting on webhook or wait_for_response
- `flow_contexts` with `wakeup_at` in the past → scheduler missed the wake-up
- `messages.errors` populated → send failure mid-flow
- `webhook_logs.status_code` non-2xx with matching `flow_context_id` → webhook failed and the flow has nowhere to go

### Recipe 10: "Broadcast didn't go out to my collection"

Tables: `message_broadcasts`, `message_broadcast_contacts`, `notifications`.

```json
{
  "tables": {
    "message_broadcasts": {
      "fields": [
        "id",
        "started_at",
        "completed_at",
        "type",
        "group_id",
        "message_id",
        "flow_id",
        "user_id",
        "inserted_at"
      ],
      "limit": 10,
      "order": "started_at DESC"
    },
    "message_broadcast_contacts": {
      "fields": [
        "id",
        "message_broadcast_id",
        "contact_id",
        "processed_at",
        "status",
        "inserted_at"
      ],
      "limit": 50,
      "order": "inserted_at DESC"
    },
    "notifications": {
      "filters": { "category": "Message" },
      "fields": ["id", "message", "severity", "inserted_at"],
      "limit": 10,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

Problem signals:

- `message_broadcasts.completed_at IS NULL` long after `started_at` → broadcast worker stalled
- Many `message_broadcast_contacts` with `processed_at IS NULL` → never picked up by the worker
- `message_broadcast_contacts.status = "error"` cluster → BSP rejecting (HSM/quality/window issue)

### Recipe 11: When the user gives no specifics — "Something's wrong" / "It's broken"

Don't query speculatively. Call only `notifications`:

```json
{
  "tables": {
    "notifications": {
      "fields": ["id", "message", "category", "severity", "inserted_at"],
      "limit": 30,
      "order": "inserted_at DESC"
    }
  },
  "time_range": "24h",
  "page_url": "<from input>"
}
```

The interpreter then asks the user a specific follow-up based on the most-frequent category in the result.

---

## Defaults the planner should apply

- Always include `page_url` (passed in from the input).
- Default `time_range` is `"24h"`. Widen to `"7d"` for low-frequency events (sheet syncs, scheduled triggers, broadcasts).
- `time_range` applies by default to every table that has `inserted_at`. **Set `"apply_time_range": false` per table for entity lookups** (flows by name, contacts by phone, sheets, triggers, session_templates).
- Default `limit` per table is `10–20`. Hard cap is 50 (silently clamped).
- Pick AT MOST 3 tables per call. More than 3 = guessing.
- Skip `organization_id` in filters — the backend auto-scopes by org from `page_url`.
- Order results by `inserted_at DESC` for log-shaped tables to surface recent first.
- Prefer virtual filter keys (`flow_uuid`, `flow_name`, `contact_phone`, `contact_name`) over reaching for join tables.

## Valid `notifications.category` values

Filtering on a category that doesn't exist silently returns `[]`, which reads as "nothing is wrong". These are the only categories the backend ever writes:

`Message` · `Flow` · `Templates` · `HSM template` · `Partner` · `Ticket` · `Contact Upload` · `Custom Certificates` · `Google sheets` · `Organization` · `Assistant` · `AI Evaluation` · `WA Group` · `WA Group Member Upload` · `WhatsApp Groups` · `WhatsApp Forms`

There is no `Trigger`, `Webhook`, `Contact` or `Collection` category. For trigger and webhook problems, read `trigger_logs` / `webhook_logs` and fall back to the `Flow` category.

## What NOT to do

- Don't request fields not listed in the table schemas above — backend silently drops them, and if no valid fields remain the table returns `[]`.
- Don't use `templates` as a table name — it's `session_templates` (or `interactive_templates`).
- Don't request `flows.last_published_at`, `groups.users_count`, or `users.phone` — they don't exist as columns.
- Don't expect `LIKE`/`ILIKE` on regular field filters — only `=`, `IN`, and `IS NULL`. Use the virtual filter keys for fuzzy match.
- Don't query the same table twice with different filters in one call — pick one filter set.
- Don't speculatively query 5+ tables hoping one will have the answer. Use Recipe 11's notification-only fallback if the user is vague.
- Don't request a multi-column `order` — only `"<field> ASC|DESC"` is parsed.
- Don't pass time_range formats other than `Nh` or `Nd` — the regex falls back to 24h on anything else.
- Don't invent a `notifications.category` — use one from the list above. An unknown category returns an empty list, not an error.
