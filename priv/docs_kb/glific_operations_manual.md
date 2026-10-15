--- entry
section: 1.1
heading: 1. Flow Execution Engine › 1.1 Flow Lifecycle: Draft → Published → Active → Executing
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Overview/

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
section: 1.8
heading: 1. Flow Execution Engine › 1.8 Common Flow Issues — DB Signatures
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Flows%20not%20working%20-%20Troubleshoot%20checklist/

| Symptom                                 | Check                                                                                                                                                                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flow not triggering                     | `flows.is_active=true`? Latest `flow_revisions.status='published'` exists? `contact.optin_status=true`? Keyword in `flow_keywords` cache? Another flow active (`flow_contexts` where `completed_at IS NULL AND is_killed=false`)? |
| Flow stops at node X                    | `flow_contexts.node_uuid` == that node + `notifications` category='Flow' with matching `entity->>'node_uuid'`                                                                                                                     |
| Works in simulator/preview but not real | Simulator bypasses `can_send_message_to?` session check; real sends blocked by `bsp_status` gate                                                                                                                                  |
| Flow triggers but does nothing          | Node has no exits with destinations, or all router cases fail match. Check `flow_revisions.definition` for the node uuid                                                                                                          |

---

--- entry
section: 3.2
heading: 3. Contact Management › 3.2 Opt-in / Opt-out End to End
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

--- entry
section: 3.5
heading: 3. Contact Management › 3.5 Common Contact Issues
---

| Symptom                     | Check                                                                                                     |
| --------------------------- | --------------------------------------------------------------------------------------------------------- |
| Not receiving messages      | `optin_status`, `bsp_status`, `status`, and `last_message_at` (session)                                   |
| Shows as invalid            | `status=:invalid` → `optout_time` set, or error 1002 history, or provider rejection                       |
| Opted out unexpectedly      | Check `contact_histories` for `:contact_opted_out` event and `optout_method`                              |
| Field not resolving in flow | `contacts.fields->>'xxx'` missing → flow wrote label but never value, or flow path didn't reach the write |

---

--- entry
section: 4.6
heading: 4. Google Sheets Integration › 4.6 Common Sheet Failures Map
source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/
---

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

| User symptom                     | Likely cause                                              | DB/UI signal                                                     |
| -------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------- |
| "Sync failed" notification       | Google API error                                          | `sheets.failure_reason`, `sync_status=:failed`                   |
| "Unknown error or empty content" | Sheet tab has no rows under headers; or tab name mismatch | First sheet empty; `sheet_data_count=0`                          |
| "Repeated or missing headers"    | Two columns with same header, or a header cell is blank   | Fix the header row                                               |
| "No read access..."              | Service account not shared on the sheet                   | Share with `organization.services["google_sheets"]` client email |
| Auth errors                      | Credential JSON corrupt or rotated                        | `"Invalid Service Account JSON"` or `"Error fetching token..."`  |
| Sheet tab renamed/deleted        | gid in URL no longer resolves                             | `"Sheet with gid X not found"`                                   |
| Rate-limited by Google           | 429 surfaces as generic write error, message from Google  | `failure_reason` contains Google error body                      |

---

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
heading: 6. Webhooks — Complete Reference › 6A. Outgoing Webhooks ("Call Webhook" flow node)
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Call%20a%20webhook/

--- entry
heading: 6. Webhooks — Complete Reference › 6C. "Call a Function" Node › Async nodes and the resume path
---

