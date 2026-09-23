# Ranking Guide

📖 Source: https://example.test/docs/ranking-guide/

A fixture corpus. It exists so the ranker can be measured without asserting on
the wording of the shipped documentation, which changes for reasons that have
nothing to do with search.

## Opt-in

### Opt-in lifecycle

📖 Source: https://example.test/docs/optin-lifecycle/

How a contact moves from unknown to opted in, and what each status means along
the way. Covers the keyword, the confirmation and the record written when the
contact replies.

### Registration walkthrough

A section that discusses opt-in repeatedly in its body without naming it in the
heading. Opt-in is mentioned here, and opt-in again, so that body overlap alone
is high. It exists so that a heading match can be measured against a body-only
match for the same term.

## Templates

### Common HSM template errors

📖 Source: https://example.test/docs/hsm-errors/

What the provider rejects an HSM for, and what each rejection means. Variable
count mismatches, unapproved categories and language codes that do not match
the template body.

### Limits and constraints

The general ceilings that apply across the product. Character counts, file
sizes and the number of buttons an interactive message may carry.

## Notation

### Using @results.category in a flow

📖 Source: https://example.test/docs/results-category/

The value a router wrote, available to every node after it. Written as
`@results.<name>.category` where the name is the one given on the node.

## Length

### Short specific section

Webhook timeout.

### Webhook timeout reference

This section ties exactly with the one in the other document: both headings
carry webhook and timeout, so both score the same on heading matches and on
body overlap. It is deliberately the longer of the two, and it is read first
because its file sorts first, so without a tie break it would always win. It
goes on at some length about webhooks and timeouts and retries and flows and
contacts and collections without ever being more specific than the short
section, which is precisely the case the tie break exists to decide.

It also runs past the body cap on purpose. A section in the shipped corpus can
reach twelve kilobytes, and the tool tells the model that two or three searches
cost almost nothing, so an uncapped body is the difference between a search
that costs a few hundred tokens and one that costs several thousand. Repeating
the point at length: a webhook that times out leaves the flow with nowhere to
go, the contact waits at the node, and the only evidence is a log line with a
status code and an error. None of that needs twelve kilobytes to say, and a
section that takes twelve kilobytes to say it is exactly the section a cap
should cut. Flows, contacts, collections, templates, triggers, broadcasts,
webhooks, sheets, notifications and forms all appear in this paragraph purely
to make it long enough that the cap has something to do, because a fixture that
never exceeds the limit tests nothing at all and would let someone remove the
cap without a single test noticing. One more sentence, then, so that the body
comfortably clears fifteen hundred bytes and the cap has to engage rather than
merely being configured, because a limit that never fires is indistinguishable
from no limit at all to every test that might otherwise have caught it.

### Long general section

This section is deliberately long so that a tie on score is broken by length.
It repeats the same general material at length without ever becoming more
specific about any single topic, which is the behaviour a reader would want
ranked below a short section that answers the question directly. It mentions
webhook and timeout among many other words, so it ties on body overlap with
the short section above while carrying far more text around them. Flows,
contacts, collections, templates, triggers, broadcasts and webhooks all appear
here, which is exactly what makes a long general section score well without
being useful. The ranker should prefer the shorter, more specific section when
the two are otherwise equal, because a shorter section wastes less of the
context window and is more likely to be about the thing that was asked.
