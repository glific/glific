---
name: assess-ai-security-maturity
description: >-
  Score this codebase's AI/agent security maturity against CSA AISMM levels and
  OWASP Top 10 for Agentic Applications, using evidence read out of the source,
  CI config, container and deploy files — never a questionnaire. Produces a
  per-dimension level, a weakest-link overall rating, and the highest-leverage
  fixes with file:line citations. Use when the user asks for an AI security
  assessment, an agent security review, a maturity score, an OWASP ASI or CSA
  AICM/AISMM gap analysis, or asks how exposed the repos are to agent and
  prompt-injection risk.
disable-model-invocation: true
---

# Assess AI Security Maturity

Produce an **evidence-based** maturity assessment of the Glific repositories against the
published agent-security standards, and hand the team a short list of fixes that would
actually move the score.

## Why this is not a questionnaire

Almost every AI security maturity assessment in circulation is scored on self-report, and
self-report is the specific thing that has already failed. A team that has never checked
where its allowlists apply will rate itself mature on network controls — honestly — and be
wrong. In the July 2026 Hugging Face intrusion the platform would have scored well on nine
dimensions out of ten; the tenth was a data-loader that read local files in a process
holding production secrets.

So every score in this assessment is anchored to something a reader can open: a file and
line, a config key, or a command and its output. A dimension with no evidence is scored
`unknown`, not guessed. That constraint is the whole value — it is what makes the number
worth showing to someone else.

## Prerequisites

- **Python 3** for `scripts/collect_evidence.py` (stdlib only, no network).
- Read access to the repos in scope. The collector uses `git ls-files` where available and
  falls back to a bounded filesystem walk.
- Sibling checkouts if you want a system-level view: `glific`, `glific-frontend`,
  `floweditor`, `glific-mcp`, `glific-web-channel`. Trust zones and egress only mean
  anything across the whole system, so a single-repo run is a partial assessment and the
  report must say so.
- Read [references/dimensions.md](references/dimensions.md) for the check catalogue and the
  level definitions. Read [references/standards.md](references/standards.md) when you need
  to cite a standard or map a finding to a control ID.

## Hard rules

- **Never put a secret value in the report.** Cite `path:line` and the rule that matched.
  The report is meant to be shared; a report containing live credentials has made the
  problem worse. The collector is built this way — keep it that way when you summarise.
- **Never score a dimension from a grep hit alone.** Open the file and read it. Roughly half
  the collector's candidates in this codebase are false positives on first pass, and
  several are the *opposite* of a defect — `lib/glific/flows/expression.ex` names
  `Code.eval_quoted` in its moduledoc to explain why it refuses to call it.
- **`unknown` is a real score, and a useful one.** When nothing in the repo settles a
  question, say so and name the file, command, or person that would. Never infer a level
  from the absence of evidence.
- **Report the weakest link, not the mean.** An average hides the one open door, which is
  the only part an attacker uses.
- **Assess; do not fix.** This skill reads and reports. Propose changes, do not make them
  unless the user asks — then treat each as its own change with its own review.
- **Stop and ask the user** if the scope is ambiguous (which repos, whether infrastructure
  config is in reach), or if a finding looks like a live exploitable vulnerability rather
  than a maturity gap — that is an incident, not a report line.

## Progress checklist

```
- [ ] Phase 0 — Scope agreed (repos, deploy config availability)
- [ ] Phase 1 — Evidence collected (collect_evidence.py)
- [ ] Phase 2 — Every candidate verified in context; false positives discarded
- [ ] Phase 3 — Ten dimensions scored, each with citation or `unknown`
- [ ] Phase 4 — Report written (weakest link + top fixes)
```

---

## Phase 0 — Scope

Establish and state in the report:

| Question | Why it changes the result |
|----------|---------------------------|
| Which repos are in scope? | Single-repo runs cannot judge trust zones, egress, or cross-service identity |
| Is deployment config reachable (Gigalixir, Netlify/Vercel, k8s manifests, Terraform)? | Dimensions 02, 06 and 09 depend on it; without it they are `unknown`, not zero |
| Is this a point-in-time baseline or a re-run? | A re-run should report deltas against the previous report's date and commit |

Record the commit SHA of each repo. A maturity score without a SHA cannot be reproduced or
compared later.

## Phase 1 — Collect evidence

```bash
python3 .claude/skills/assess-ai-security-maturity/scripts/collect_evidence.py \
  --repo . --repo ../glific-frontend --repo ../glific-mcp \
  --repo ../glific-web-channel --repo ../floweditor \
  --pretty --out /tmp/ai-sec-evidence.json
```

Takes a few seconds per repo. Read `summary` per repo first — the detail arrays are
deliberately truncated and exist for drilling into a specific claim.

What the collector establishes mechanically, so you do not have to:

- credential-shaped strings, split by `code` / `test` / `doc` context
- tracked files whose *names* imply secrets, and whether `.gitignore` covers them
- the LLM/agent surface (which files touch a model vendor, and which touch MCP)
- dangerous sinks, language-scoped: `Code.compile_string`, `EEx.eval_string`,
  `String.to_atom`, pickle, unsafe YAML, Jinja `from_string`, `dangerouslySetInnerHTML`,
  raw SQL execution with interpolation
- per-workflow CI posture: `permissions:` declared, `pull_request_target`, secrets
  referenced, third-party actions pinned to a SHA or floating on a tag
- container posture: non-root `USER`, remote `ADD`, secret-shaped build args
- security tooling, and critically whether each tool **runs** or is only **declared** —
  including tools an aggregate runner has switched off

The last one matters more than it sounds. In `glific`, `.check.exs` sets
`{:sobelow, false}` and `{:mix_audit, false}` while both remain dependencies in `mix.exs`.
A dependency list implies coverage that does not exist, and *explicitly disabled* is a
different state from *never configured* — someone chose it, so ask why before scoring it.