The four async nodes acknowledge immediately, park the flow, and are resumed by a signed callback to `POST /webhook/flow_resume`. Their bodies must carry `organization_id`, `flow_id` and `contact_id` — `KaapiSupport.parse_flow_fields/1` rejects a missing or non-numeric one with `"Invalid or missing flow metadata for Kaapi webhook"`. STT additionally validates that `speech` is an `https` URL.

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
  "data": { "response": { ... } }
}
```

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Stripe webhook
---

Plug `GlificWeb.StripeWebhook` verifies via `Stripe.Webhook.construct_event/3` using `Application.fetch_env!(:stripity_stripe, :signing_secret)`. Handles `invoice.created/paid/failed`, `customer.subscription.*`, `customer.updated/deleted`.

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Exotel opt-in
source: https://glific.github.io/docs/docs/Integrations/Setting%20up%20Exotel/
---

📖 Source: https://glific.github.io/docs/docs/Integrations/Setting%20up%20Exotel/

`GET /webhook/exotel/optin?CallFrom=...&CallTo=...&To=...`. Looks up phone → flow_id in org creds, opt-in contact, starts configured flow.

--- entry
heading: 6. Webhooks — Complete Reference › 6B & 6F. Incoming Webhooks › Dify diagnose
---

`POST /dify/chatbot-diagnose` authenticated by header `x-dify-api-key` matching config.

--- entry
heading: 6. Webhooks — Complete Reference › 6D. Webhook Logs & Debugging
---

`webhook_logs` is the primary outgoing-webhook debug table. For incoming webhooks there's no single log table; failures appear in application logs and (for message events) in `messages.errors`.

--- entry
heading: 6. Webhooks — Complete Reference › 6D. Webhook Logs & Debugging › Signatures of outgoing webhook failures in `webhook_logs`
---

| Pattern                                                          | Diagnosis                                                                                |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `error` set, `status_code=400`                                   | Local error before the HTTP call (DNS, connection refused, timeout). Check `error` text. |
| `status_code=0` or null, `error` populated                       | Network / timeout                                                                        |
| `status_code=4xx`                                                | Auth, bad URL, bad body. Check `response_json`.                                          |
| `status_code=5xx`                                                | Server crashed. Check receiving server logs.                                             |
| `response_json=null`, `error="Could not decode message body..."` | Non-JSON response                                                                        |
| `status_code` in 200-299 but `response_json=null`                | Empty body returned                                                                      |

--- entry
heading: 6. Webhooks — Complete Reference › API to Start Flow Externally
---

GraphQL mutations (see §1.2): `startContactFlow`, `startWaGroupFlow`, `startGroupFlow`. Auth via user token scoped to org. No REST equivalent exists; external systems typically authenticate as a service user and call GraphQL.

---

--- entry
section: 7.5
heading: 7. Triggers & Scheduling › 7.5 Common Trigger Issues
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

| Symptom                       | Check                                                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Not firing                    | `is_active=true`; `next_trigger_at <= now()+1min`; `end_date` not passed                                               |
| Fires but flow doesn't start  | `flows.is_active=true`; latest `flow_revisions.status='published'`; group has contacts; contacts opted in / in session |
| Wrong fire time               | `start_at` in org timezone? `Helper.compute_next` uses Timex with org tz                                               |
| One-time trigger still active | `is_repeating=false` but not yet fired; after firing, is_active flips to false                                         |

---

--- entry
heading: 8. BigQuery Integration › 8.3 Worker Cadence — How Often Sync Runs › Quick answer
---

**Standard data lands in BigQuery every 2 minutes. Duplicate cleanup runs once a day at 23:58 UTC.**

--- entry
section: 8.4
heading: 8. BigQuery Integration › 8.4 Error Messages
---

| Status                    | Behavior                                              | Message                                            |
| ------------------------- | ----------------------------------------------------- | -------------------------------------------------- |
| `NOT_FOUND`               | Re-creates dataset/schema                             | `"Sync schema with bigquery"`                      |
| `PERMISSION_DENIED`       | Disables credential via `Partners.disable_credential` | From response body                                 |
| `TIMEOUT`                 | Logs and retries                                      | `"Timeout while inserting the data. {response}"`   |
| `ALREADY_EXISTS`          | Triggers schema refresh                               | —                                                  |
| `INVALID_SERVICE_ACCOUNT` | Fail hard                                             | `"Invalid Service Account JSON"`                   |
| `ERROR_FETCHING_TOKEN`    | Fail hard                                             | `"Error fetching token with Service Account JSON"` |
| INSERT_ERRORS             | Raises                                                | `"BigQuery Insert Error for table {table}"`        |

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
section: 9.5
heading: 9. Notifications System › 9.5 Mapping Notifications → Root Causes
source: https://glific.github.io/docs/docs/Product%20Features/Notifications/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Notifications/

| Notification message                                                     | Root cause                                            | Fix                                                         |
| ------------------------------------------------------------------------ | ----------------------------------------------------- | ----------------------------------------------------------- |
| `"Google sheet sync failed"`                                             | API error, bad headers, empty sheet                   | See §4.4 for exact sub-errors in `sheets.failure_reason`    |
| `"Could not send message: ... reason: ..."`                              | Session expired / opt-out / invalid bsp_status        | Check `contact.bsp_status`, `optin_time`, `last_message_at` |
| `"Template ... rejected"`                                                | Meta policy / invalid structure                       | Read `session_templates.reason`                             |
| `"Cannot send messages. WhatsApp phone X is not connected with Maytapi"` | Maytapi session died                                  | Reconnect phone in Maytapi dashboard                        |
| `"Disabling {shortcode}. {error}"`                                       | Credential invalid (BigQuery, Google Sheets, Gupshup) | Refresh/replace credential in Settings                      |
| `"Flow execution failed due to invalid regular expression"`              | Bad regex in case condition                           | Fix regex in flow editor                                    |
| `"Template expression is null in the flow"`                              | Template variable unresolved                          | Ensure prior node set the variable                          |
| `"New Ticket created"`                                                   | Flow created a ticket                                 | Route to support tool                                       |

---

--- entry
section: 10.3
heading: 10. Common Troubleshooting Decision Trees › 10.3 Sheet Not Syncing
source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/
---

📖 Source: https://glific.github.io/docs/docs/Use%20Cases/Solving%20For%20Sheet%20Sync%20Failures%20Issues/

```
SELECT * FROM sheets WHERE id=?
├── is_active=false → Enable.
├── sync_status=:failed → read failure_reason:
│   ├── "Unknown error or empty content" → Sheet tab empty or wrong tab referenced by gid.
│   ├── "Repeated or missing headers" → Duplicate or blank header in row 1.
│   ├── "No read access..." / "No edit access..." → Share sheet with service account email.
│   ├── "Google Sheet not found." → URL wrong or sheet deleted.
│   ├── "Invalid Service Account JSON" / "Error fetching token..." → Re-upload credentials.
│   └── "Sheet with gid X not found" → Sheet tab renamed or deleted.
├── sync_status=:success but old last_synced_at → Cron not running OR auto_sync=false.
└── No sheet row for this URL → Sheet not registered. Add in Settings → Google Sheets.
```

--- entry
section: 10.5
heading: 10. Common Troubleshooting Decision Trees › 10.5 Trigger Not Firing
source: https://glific.github.io/docs/docs/Product%20Features/Triggers/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Triggers/

```
SELECT * FROM triggers WHERE id=?
├── is_active=false →
│   ├── is_repeating=false AND last_trigger_at set → already fired once (expected).
│   ├── end_date passed → trigger expired.
│   └── Otherwise → manually disabled.
├── is_active=true → When was last MinuteWorker run?
│   ├── Check oban_jobs WHERE worker='Glific.Jobs.MinuteWorker' — recent completions?
│   ├── next_trigger_at in future → not yet matured.
│   └── next_trigger_at past + last_trigger_at recent + hourly → already fired this hour, waits next.
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
├── Check contact_histories for :contact_opted_out event
├── optout_method tells you what triggered it:
│   - "BSP" → user sent STOP in WhatsApp
│   - "Number does not exist" → error 1002 from provider
│   - "Glific Flows" → a flow action opted them out
│   - "Import" → CSV import set optout_time
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
│   ├── BSP webhook URL in provider dashboard correct?
│   ├── Glific server reachable (DNS, SSL, public)?
│   ├── BSP delivery logs show success to Glific endpoint?
│   ├── organization.is_active=true? (Shunt plug rejects non-active orgs)
│   └── Check Glific server logs for parse errors.
├── Messages appear but flow doesn't trigger →
│   ├── Another flow already active (flow_contexts incomplete)?
│   ├── Keyword didn't match exactly (full-message, case-insensitive)?
│   ├── Contact opted in?
│   └── See §1.2 priority order.
└── Messages appear, flow triggers, but webhook inside flow fails → See §10.8.
```

---

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
    signed = f"{timestamp}.{body_str}".encode()
    computed = hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()
    return hmac.compare_digest(computed, expected)
```

