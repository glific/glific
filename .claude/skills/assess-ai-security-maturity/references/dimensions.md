# Dimension catalogue

Checks, level definitions and control mappings for the ten dimensions. Each section gives
the question, the commands that produce evidence in *these* repos, what each level looks
like, and notes on what is already known about the Glific system so a run does not
rediscover it.

The collector (`scripts/collect_evidence.py`) already answers the mechanical parts. Use
these sections for the judgement calls it cannot make.

## Contents

- [01 Secret handling](#01-secret-handling)
- [02 Identity and least privilege](#02-identity-and-least-privilege)
- [03 Trust zones](#03-trust-zones)
- [04 Authorization enforcement](#04-authorization-enforcement)
- [05 Agent and tool surface](#05-agent-and-tool-surface)
- [06 Egress control](#06-egress-control)
- [07 Supply chain](#07-supply-chain)
- [08 Audit integrity](#08-audit-integrity)
- [09 Stop capability](#09-stop-capability)
- [10 Detection](#10-detection)
- [Known system topology](#known-system-topology)

---

## 01 Secret handling

**Question:** can a file read, a log line, or a stack trace yield a working credential?

Maps to `ASI03` (identity and privilege abuse) and the AICM identity/data domains.

### Evidence to gather

- Collector: `secret_candidates_in_code`, `secret_candidates_by_rule`,
  `tracked_secret_filename_count`, `gitignore_covers`.
- Where config reads secrets from: `config/runtime.exs` uses `Dotenvy` with
  `source(["config/.env", "config/.env.#{config_env()}", System.get_env()])`. Check whether
  any secret has a committed default rather than failing closed when absent.
- Whether secrets reach the environment of a process that also parses untrusted input
  (this is the `/proc/self/environ` read that started the Hugging Face intrusion):

  ```bash
  grep -rn "System.get_env\|Application.fetch_env!" lib/ --include=*.ex | head -40
  ```

- Log redaction. Glific has `lib/glific/flows/webhook/header_redactor.ex` and
  `Glific.SafeLog` — check they are actually used on the paths that log third-party
  requests and exceptions, not merely present.
- Rotation and TTL: are any credentials long-lived static keys? Look at the CI secret names
  the collector lists (`GIGALIXIR_PASSWORD`, `SSH_PRIVATE_KEY`, `KAAPI_API_KEY`,
  `OBAN_PRO_KEY`) and ask which support rotation or OIDC exchange instead.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | Live credentials in tracked files, or secrets logged unredacted |
| 1 | No committed secrets found, but no scanning and no rotation story |
| 2 | Consistent env/vault pattern, `.gitignore` covers secret files, redaction helpers exist |
| 3 | Secret scanning blocks the build; committed secrets cannot merge; redaction enforced on log paths |
| 4 | Level 3 plus short-lived or OIDC-exchanged credentials with measured rotation age |

### Notes

Dev and test fixtures containing passwords (`config/test.exs`, `lib/glific/seeds/seeds_dev.ex`)
are low severity but not zero — check they cannot be loaded in a production release. Score
them as a note, not as a level-0 finding, unless a prod path reaches them.

---

## 02 Identity and least privilege

**Question:** does each workload have its own identity, scoped to what it needs, for as
short a time as it needs?

Maps to `ASI03`, NIST SP 800-207A (identity-based segmentation over network-based).

### Evidence to gather

- CI token scope: for each workflow the collector reports `declares_permissions`. GitHub's
  default token permissions apply to any workflow without a `permissions:` block, which is
  broader than almost any job needs.
- Deploy identity: `.github/workflows/continuous-deployment.yml` and the Gigalixir
  credentials — is deployment a shared username/password, or a scoped token?
- Database and service accounts: does the app use one superuser-ish role, or roles per
  function? Check `config/runtime.exs` and any migration granting privileges.
- Multi-tenancy is Glific's built-in least-privilege mechanism at the data layer. Verify
  `Repo.put_organization_id/1` discipline and, more importantly, count and review the
  deliberate escapes:

  ```bash
  grep -rn "skip_organization_id" lib/ --include=*.ex | wc -l
  grep -rn "skip_organization_id" lib/ --include=*.ex | head -30
  ```

  Each escape is a place where a bug crosses a tenant boundary. Whether they are justified
  is the finding, not the count.
- MCP identity: `glific-mcp` obtains a per-session access token and refreshes on 401
  (`src/glific_mcp/auth.py`, `client.py`). Confirm the token is per-user rather than a
  shared service credential, and that tenant isolation is genuinely enforced backend-side
  as the module docstring claims.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | Shared static credentials across workloads; no scoping |
| 1 | Separate credentials exist but scopes are broad and untracked |
| 2 | One identity per workload, documented, mostly least-privilege |
| 3 | Scopes enforced by config that fails closed; CI tokens explicitly narrowed per workflow |
| 4 | Level 3 plus short-lived credentials and an inventory with owner and lifecycle per identity |

---

## 03 Trust zones

**Question:** does any process that parses untrusted input also hold production secrets or
internal network reach?

Maps to `ASI05` (unexpected code execution), `ASI02` (tool misuse).

This is the dimension that decided the Hugging Face outcome, and it is the one most worth
spending time on.

### Untrusted inputs in Glific

Inbound WhatsApp message bodies and media; contact fields; flow definitions and flow
expressions; webhook responses from NGO-configured endpoints; CSV and sheet imports;
uploaded files; LLM output (treat model output as untrusted input to whatever consumes it).

### Evidence to gather

- Collector: `dangerous_sinks_by_rule`, `code` context only.
- For each sink, trace reachability and record the answer:

  ```bash
  grep -rn "Code.compile_string\|Code.eval_string\|EEx.eval_string" lib/ --include=*.ex
  grep -rn "String.to_atom" lib/ --include=*.ex | head -20
  ```

- Known case worth reading every time: `lib/glific/extensions/extension.ex` compiles stored
  Elixir source with `Code.compile_string/1`. That is arbitrary code execution by design.
  The assessment questions are who can write the `code` field (which GraphQL mutation, which
  role), whether the compiling process holds production secrets and network reach, and
  whether anything bounds what the compiled module can do.
- Known counter-example worth crediting: `lib/glific/flows/expression.ex` is a deliberately
  non-Turing-complete evaluator that refuses `Code.eval_quoted` and explains why — "validating
  one representation and executing another is the bug." Cite it under strengths.
- Webhook egress and header handling: `lib/glific/flows/webhook/` — do NGO-configured
  webhook URLs get fetched from a process with internal network reach? Can they point at
  `169.254.169.254` or an internal service (SSRF)?
- Cloud metadata reachability from any workload that parses user input.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | Untrusted input reaches a code-execution sink in a process holding production secrets |
| 1 | Sinks exist and are reachable only via privileged roles; no isolation, no written analysis |
| 2 | Trust boundaries understood and documented; parsing mostly separated from privilege |
| 3 | Parsing of untrusted input runs with no production secrets and no internal reach, enforced by deployment |
| 4 | Level 3 plus the boundary is tested — a fixture proves the parse process cannot reach secrets or internal hosts |

---

## 04 Authorization enforcement

**Question:** are access checks at the business boundary, expressed in something testable?

Maps to `ASI03`, AICM application domain.

### Evidence to gather

- GraphQL is the primary API, so authorization lives in resolvers and middleware. Read
  `lib/glific_web/CLAUDE.md` for the intended pattern, then check reality:

  ```bash
  ls lib/glific_web/schema/middleware/ 2>/dev/null
  grep -rn "Absinthe.Middleware\|middleware(" lib/glific_web/schema.ex | head -20
  ```

- Role checks: are they a middleware applied by default, or per-resolver and easy to omit?
  A control you have to remember to add is level 2 at best.
- By-id lookups crossing tenants — the resolver rule in `lib/glific_web/CLAUDE.md`.
- Frontend role logic (`glific-frontend/src/context/role.ts`, `routeStaff`/`routeAdmin`) is
  UI convenience, not authorization. Confirm every route restriction has a server-side
  counterpart; if the API trusts the client's role, that is a level-0 finding.
- Is authorization tested? Look for tests asserting a *denied* case, not just allowed ones:

  ```bash
  grep -rn "unauthorized\|not_authorized\|permission" test/glific_web/ | head -20
  ```

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | Authorization only client-side, or absent on some mutating endpoints |
| 1 | Server-side checks present but inconsistent and per-resolver |
| 2 | Consistent documented pattern; role checks applied by convention |
| 3 | Default-deny middleware; a new endpoint is protected unless it opts out; denial paths tested |
| 4 | Level 3 plus authorization expressed as reviewable policy with its own test suite |

---

## 05 Agent and tool surface

**Question:** for each agent or LLM integration, which legs of the lethal trifecta does it
hold — private data, untrusted content, external communication?

Maps to `ASI01` (goal hijack), `ASI02` (tool misuse), `ASI06` (memory/context poisoning),
`ASI07` (inter-agent communication).

### Evidence to gather

- Collector: `llm_surface_files`, `mcp_surface_files`.
- Build a table, one row per integration, and fill all three columns. This table *is* the
  finding — if it has a row with all three legs, that is the headline:

  | Integration | Private data | Untrusted content | External comms |
  |-------------|--------------|-------------------|----------------|

  Start from `lib/glific/assistants/`, `lib/glific/ai_evaluations.ex`,
  `lib/glific/prompt_generator.ex`, `lib/glific/third_party/open_ai/chat_gpt.ex`,
  `lib/glific/third_party/gemini.ex`, `lib/glific/third_party/kaapi/`, and the flow webhook
  implementations `parse_via_chat_gpt.ex`, `parse_via_gpt_vision.ex`,
  `voice_filesearch_gpt.ex`.
- Prompt construction: does untrusted content (a contact's message, a contact field) get
  concatenated into a system prompt, or passed as clearly delimited user content? Look for
  string interpolation into prompt templates.
- Tool breadth: for `glific-mcp`, count the tools and confirm read-only really is read-only:

  ```bash
  grep -c "@mcp.tool()" ../glific-mcp/src/glific_mcp/tools/read.py
  grep -rn "mutation\|create\|update\|delete" ../glific-mcp/src/glific_mcp/tools/read.py | head
  ```

  A server described as read-only that exposes one mutation is a worse position than an
  honestly read-write one, because the description is what people reason with.
- Which design pattern does each integration use? Action-selector and plan-then-execute
  bound the damage; an open-ended agent with tools does not. See
  [standards.md](standards.md) for the pattern list.
- Approval gates: does any LLM-driven path write to production data or trigger an outbound
  message without a human in the loop?

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | An agent holds all three trifecta legs with no gate, or untrusted text lands in a system prompt |
| 1 | Integrations inventoried informally; no per-integration analysis |
| 2 | Each integration's data/content/comms reach is documented; prompts separate untrusted content |
| 3 | Architecture removes a leg where possible (read-only tools, quarantined parsing); write actions gated |
| 4 | Level 3 plus injection tests in CI that fail the build when a gate regresses |

---

## 06 Egress control

**Question:** if a workload is compromised, where can it reach?

Maps to `ASI02`, `ASI05`.

### Evidence to gather

- Is there any egress policy at all for app workloads, CI jobs, or agent sandboxes? On
  Gigalixir and most PaaS the default is unrestricted outbound — check rather than assume.
- Outbound HTTP clients and whether destinations are bounded: Tesla/Finch/httpx config,
  and specifically NGO-supplied webhook URLs in flows. Is there a denylist for link-local
  and private ranges?

  ```bash
  grep -rn "169.254\|metadata.google\|127.0.0.1\|localhost" lib/glific/flows/webhook* -r
  ```

- Container network posture: `Dockerfile`s in `glific`, `glific-mcp`, `glific-web-channel`,
  `floweditor/.devcontainer` — the collector reports which lack a non-root `USER`.
- Developer agent sandboxes: do engineers run coding agents with unrestricted network
  access to the repo and their credentials? This is a process answer, usually `unknown`
  from the repo alone — name it and ask.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | Unrestricted egress everywhere, and user-supplied URLs fetched without range filtering |
| 1 | Some filtering in application code, nothing at the network layer |
| 2 | Documented expectations; SSRF protections on user-supplied URL fetches |
| 3 | Default-deny egress with a reviewed allowlist for app, CI and agent workloads |
| 4 | Level 3 plus denied-egress attempts are logged and alerted on |

---

## 07 Supply chain

**Question:** can a third party you did not review change what runs?

Maps to `ASI04` (agentic supply chain), AICM supply-chain domain.

### Evidence to gather

- Collector: `lockfiles`, `unpinned_third_party_actions`, `workflows_with_pull_request_target`,
  `security_tooling` (declared vs runs vs explicitly disabled).
- Third-party GitHub Actions pinned to a commit SHA rather than a mutable tag. A tag can be
  repointed by whoever controls the action repo; the Shai-Hulud/CHAINDROP worms spread
  through exactly this kind of trust.
- Dependency vulnerability scanning that actually runs. In `glific`, `mix_audit` is a
  declared tool disabled in `.check.exs` — so dependency CVEs are currently unchecked in CI.
- MCP server provenance: which servers do engineers run locally, pinned to which versions,
  and has anyone read the tool descriptions? Tool descriptions are part of the prompt, so
  they are executable content and belong in review. Usually `unknown` from the repo — ask.
- Dependabot or equivalent, and whether its PRs get merged or pile up.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | No lockfiles, or CI runs unpinned third-party actions with access to secrets |
| 1 | Lockfiles present; no vulnerability scanning running; actions on floating tags |
| 2 | Scanning configured; update process exists; pinning inconsistent |
| 3 | Dependency and action pinning enforced; vulnerability scan blocks the build; MCP servers pinned |
| 4 | Level 3 plus provenance/SBOM and a measured time-to-patch |

### Notes

Distinguish *declared* from *running* every time. `sobelow` and `mix_audit` in `mix.exs`
with `{:sobelow, false}` and `{:mix_audit, false}` in `.check.exs` is the clearest example
in this codebase of tooling that implies coverage it does not provide.

---

## 08 Audit integrity

**Question:** could you reconstruct what an agent or integration did, and could the actor
have edited that record?

Maps to `ASI08` (cascading failures), `ASI10` (rogue agents), EU AI Act Art. 12/15 logging.

In the July 2026 incident more than 7% of reviewed agent transcripts contained spoofed tool
calls, and one group escaped its container to make the log show one command while another
ran. An audit trail the actor can reach is not evidence.

### Evidence to gather

- What is logged for LLM and webhook calls: prompts, tool calls, responses, identities,
  timestamps. Check `lib/glific/flows/webhook/`, `lib/glific/mails/mail_log.ex`, and any
  assistant/evaluation logging.
- Is the log append-only and outside the blast radius of the process that writes it, or a
  table the app can update and delete?
- Retention: long enough to investigate something discovered weeks later?
- Does anything alert on *gaps* — a missing stretch of log — rather than only on anomalies?
- AppSignal is configured for APM. Establish whether it carries security-relevant events or
  only performance telemetry.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | LLM/agent actions not logged, or logs mutable by the component being audited |
| 1 | Application logs exist; no integrity guarantee; retention unclear |
| 2 | Structured logs covering agent actions with defined retention |
| 3 | Append-only storage outside the actor's reach; a session is reconstructable end to end |
| 4 | Level 3 plus signed records and alerting on gaps, exercised at least once |

---

## 09 Stop capability

**Question:** can you halt a running agent or integration, and has anyone tried?

Maps to `ASI10`, EU AI Act Art. 14 (human oversight).

More than a third of organisations surveyed in 2026 admitted they could not shut down a
rogue agent. The number to produce here is mean time to stop.

### Evidence to gather

- Feature flags and kill switches: Glific has `lib/glific/flags/` (FunWithFlags). Can an
  LLM integration, a flow, or the webhook subsystem be disabled per organisation and
  globally, without a deploy?
- Oban queues: can a queue be paused at runtime? Are there iteration or retry ceilings, or
  can a job loop indefinitely?

  ```bash
  grep -rn "max_attempts\|unique:\|queue:" lib/glific/ --include=*.ex | head -20
  ```

- Budget and rate ceilings on LLM calls per organisation — is there anything that stops
  runaway spend or runaway volume?
- Is the stop path enforced outside the component being stopped, so the component cannot
  bypass it?
- Has a stop been tested? A kill switch that has never been pulled is a hypothesis.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | No way to stop an integration short of a deploy or a database edit |
| 1 | Flags exist for some paths; no ceilings; untested |
| 2 | Runtime disable for each integration; retry and attempt limits set |
| 3 | Circuit breakers on iteration, budget and failure thresholds, enforced externally |
| 4 | Level 3 plus a rehearsed stop with a measured mean time to stop |

---

## 10 Detection

**Question:** would you notice, and would the signal reach someone who could act?

Maps to `ASI09`, `ASI10`, AICM monitoring domain.

Hugging Face's own anomaly detection caught the intrusion — after two days of lateral
movement. OpenAI's chain-of-thought monitoring had the signal more than a day earlier and it
was not wired to anything. Both halves matter: the signal, and the route from signal to
action.

### Evidence to gather

- What anomaly signals exist on LLM/agent paths: unusual volume, unusual tool sequences,
  cost spikes, repeated failures, tenant-boundary errors.
- Where alerts go, and whether anyone is on the other end. An alert into a channel nobody
  watches scores as no alert.
- Are behavioural signals (what the integration did) correlated with infrastructure signals
  (what the process touched)? Neither alone caught the 2026 incident.
- Is there an incident runbook that mentions agents or LLM integrations at all?
- Forensics readiness: could payloads be analysed if a vendor's safety filters refused?
  Hugging Face had to switch to a self-hosted model mid-investigation.

### Levels

| Score | Looks like |
|-------|-----------|
| 0 | No monitoring of agent or LLM activity |
| 1 | Error tracking only (exceptions, uptime) |
| 2 | Agent-specific metrics collected and visible on a dashboard |
| 3 | Alerts on defined conditions, routed to an owner, with a runbook |
| 4 | Level 3 plus behavioural and infrastructure signals correlated, and a rehearsed agent scenario |

---

## Known system topology

Recorded so each run starts from facts rather than rediscovering them. Re-verify rather
than trusting this list — it is a starting point with a date on it, first written
September 2026.

| Component | Repo | Relevance |
|-----------|------|-----------|
| Elixir/Phoenix backend, GraphQL via Absinthe, Oban queues | `glific` | Holds production secrets, DB, tenant scoping |
| LLM integrations: assistants, AI evaluations, prompt generator | `glific` | `lib/glific/assistants/`, `lib/glific/ai_evaluations.ex`, `lib/glific/prompt_generator.ex` |
| Model vendors: OpenAI, Gemini, Kaapi | `glific` | `lib/glific/third_party/` |
| Flow webhooks calling models | `glific` | `parse_via_chat_gpt.ex`, `parse_via_gpt_vision.ex`, `voice_filesearch_gpt.ex` |
| Dynamic code compilation | `glific` | `lib/glific/extensions/extension.ex` — `Code.compile_string/1` |
| Hardened expression evaluator | `glific` | `lib/glific/flows/expression.ex` — a strength, cite it |
| Redaction helpers | `glific` | `flows/webhook/header_redactor.ex`, `Glific.SafeLog` |
| Read-only MCP server, OAuth, per-session token | `glific-mcp` | `src/glific_mcp/{auth,client,oauth}.py`, tools in `tools/read.py` |
| React frontend, role-based routes | `glific-frontend` | Client-side roles are not authorization |
| Flow editor | `floweditor` | Renders flow content; check HTML sinks |
| Web channel widget | `glific-web-channel` | Public-facing entry point for untrusted input |
| Aggregate check roster | `glific` | `.check.exs` — Sobelow and mix_audit disabled |
| Deploy | both apps | Gigalixir (backend), Netlify/Vercel (frontends) |
