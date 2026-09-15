# Flows on the web channel (#5719)

A map of the changes in this PR. Read this first if the diff looks scattered — it isn't; it is
one idea applied at every doorway a flow can open.

## The one idea

> **Decide the channel once (at the entry), stamp it onto the flow's context row, and inherit it
> everywhere after — never re-derive it. Every operation that touches a contact's flow state
> filters by that channel.**

A contact is shared across channels, but each channel keeps its **own** `flow_context` row,
distinguished by the `channel` column. So one contact can be mid-flow on WhatsApp *and* mid-flow
on the web widget at the same time, and neither disturbs the other.

## Three jobs (every change fits in one bucket)

| Bucket | Question it answers | Where the code lives |
|--------|--------------------|----------------------|
| **1. INLET** | How does a web message *get into* the flow engine? | `Communications.WebMessage`, `Processor.MessageWorker` |
| **2. STATE** | How do web & WhatsApp flows *not collide* for one contact? | `Flows.FlowContext` (+ all callers) |
| **3. OUTLET** | How does a reply *go back out* on the right channel? | `Flows.ContactAction`, `Communications.Message`, `Providers.Web.Message` |

## Lifecycle: many entry points, one fork

```
                      ENTRY POINTS  — each decides or carries a channel
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │ inbound WEB msg      inbound WA msg     staff "start flow"    periodic / cron   │
 │ WebMessage           Gupshup           start_contact_flow    Periodic          │
 │ channel=:web         channel=:whatsapp channel opt(def :wa)  channel=msg.chan  │
 └──────┬───────────────────┬───────────────────┬──────────────────┬─────────────┘
        │                   │                    │                  │
        ▼                   ▼                    ▼                  ▼
   MessageWorker      MessageWorker         Broadcast          ConsumerFlow
        └───────┬───────────┘             .broadcast_contacts  .run_flows
                ▼                                │                  │
        ConsumerFlow.process_message ───────────┴──────────────────┘
                │   reads message.channel
                ▼
   ┌─────────────────────────────────────────────────────────────┐
   │  FlowContext  (channel stamped on the ROW)                    │
   │   • active_context(id, channel:)   ← find only THIS channel   │◄─ also entered by:
   │   • init_context(..., channel:)    ← create + complete-prev   │   • sub-flow (start_sub_flow)
   │   • mark_flows_complete(channel:)  ← complete only this chan  │   • optin (start_optin_flow)
   │   • wakeup_one / reset_all_contexts← resume/reset this chan   │   • resume (wait / TTS webhook)
   └───────────────────────────┬─────────────────────────────────┘
                               ▼
                    flow runs → a "send message" node
                               ▼
        ContactAction   attrs = %{ ..., channel: channel_for(context, cid) }
                               ▼
        Messages.create_and_send_message
                               ▼
        message_handler(%Message{channel})     ◄────  THE ONE DECISION POINT
             ┌─────────────────┴──────────────────┐
        channel == :web                        anything else
             ▼                                      ▼
   Providers.Web.Message                   Providers.Gupshup.Message
   → Phoenix PubSub → WebSocket → browser  → HTTP API → WhatsApp → phone
```

Many arrows in at the top converge on the `flow_contexts` row (which now carries `channel`), the
flow runs, and everything funnels down to **one fork** — `message_handler/1` — the only place
that decides web-vs-BSP.

## Isolation: why two channels don't conflict

```
Contact X  (one contact, shared across channels)
 ├─ flow_context { channel: :whatsapp, node: N1 }   ← advanced ONLY by WA messages
 └─ flow_context { channel: :web,      node: M1 }   ← advanced ONLY by web messages

 every find/complete/resume/reset call carries `channel:` →
   a :web operation cannot see or touch the :whatsapp row, and vice versa
```

## Entry points and the one-line change at each

A flow can start or advance from several places. Each now carries the channel instead of
defaulting:

| Entry point | Function | What changed |
|-------------|----------|--------------|
| Web inbound reaching the engine at all | `WebMessage.hand_to_flow_engine` | enqueue `MessageWorker` (flag-gated) — the INLET that did not exist before |
| Inbound msg (keyword / mid-flow reply) | `ConsumerFlow.process_message` → `start_new_flow` | thread `message.channel` into `init_context` / `active_context` / `mark_flows_complete` |
| Sub-flow (`enter_flow` node) | `Flow.start_sub_flow` | inherit `context.channel` |
| Optin flow | `ConsumerFlow.start_optin_flow` | inherit `message.channel` |
| Periodic (default / out-of-office / weekday) | `Periodic.init_common_flow` | inherit `message.channel` |
| Staff-initiated | `Flows.start_contact_flow` → `Broadcast.broadcast_contacts` | optional `:channel` opt (default `:whatsapp`) |
| Resume (wait-for-time, async TTS webhook) | `FlowContext.wakeup_one` | complete newer contexts scoped by `channel` |
| Error reset | `FlowContext.reset_all_contexts` | scope the tree completion by `channel` |

## Two invariants to remember

1. **STATE side:** anything that queries or completes a contact's contexts filters by `channel` —
   `active_context`, `init_context`, `mark_flows_complete`, `wakeup_one`, `reset_all_contexts`.
   That is what keeps the two rows above from colliding.
2. **OUTLET side:** the outbound message's `channel` is copied from `context.channel` (or
   `:whatsapp` for a cross-contact broadcast via `ContactAction.channel_for/2`), and
   `Communications.Message.message_handler/1` is the single fork that turns that into
   "socket vs BSP".

## The gotcha behind most of the review churn

The default is `:whatsapp`. Any entry point that *forgets* to pass the channel silently starts a
`:whatsapp` flow — so a web contact would receive a WhatsApp message (a leak). Most of the later
commits were "found another entry point that was not inheriting the channel": the same one-line
fix, different doorways.

## Deliberate non-goals

- **`send_at` pacing on web** is not honoured — `Providers.Web.Message` delivers immediately.
  Inline delivery keeps bubbles strictly ordered, and prompt delivery suits a live browser chat
  (WhatsApp's inter-bubble pacing is a BSP concern). Pacing is a follow-up.
- **Templates on web** are refused, not rendered — a template needs a BSP, so
  `check_for_hsm_message`'s `:web` clause returns an error rather than leaking the body over
  WhatsApp.
- **Oban queue** — web inbound shares `gupshup_inbound` for now; a dedicated queue is deferred
  until web traffic warrants it.