Secret = value of `organizations.signature_phrase` for the calling org. Default fallback: `"This is a dummy secret"`.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Gupshup (`/gupshup/*`, forwarded to `Providers.Gupshup.Plugs.Shunt`)
---

| Path                                           | Purpose           |
| ---------------------------------------------- | ----------------- |
| `POST /gupshup/message/text`                   | Inbound text      |
| `POST /gupshup/message/image`                  | Inbound image     |
| `POST /gupshup/message/file`                   | Inbound document  |
| `POST /gupshup/message/audio`                  | Inbound audio     |
| `POST /gupshup/message/video`                  | Inbound video     |
| `POST /gupshup/message/sticker`                | Inbound sticker   |
| `POST /gupshup/message/location`               | Inbound location  |
| `POST /gupshup/message/quick_reply`            | Quick reply       |
| `POST /gupshup/message/button_reply`           | Button reply      |
| `POST /gupshup/message/list_reply`             | List reply        |
| `POST /gupshup/message/whatsapp_form_response` | WA form response  |
| `POST /gupshup/message-event/enqueued`         | BSP accepted send |
| `POST /gupshup/message-event/sent`             | BSP confirms sent |
| `POST /gupshup/message-event/delivered`        | Delivered         |
| `POST /gupshup/message-event/read`             | Read              |
| `POST /gupshup/message-event/failed`           | Failed            |
| `POST /gupshup/user-event/opted-in`            | Opt-in            |
| `POST /gupshup/user-event/opted-out`           | Opt-out           |
| `POST /gupshup/billing-event/conversations`    | Billing           |

