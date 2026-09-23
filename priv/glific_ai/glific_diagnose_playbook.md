# Glific Diagnose Playbook

What to look at when someone reports that something is not working, and what
each result means. Every recipe names the tool to call and the fields that
come back from it.

Two rules that apply to all of them. Check what the person actually said
before assuming the failure is where they think it is — "the flow is broken"
is usually one contact, one template or one webhook. And a result that comes
back empty is not proof that nothing is wrong: it is equally often the wrong
filter.

## Complaint recipes

### My flow is not running / the flow stopped triggering

Call `list_flows` with the name, then `get_flow` on the id it returns.

- `is_active` is `false` — somebody switched the flow off. This is the most
  common answer and the easiest to miss.
- `list_flows` returns nothing for that name — the flow was renamed or never
  existed. Search a shorter fragment before concluding it is gone.
- `get_flow` with `status: "published"` finds no revision — the flow exists
  only as a draft. Edits in the flow editor do nothing until published.
- `last_changed_at` is recent but the published revision is old — they made
  edits and did not publish them. People report this as "my changes did
  nothing".
- The flow is meant to run on a schedule — check `list_triggers` as well,
  because a live flow with a dead trigger looks identical from the outside.

### A contact did not get the message / why did this number not receive it

Call `get_contact` with the phone number and
`include: ["messages", "history"]`.

On the contact itself:

- `optin_status` is `false`, or `optout_time` is set — they opted out and
  cannot be messaged until they opt in again.
- `bsp_status` is `"none"` — no open session and no template was sent. The
  24-hour window has closed.
- `bsp_status` is `"hsm"` — only a template will reach them; a session
  message will not.
- `status` is `"invalid"` or `"blocked"` — the number is not reachable on
  WhatsApp at all, regardless of opt-in.
- `last_message_at` is days old — consistent with an expired session.

In `messages`:

- `status` is `"error"` and `errors` is populated — read `errors`, it carries
  the provider's own wording.
- `bsp_status` disagrees with `status` — Glific accepted the send and the
  provider rejected it afterwards.
- No messages at all — nothing was ever queued. The flow did not reach the
  send node, or the template was not approved.
- `status` stays `"enqueued"` — the send is stuck before the provider.

In `history`, `event_type` and `event_label` show opt-outs and flow entries
in order, which is how to tell "never entered the flow" from "entered and
failed".

### My Google Sheet is not syncing

Call `list_sheets`.

- `is_active` is `false` — disabled.
- `sync_status` is a failure and `failure_reason` is populated — the reason
  is the answer; quote it.
- `last_synced_at` is days old with no failure recorded — the sync is not
  running rather than failing.
- `sheet_data_count` is 0 on a sheet that should have rows — the sheet is
  reachable but the range or the header row is wrong.

Sheet syncs are daily, so widen the window before deciding it is broken.

### My webhook is not firing

Call `list_webhook_logs`, filtered by `url` or `status_code`.

- `status_code` is 0 or absent and `error` is set — it never reached the
  remote server. Network, DNS or timeout.
- `status_code` is 4xx — the request arrived and was refused. Wrong URL,
  missing auth, or a malformed body.
- `status_code` is 5xx — the remote server failed. Not a Glific problem, but
  the flow still stops.
- No rows at all for that flow — the flow never reached the webhook node.
  Diagnose the flow, not the webhook: `get_flow` with
  `include: ["contacts"]` shows who is sitting in it and where.

A webhook that returns 2xx but the wrong shape will not appear as a failure
here; the flow will simply carry on with nothing in the result.

### A scheduled flow did not start / the trigger did not fire

Call `list_triggers`.

- `is_active` is `false` — disabled.
- `next_trigger_at` is in the past — the run was missed rather than skipped.
- `last_trigger_at` is older than the `frequency` implies — the trigger has
  not been firing for a while, not just this once.
- `start_at` is in the future — it has not begun yet, which reads to the
  person as "not working".

### My template is not going out

Call `list_templates` with `is_hsm: true`.

- `status` is not `"APPROVED"` — it cannot be used yet. `"PENDING"` means
  waiting on Meta; `"REJECTED"` means it must be fixed and resubmitted.
- `is_active` is `false` — approved but switched off.
- The template is not in the list — it was never created in this
  organisation, or it is an interactive template rather than a session one.

Then `get_contact` with `include: ["messages"]` on someone who should have
received it. Messages with `is_hsm` true and `errors` populated carry the
send-time failure, which is usually a mismatch between the number of
variables the template expects and the number the flow supplied.

The rejection reason Meta gave is not returned by the tool. Say the template
is rejected, and point the person at the Templates screen to read why.

### The notifications page is empty

Call `platform_health`. An empty notification list has two readings that look
identical: nothing has failed, or nothing is being recorded. Check the
`providers` list in the same result — a credential with `is_valid` false is a
real fault that would normally have produced notifications.

### A contact is not opting in

Call `get_contact` with `include: ["messages", "history"]`.

- `optin_status` is already `true` with `optin_time` set — they are opted in,
  and the complaint is about something else.
- `status` is `"blocked"` or `"invalid"` — opt-in cannot succeed.
- No inbound messages at all — their reply never reached Glific, which points
  at the provider rather than the flow.
- `history` shows an opt-out shortly after an opt-in — they opted out again.

### A flow is stuck partway through

Call `get_flow` with `include: ["contacts"]` to see who is in the flow and at
which node.

- Contacts sitting at the same node for a long time — the flow is waiting on
  a reply that will not come, or on a webhook that never returned.
- `list_webhook_logs` shows a non-2xx for that flow around the same time —
  the webhook failed and the flow has nowhere to go.
- `get_contact` on one of them, with `include: ["messages"]`, shows whether
  the last send failed.

### A broadcast did not reach the collection

Call `list_broadcasts` with `include: ["contacts"]`.

- `completed_at` is empty long after `started_at` — the broadcast started and
  stalled.
- Many contacts with `processed_at` empty — they were never attempted.
- A cluster of contacts with an error `status` — they were attempted and the
  provider refused. Check the template and the 24-hour window before blaming
  the broadcast.

### Something is broken but they have not said what

Do not go looking through every tool. Call `platform_health` first: it
returns the provider credentials, recent notifications and the BigQuery job
state together, which is usually enough to name the area. Then ask one
specific question rather than guessing.

## Notification categories that exist

Filtering on a category that is never written returns an empty list, which
reads as "nothing is wrong" when it means "wrong filter". The categories
actually used are:

`Message` · `Flow` · `Templates` · `HSM template` · `Partner` · `Ticket` ·
`Contact Upload` · `Custom Certificates` · `Google sheets` · `Organization` ·
`Assistant` · `AI Evaluation` · `WA Group` · `WA Group Member Upload` ·
`WhatsApp Groups` · `WhatsApp Forms`

There is no `Trigger`, `Webhook`, `Contact` or `Collection` category. Trigger
and webhook problems surface under `Flow`, if they surface at all — for those
two, read `list_triggers` and `list_webhook_logs` directly instead.

## What not to conclude

- An empty result is not an answer. Say what was searched for and widen the
  filter before reporting that nothing exists.
- A flow that is active is not necessarily published, and a published flow is
  not necessarily the version they edited.
- A message recorded as sent is not a message delivered; `bsp_status` is the
  provider's view and it can disagree with `status`.
- A contact who can be looked up is not necessarily reachable — opt-in status
  and session state both have to hold.
- One contact failing is not the same as the feature failing. Check a second
  contact before generalising, and check the template before blaming the
  flow.
