# Standards reference

What the published frameworks say, how this skill's 0–4 scores map onto them, and how to
cite them without overclaiming.

## Contents

- [How to cite](#how-to-cite)
- [CSA AISMM and AICM](#csa-aismm-and-aicm)
- [OWASP Top 10 for Agentic Applications](#owasp-top-10-for-agentic-applications)
- [NIST SP 800-207 and 207A](#nist-sp-800-207-and-207a)
- [EU AI Act](#eu-ai-act)
- [Architecture patterns](#architecture-patterns)
- [Capability context](#capability-context)
- [Dimension to control mapping](#dimension-to-control-mapping)

---

## How to cite

Cite the standard **by name and organisation**, and the control **by ID only when you are
sure of the ID**. An invented control ID is worse than no ID: it is the kind of error that
makes a reader discard the whole assessment, and it is easy to make because these
frameworks were all published or revised between late 2025 and mid 2026.

When a figure from an incident or a report appears in an assessment, treat it as needing a
primary source. The numbers in this file are recorded from secondary summaries and are here
for orientation, not for quotation in anything external.

Two claims are safe to make without a citation because they are visible in the repo: what
the code does, and what CI enforces. Prefer those. An assessment grounded in the reader's
own codebase does not need borrowed authority.

---

## CSA AISMM and AICM

The Cloud Security Alliance publishes two complementary artefacts:

- **AI Controls Matrix (AICM)** — a controls catalogue, aligned to ISO 42001 and the NIST AI
  RMF, with per-deployment-pattern applicability (self-hosted, PaaS, API/SaaS). Answers
  *which controls should exist for this deployment*.
- **AI Security Maturity Model (AISMM)** — five maturity levels across twelve practice areas
  in three domains, mapped to AICM. Answers *what the programme looks like at each stage*.
  Published May 2026. Commentary treats Level 3 as the practical minimum for regulated
  deployment.

### Level mapping

This skill scores 0–4 per dimension. AISMM numbers its levels 1–5. The mapping:

| This skill | AISMM | Shorthand |
|-----------|-------|-----------|
| 0 | below 1 | Absent — the control does not exist and the exposure is reachable |
| 1 | 1 | Ad hoc / initial |
| 2 | 2 | Defined — a documented, consistent pattern |
| 3 | 3 | Enforced — departures fail the build or the deploy |
| 4 | 4–5 | Measured and improving — monitored, with a tested response path |

Two deliberate differences from AISMM, worth stating in any report that cites it:

1. AISMM assesses an enterprise **programme**. This skill assesses a **codebase and its
   deployment**. A team can score well here and still lack the governance AISMM measures,
   and the report should not imply otherwise.
2. This skill reports the **weakest link**, where maturity models usually roll up to an
   average. An average is the right instrument for tracking a programme over time and the
   wrong one for deciding what an attacker would use.

Glific's relevant deployment pattern is mostly **API/SaaS** for model access (OpenAI,
Gemini, Kaapi) with self-hosted application infrastructure — so AICM controls scoped to
model training and hosting largely do not apply, and saying so is a legitimate part of the
assessment rather than a gap.

---

## OWASP Top 10 for Agentic Applications

Published 9 December 2025 by the OWASP GenAI Security Project, developed with more than 100
contributors. IDs run `ASI01`–`ASI10`. It extends, and does not replace, the OWASP GenAI/LLM
Top 10 (2026 edition), which covers model-layer risks.

| ID | Risk | Short form |
|----|------|-----------|
| `ASI01` | Agent Goal Hijack | Adversary redirects the agent's plan or objective |
| `ASI02` | Tool Misuse | Tools invoked in ways they were not authorised for |
| `ASI03` | Identity & Privilege Abuse | Agent identity or permissions misused or escalated |
| `ASI04` | Agentic Supply Chain | Third-party tools, frameworks, registries, components |
| `ASI05` | Unexpected Code Execution | Agent or sandbox boundary fails, arbitrary code runs |
| `ASI06` | Memory & Context Poisoning | Persistent memory, retrieval or context shaped to mislead |
| `ASI07` | Insecure Inter-Agent Communication | Messages spoofed, replayed, unauthenticated |
| `ASI08` | Cascading Failures | One agent's error or compromise fans out |
| `ASI09` | Human-Agent Trust Exploitation | Humans over-trust or are deceived by agent output |
| `ASI10` | Rogue Agents | Agents operating outside intended bounds |

The framing in the commentary: `ASI01` is the failure state, and the other nine are routes
to reaching it.

A related OWASP MCP Top 10 covers protocol-layer risks; tool poisoning is `MCP03`, grouped
with rug pulls and tool shadowing. Use it when assessing `glific-mcp` specifically.

---

## NIST SP 800-207 and 207A

**SP 800-207** is the zero trust architecture baseline: verify explicitly, enforce least
privilege, assume breach. **SP 800-207A** is the one to cite for agents, because it
addresses non-person entities — which now includes agents, inference workers and automated
pipelines.

NIST has been soliciting input for a demonstration project applying 800-207 to agent use
cases, with MCP, OAuth 2.0/2.1, OpenID Connect and SPIFFE/SPIRE among the standards in
scope. CSA's Agentic Trust Framework (February 2026) is the agent-specific governance layer
built on the same principles.

The practical content, consistent across all of them, and the thing worth checking in code:

- one identity per agent, never a shared API key or a borrowed human credential
- authenticate per request, authorise least-privilege per tool call, log every action
- sub-agent delegation stays minimal, short-lived, and traceable to the original approved task
- every agent catalogued with an owner, a scope and a lifecycle
- revocation is event-driven, because periodic review misses identities created and
  destroyed between cycles

---

## EU AI Act

High-risk obligations became binding **2 August 2026**. Relevant articles:

| Article | Subject | Why it matters here |
|---------|---------|---------------------|
| 9 | Risk management system | Continuous, not a one-off assessment |
| 10 | Data governance | Includes inference-time protections |
| 12 | Logging | Feeds dimension 08 |
| 14 | Human oversight | Feeds dimension 09 |
| 15 | Accuracy, robustness, cybersecurity | Resilience across the **action layer**, not only model output |
| 26 | Deployer obligations | Applies when using someone else's high-risk system |

Article 15 is the one security engineers should read. If agents invoke APIs, that action
layer is in scope for the cybersecurity and logging mandates, and in a multi-agent
architecture the compliance boundary extends to every agent performing a high-risk function.
Penalties for high-risk non-compliance reach €15M or 3% of global turnover.

Whether Glific's use is high-risk is a legal determination, not one this skill makes. Note
the exposure and route the question to someone who can answer it. Glific's social-sector
deployments touching education, health messaging and public services are the cases most
likely to matter.

---

## Architecture patterns

### The lethal trifecta

Simon Willison's framing (2025): access to private data, exposure to untrusted content, and
the ability to communicate externally. Any two are survivable. All three, and a single
poisoned input can exfiltrate with no bug in the code. It explains nearly every
prompt-injection exploit on record. The design response is to remove a leg per integration
rather than to filter harder — filtering is a probabilistic control on an adversarial input.

### The six design patterns

From *Design Patterns for Securing LLM Agents against Prompt Injections*. Each trades
autonomy for assurance in a different proportion:

| Pattern | What it does | Cost |
|---------|-------------|------|
| Action-selector | Agent picks from a fixed action set; almost no injection surface | No open-ended behaviour |
| Plan-then-execute | Plan fixed before untrusted content is read | Cannot adapt mid-task |
| LLM map-reduce | Untrusted items processed in isolation, results aggregated | More calls |
| Dual-LLM | Privileged model holds tools and never sees raw untrusted content; quarantined model reads it, has no tools, returns typed values | Two models, typed channel |
| Code-then-execute | Model emits code reviewed or constrained before running | Needs a sandbox |
| Context-minimisation | Untrusted content dropped from context once used | Loses history |

CaMeL operationalises dual-LLM; CaMeL and FIDES both attach metadata to values and enforce
data- and control-flow policy in **deterministic code** rather than in the model's
probability distribution. That is the line worth holding in a review: a control you cannot
express as code is not a control.

The literature is explicit that every one of these patterns leaves something open. They
reduce blast radius; none makes an agent safe to hand production credentials.

---

## Capability context

Useful for explaining *why* these dimensions are scored more strictly than they would have
been two years ago. Treat the figures as orientation needing primary confirmation.

- UK AISI's assessment of Claude Mythos found it was not dramatically more capable than
  prior frontier models on individual cyber tasks, but was the first to autonomously chain
  them into an end-to-end intrusion. The threshold that mattered was chaining, not
  difficulty — which is why dimension 09 (stop capability) carries more weight than its
  effort suggests.
- METR measures the task length a generalist agent completes at 50% reliability as doubling
  roughly every 7 months over six years, and roughly every 4 months across 2024–25. UK AISI
  puts the 80%-reliability *cyber* time horizon at doubling every 4.7 months since late 2024.
- Practical consequence for this assessment: a control sized to today's agent horizon has
  a shelf life of months. Recommend a re-run cadence, not a one-off score.
- On AI-assisted code: the 2026 Veracode GenAI Code Security Report puts the average
  security pass rate around 56%, roughly unchanged from 55% in its first edition, while
  syntax correctness exceeds 95%. Those rates are measured when no security guidance is
  given in the prompt — which is why standing repo instructions (`CLAUDE.md`) count as a
  control worth crediting in dimension 05.

---

## Dimension to control mapping

For the report's mapping column.

| # | Dimension | OWASP ASI | Other |
|---|-----------|-----------|-------|
| 01 | Secret handling | `ASI03` | AICM identity & data domains |
| 02 | Identity & least privilege | `ASI03` | NIST SP 800-207A |
| 03 | Trust zones | `ASI05`, `ASI02` | AICM infrastructure |
| 04 | Authorization enforcement | `ASI03` | AICM application |
| 05 | Agent & tool surface | `ASI01`, `ASI02`, `ASI06`, `ASI07` | Lethal trifecta; design patterns |
| 06 | Egress control | `ASI02`, `ASI05` | NIST SP 800-207 |
| 07 | Supply chain | `ASI04` | OWASP MCP Top 10 (`MCP03`) |
| 08 | Audit integrity | `ASI08`, `ASI10` | EU AI Act Art. 12 |
| 09 | Stop capability | `ASI10` | EU AI Act Art. 14 |
| 10 | Detection | `ASI09`, `ASI10` | AICM monitoring |