Auth: Shunt plug validates org active, sets root user context.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Maytapi (`/maytapi/*`)
---

| Path                                  | Purpose           |
| ------------------------------------- | ----------------- | ----- | ----- | ----- | --- | -------- | -------- | ------- | ----- | ---------------- |
| `POST /maytapi/message/text           | image             | video | audio | voice | ptt | document | location | sticker | poll` | Inbound messages |
| `POST /maytapi/message-event/handler` | Status events     |
| `POST /maytapi/status/status`         | Connection status |

Set webhook URL in Maytapi dashboard: `https://api.<shortcode>.glific.com/maytapi`.

--- entry
heading: 11. All Webhook Endpoints Reference › 11.2 Incoming (External → Glific) › Other
---

| Path                                 | Purpose                                               |
| ------------------------------------ | ----------------------------------------------------- |
| `POST /webhook/stripe`               | Stripe billing events (Stripe-signed)                 |
| `POST /webhook/flow_resume`          | Async flow resume (HMAC-SHA256 signed, 15-min window) |
| `GET /webhook/exotel/optin`          | Missed-call opt-in                                    |
| `POST /kaapi/knowledge_base_version` | KB creation callback                                  |
| `POST /kaapi/prompt_generation`      | Prompt-generation callback                            |
| `POST /kaapi/assistant_chat`         | Assistant-chat callback                               |
| `POST /kaapi/improve_prompt`         | Improve-prompt callback                               |
| `POST /kaapi/evaluation_run`         | AI-evaluation run callback                            |
| `POST /dify/chatbot-diagnose`        | Diagnostic (header `x-dify-api-key`)                  |

There is **no `/kaapi/voice_flow_resume`** route. Every async flow node — STT, TTS, `filesearch-gpt` and `voice-filesearch-gpt` alike — resumes through `POST /webhook/flow_resume`.

--- entry
section: 11.4
heading: 11. All Webhook Endpoints Reference › 11.4 Webhook Signing Summary
---