## Phase 2 — Verify in context

For every candidate you intend to cite, open the file and answer three questions:

1. **Is it reachable from untrusted input?** Trace backwards. In Glific the untrusted
   sources are inbound WhatsApp messages, contact fields, flow definitions, webhook
   responses, uploaded media and dataset/CSV imports. A `Code.compile_string` reachable
   only from a Glific-admin GraphQL mutation is a very different finding from one reachable
   from a contact's message body.
2. **What does the process hold?** Production secrets in the environment, a database
   connection, internal network reach, a cloud metadata endpoint. Impact is a property of
   the trust zone, not of the sink.
3. **Is there already a control, and does it cover this primitive?** Write down which
   primitive each control blocks — URL fetch, local file read, code execution, DNS — and
   check it covers the one in play. Hugging Face's dataset allowlist was sound and
   irrelevant: it blocked URL fetches, and the attack used a local file read and local
   code execution.

Discard false positives silently; do not pad the report with them. But when a candidate
turns out to be a deliberate, well-reasoned control, note it under strengths — it is
evidence for a *higher* score, and teams rarely get credit for it.

## Phase 3 — Score the ten dimensions

Full check lists, per-level definitions and control-ID mappings are in
[references/dimensions.md](references/dimensions.md). The dimensions:

| # | Dimension | Primary question |
|---|-----------|------------------|
| 01 | Secret handling | Can a file read or a log line yield a working credential? |
| 02 | Identity & least privilege | One identity per workload, scoped and short-lived? |
| 03 | Trust zones | Does anything parsing untrusted input hold production reach? |
| 04 | Authorization enforcement | Are checks at the business boundary, in testable policy? |
| 05 | Agent & tool surface | Which legs of the lethal trifecta does each agent hold? |
| 06 | Egress control | Default-deny, or can a compromised process reach anywhere? |
| 07 | Supply chain | Are deps, actions and MCP servers pinned and reviewed? |
| 08 | Audit integrity | Could you reconstruct a session, and can the actor edit the log? |
| 09 | Stop capability | Can you halt a running agent, and has that been tested? |
| 10 | Detection | Are behavioural and infrastructure signals correlated and routed? |

Score each 0–4 (the mapping to CSA AISMM levels 1–5 is in
[references/standards.md](references/standards.md)):

| Score | Meaning |
|-------|---------|
| **0** | Absent. No control, and the exposure is reachable. |
| **1** | Ad hoc. Something exists in places, inconsistent, undocumented, unenforced. |
| **2** | Defined. A consistent pattern exists but nothing prevents departing from it. |
| **3** | Enforced. CI, policy or infrastructure blocks the bad state; departures fail. |
| **4** | Measured. Enforced *and* monitored, with a tested response path and a metric. |
| **`unknown`** | Nothing in scope settles it. Name what would. |

Two scoring habits that keep the result honest:

- **Enforced beats documented.** A convention in `CLAUDE.md` is level 2. The same rule
  failing the build is level 3. The gap between them is where incidents happen.
- **Score the state, not the intention.** A disabled scanner scores as no scanner, however
  good the reason. Record the reason separately — it usually explains the fix.

## Phase 4 — Report

Use this structure. Keep it short enough to be read.

```markdown
# AI Security Maturity Assessment — <scope>
<date> · repos and commit SHAs · assessed against CSA AISMM, OWASP ASI (2026)

## Overall: Level <weakest link> (<dimension that sets it>)
One paragraph: what the weakest link is, what it would cost, and what raises it.

## Scores
| # | Dimension | Level | Evidence |
|---|-----------|-------|----------|
| 01 | Secret handling | 2 | `path:line`, `path:line` |
...
Dimensions scored `unknown` are listed with the file or command that would settle them.

## Top 3 fixes, highest leverage first
For each: what to change, which files, which dimension and control ID it moves,
and roughly what it costs.

## Strengths worth keeping
Deliberate controls found in the code. Name them so they survive refactors.

## Out of scope / not assessed
What this run could not see, and why.
```

Rules for the report itself:

- Every score cites evidence or reads `unknown`. No exceptions — an uncited score is the
  self-report failure this skill exists to avoid.
- Top fixes are ordered by **exposure reduced per unit of work**, not by severity label. A
  one-line CI change that turns a scanner on usually beats a refactor.
- Name the control ID (`ASI03`, `AICM` domain) so the result reconciles with whatever
  framework the org already reports against. Do not invent IDs — if unsure, cite the
  standard by name only.
- If a finding is exploitable now, stop and tell the user directly rather than filing it as
  a report line.

---

## When to ask the user

- Scope is unclear, or deploy/infrastructure config is not in the checkout
- A finding appears to be a live exploitable vulnerability
- A control is deliberately disabled and the reason is not in the repo (e.g. why
  `.check.exs` switches Sobelow off)
- The user wants fixes applied, not just reported
- Scoring would require access to runtime systems (SIEM, cloud IAM, Gigalixir config)

## Related skills

- **make-branch-ready-for-review** — `.claude/skills/make-branch-ready-for-review/SKILL.md`,
  for shipping any fix this assessment recommends
- **security-review** — reviews a *diff*; this skill assesses the *system*. Use that for a
  PR, this for a baseline.

## Additional resources

- [references/dimensions.md](references/dimensions.md) — check catalogue, level definitions
- [references/standards.md](references/standards.md) — CSA AISMM/AICM, OWASP ASI, NIST
  SP 800-207A, EU AI Act Art. 15, and how scores map
- Glific conventions: `CLAUDE.md`, `lib/glific/CLAUDE.md`, `lib/glific_web/CLAUDE.md`
- Aggregate check roster: `.check.exs`
