<!--
  This file is inlined verbatim into a cached system prompt (Glific.AI.Skills.AskGlific,
  loaded by Glific.AI.KnowledgeBase). Editing it changes both the cost and the behaviour of
  every "Ask Glific" answer, across every tenant, until the app is recompiled and redeployed.

  Do not put organisation-specific or personal data here — this content is shared, verbatim,
  across every organisation on the platform. Keep each section short and headed with `##` so
  it stays skimmable and so a future search tool can match on headings.
-->

## What is a flow?

A flow is the automated conversation Glific runs with a contact on WhatsApp. It is built as a
sequence of nodes in the Flow Editor: a message to send, a question to ask, a condition to
branch on, a wait for a reply, or an action like adding the contact to a collection or
webhook call. A contact enters a flow either because they sent a keyword the flow is
configured to trigger on, because staff started the flow for them or for a collection, or
because another flow or a schedule (a trigger) started it for them.

While a contact is inside a flow, Glific keeps a record of exactly where they are — which node,
waiting for what — so that when they reply, the flow can pick up from that point rather than
starting over. A contact can only be in one flow at a time by default, unless a flow is marked
to run in the background.

## Session messages vs template messages, and the 24-hour window

WhatsApp only allows a business to freely send any message to a contact within 24 hours of that
contact's last message. A message sent inside that window is a **session message** — plain
text, buttons, images, anything.

Once 24 hours pass since the contact's last message, a business can no longer send a session
message. To reach the contact again, it must send a **template message** (also called an HSM —
Highly Structured Message) that Meta pre-approved. This is why a contact who has gone quiet can
only be re-engaged with an approved template, never with an ordinary flow message.

## HSM / templates and Meta approval

A template (HSM) is a message with fixed wording and optional variable placeholders (like
"Hi {{1}}, your appointment is on {{2}}") that must be submitted to Meta for approval before it
can ever be sent. Meta reviews the wording and assigns it a category — most importantly
**UTILITY** (transactional: confirmations, updates, reminders about something the recipient
already started) or **MARKETING** (promotional: new offers, invitations, announcements).
A template stuck in "pending" simply means Meta has not reviewed it yet; a "rejected" template
usually means the wording reads as promotional, requests something new from the recipient, or
does not match its declared category, and needs to be edited and resubmitted.

## Opt-in and opt-out

A contact must opt in before an organisation can message them outside the 24-hour session
window, and Meta requires this consent to be collected and recorded. In Glific, a contact's
opt-in status, and the time and method they opted in (for example, by messaging first, or
through an opt-in flow), are tracked on the contact record. A contact who opts out (for
example, by replying STOP, or through an explicit opt-out flow) is recorded with an opt-out
time and can no longer be sent template messages until they opt in again. Staff should always
check a contact's opt-in status first when a template send is failing or a contact says they
are not receiving messages.

## Contact fields and groups

A contact field is a piece of information stored against a contact beyond the built-in ones
like name and phone — for example, a preferred language, a location, or an enrolment status
that a flow collected from their answers. Flows read and write contact fields to personalise
messages and to make branching decisions later in the same or a different flow.

## Collections

A collection is a named group of contacts (in Glific's own terms, sometimes called a "group"
in the underlying data, but always shown to staff as a "collection"). Collections are used to
target a broadcast or a flow at many contacts at once, to organise contacts by programme or
cohort, and to control who staff members with restricted access can see and message.

## Contact stuck in a flow — first things to check

When staff say a contact is "stuck" and not getting the next expected message, the flow has
usually not failed silently — it is waiting on something. The first things to check are:

1. **Is the contact actually still inside the flow?** If they are not, a different flow or a
   keyword may have taken over.
2. **Is the flow waiting for a reply that does not match what it expects?** Flows often wait
   for a specific keyword, a menu option number, or an answer in a specific format; a reply
   that does not match can leave the contact waiting indefinitely or trigger a default/failure
   branch.
3. **Has the 24-hour session window closed?** If the flow is waiting to send the contact a
   session message and more than 24 hours have passed since the contact last wrote in, that
   message cannot go out until the contact writes in again.
4. **Did an external step in the flow fail?** A webhook call, a certificate step, or another
   integration that the flow depends on can leave a contact waiting if that external step
   never returned a result.
5. **Is the organisation's WhatsApp number or BSP connection healthy?** If the underlying
   provider connection is down or the number is suspended, no messages go out at all.

## BSP and Gupshup

BSP stands for Business Solution Provider — the company that connects Glific to the actual
WhatsApp Business Platform, since organisations cannot connect to WhatsApp directly. Gupshup is
the most common BSP that Glific organisations use. All outbound and inbound WhatsApp messages
pass through the BSP: outbound messages are sent through its API, and incoming messages and
delivery/read status updates arrive from it as webhooks. If messages are not sending or
statuses are not updating, the BSP connection and credentials are usually the first thing to
check, after confirming the contact's opt-in status and the 24-hour window.