| Direction                      | Who signs       | Algorithm               | Header                              | Secret source                                     |
| ------------------------------ | --------------- | ----------------------- | ----------------------------------- | ------------------------------------------------- |
| Outgoing webhook               | Glific          | HMAC-SHA256             | `X-Glific-Signature: t=...,v1=...`  | `organizations.signature_phrase`                  |
| Incoming flow_resume           | External caller | HMAC-SHA256             | In body (`signature` + `timestamp`) | `organizations.signature_phrase`, 15-min window   |
| Incoming Stripe                | Stripe          | Stripe Webhook sig      | `Stripe-Signature`                  | Stripe signing secret in config                   |
| Incoming BSP (Gupshup/Maytapi) | —               | None beyond URL secrecy | —                                   | Org-specific URL path + org identifier in payload |

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
| ------- | --------------------- | ----------- |
| `success: true`, `webhook_log_id` present | `"Success"` | Success |
| `success: true`, no `webhook_log_id` | `"No Response"` | falls through the No Response category |
| `success: false` | `"Failure"` | Failure |

Note that the outcome is read from the parsed `response` **first**, falling back to the raw Kaapi `result` — so a failed TTS upload routes to Failure even though Kaapi itself reported success.

--- entry
section: 13.6
heading: 13. LLM & AI Integration › 13.6 WhatsApp 1024-char limit
---

No truncation in Glific code. The 1024-char limit is enforced by the BSP layer. LLM responses are sent through to Gupshup as-is. Long responses are either rejected by the BSP or split by the WhatsApp client — not by Glific. If chunking is required, do it inside the LLM's system prompt or a post-process webhook.

---

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
| --------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------- |
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
section: 15.6
heading: 15. WhatsApp Forms › 15.6 Common Form Failures
source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/WhatsApp%20Forms/

| Symptom                                  | Check                                                                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Draft won't publish                      | `meta_flow_id` null → Meta hasn't accepted form yet; check categories are from Meta's allowed list                        |
| Form loads but won't proceed past page 1 | Validation rule mismatch on a required field (Meta-side); inspect form JSON `data_api` and field `required` flags         |
| "Unauthorized access"                    | Partner token expired — see §16.3                                                                                         |
| Responses not arriving                   | Subscription for `FLOW_MESSAGE` not set, or webhook URL wrong in Gupshup — verify `POST /app/subscription` was successful |

---

--- entry
section: 16.2
heading: 16. Gupshup & BSP Integration › 16.2 Provider Shortcodes
---

| Shortcode              | Purpose                                 |
| ---------------------- | --------------------------------------- |
| `gupshup`              | Primary BSP — message sending, HSM, OTP |
| `maytapi`              | WhatsApp groups integration             |
| `open_ai`              | LLM calls                               |
| `gemini`               | LLM calls                               |
| `goth`                 | Google OAuth (for Sheets/Calendar)      |
| `google_cloud_storage` | Media storage                           |
| `bigquery`             | Data export                             |
| `google_slides`        | Custom certificates                     |
| `exotel`               | Missed-call opt-in callback             |
| `kaapi`                | Async LLM / STT / TTS dispatch          |

Note the Settings screen does **not** show all of these: `Glific.Partners.list_providers/1` excludes `goth`, `kaapi`, `gupshup_enterprise`, `navana_tech`, `google_asr`, `dialogflow` and `open_ai` (plus `google_cloud_storage` for trial orgs). There is no `bhashini` provider — Bhashini has been removed.

--- entry
section: 16.5
heading: 16. Gupshup & BSP Integration › 16.5 Error #131049
source: https://glific.github.io/docs/docs/FAQ/Check%20WhatsApp%20Quality%20Rating%20and%20Messaging%20Limits/
---

📖 Source: https://glific.github.io/docs/docs/FAQ/Check%20WhatsApp%20Quality%20Rating%20and%20Messaging%20Limits/

Not present in Glific source. This is a Meta / WhatsApp error code (quality-rating / spam) that arrives inside `messages.errors` JSON from the BSP. No internal Glific handler for it — it surfaces as-is.

--- entry
section: 17.6
heading: 17. Contact Variables & Expressions › 17.6 Dynamic Key Access
---

`@results.webhook.page_@contact.fields.index` is **not directly supported** — parser resolves `@contact.fields.index` first, then tries the literal `@results.webhook.page_<value>` path. The `<value>` becomes part of the key string. Works if `page_5` is a real key in the webhook results, not a nested structure.

--- entry
section: 17.7
heading: 17. Contact Variables & Expressions › 17.7 Initialize Blank Field
---

Set field to `""` via `set_contact_field`. No explicit "create blank" op; fields are created on first write.

---

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

Only lat/lon from pin drops are stored in `locations`. A typed address stays in `message.body` as plain text — **it is not parsed into coordinates**. To capture both, branch on `message.type == :location` in the flow and save text to a contact field when it's not.

--- entry
section: 22.5
heading: 22. WhatsApp Groups (Maytapi) › 22.5 Group vs Individual Differences
source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/WhatsApp%20Groups%20Automation%20Features/
---

📖 Source: https://glific.github.io/docs/docs/WhatsApp%20Groups%20Automation/WhatsApp%20Groups%20Automation%20Features/

| Aspect         | Individual                                     | Group                              |
| -------------- | ---------------------------------------------- | ---------------------------------- |
| Table          | `messages`                                     | `wa_messages`                      |
| Send endpoint  | Gupshup messages API                           | Maytapi `/sendMessage`             |
| BSP status set | `:sent` \| `:delivered` \| `:read` \| `:error` | `:enqueued` \| `:sent` \| `:error` |
| Rate limits    | Gupshup WABA tier                              | Maytapi plan                       |

--- entry
section: 22.6
heading: 22. WhatsApp Groups (Maytapi) › 22.6 Daily Group-Creation Limits
---

**None in Glific code.** Maytapi enforces (typical: 50 groups/day/phone). Check Maytapi dashboard for per-phone caps.

---

--- entry
section: 23.4
heading: 23. Platform & Login › 23.4 Staff Deletion
source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Others/Staff%20Management%20%26%20Role%20Management/

**There is no automatic staff deletion.** Only orgs have soft-delete (`organizations.deleted_at`). Users are deactivated by assigning `roles: [:none]`. A "staff account automatically deleted" report is usually an org-level deactivation (the user still exists; just their org is deleted).

--- entry
section: 24
heading: 24. Contacts & Collections — Deep Dive
---

(Complements §3. Read §3 first.)

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
section: 24.6
heading: 24. Contacts & Collections — Deep Dive › 24.6 Why "hi" from an existing user sometimes re-triggers opt-in
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Others/Configure%20Optin%20%26%20Optout%20preferences%20in%20Glific/

`start_optin_flow?` returns true when contact's `optin_time` is nil **or** BSP session is closed AND the incoming body matches an opt-in keyword. Flow authors who use "hi" as both the opt-in trigger and a menu keyword will see this overlap. Fix: change opt-in keyword or check `optin_time != nil` earlier in the opt-in flow.

--- entry
section: 24.8
heading: 24. Contacts & Collections — Deep Dive › 24.8 API Update Collection
---

GraphQL `updateGroup(input: {id, label, description, isRestricted})` → `Groups.update_group/2`. Validates unique `(label, organization_id)` tuple. Any label collision returns a changeset error.

---

--- entry
section: 25.6
heading: 25. Flow Builder Advanced Features › 25.6 Broadcast / Bulk Send
source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20a%20staff%20member%20a%20message/
---

📖 Source: https://glific.github.io/docs/docs/Product%20Features/Flows/Flow%20Actions/Send%20a%20staff%20member%20a%20message/

See §24.3. Important knobs:

- `@contact_chunk = 1000` (hard-coded).
- `MessageBroadcast` rows are the source of truth for broadcast progress — query `SELECT COUNT(*) FROM messages WHERE message_broadcast_id = X GROUP BY bsp_status` to see delivery distribution.
- Message ordering within a contact is preserved; across contacts it's concurrent.
