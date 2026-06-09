---
name: make-branch-ready-for-review
description: >-
  Prepare the current branch for PR review in Glific: run MIX_ENV=test mix check and tests,
  meet Codecov thresholds, self-review, commit, push, then poll CI/Codecov/CodeRabbit
  until green. Use when the user asks to make a branch review-ready, get changes
  ready for review, or invokes make-branch-ready-for-review.
disable-model-invocation: true
---

# Make Branch Ready for Review

End-to-end workflow to take **the current branch** from local changes through green CI and addressed bot review, ready for human reviewers.

## Prerequisites

- On the intended feature branch (not `master` unless the user explicitly wants that).
- GitHub CLI (`gh`) authenticated for this repo.
- Postgres available locally (CI uses Postgres 13; `mix test` / `mix coveralls.json` create/migrate the test DB).
- **Python 3** for the local coverage gate (via **improve-code-coverage**).
- Read [reference.md](reference.md) when you need exact `gh` / Codecov / CodeRabbit commands.

## Hard rules

- **Never** change CI workflow files or disable checks to make failures pass.
- **Never** use destructive git (`reset --hard`, `clean -fdx`, force-push to `master`) without explicit user approval.
- **Never** commit secrets (`.env`, credentials, keys).
- **Stop and ask the user** when this skill says to — do not guess on high-risk or unsafe fixes.
- During the **post-push loop**: commit fixes locally; **do not push** until the loop completes successfully (then push once at the end).

## Progress checklist

Copy and update as you go:

```
- [ ] Phase 1 — Local quality (MIX_ENV=test mix check, tests, coverage)
- [ ] Phase 2 — Review agent + high-risk gate
- [ ] Phase 3 — Commit and push
- [ ] Phase 4 — CI loop (tests, codecov, coderabbit)
- [ ] Phase 5 — Final push and done
```

---

## Phase 1 — Local quality

### 1.1 `MIX_ENV=test mix check`

Run (matches the CI `code-quality` job — `MIX_ENV=test` compiles `test/support/` so Doctor
validates support-module `@spec`s):

```bash
MIX_ENV=test mix check
```

Fix every reported issue (format, Credo, Dialyzer, Doctor, compile warnings-as-errors).

| Situation | Action |
|-----------|--------|
| Safe, mechanical fix (format, obvious Credo, missing `@spec`, clear Dialyzer fix in changed code) | Fix and re-run `MIX_ENV=test mix check` until green |
| Fix requires behavior change, suppressing a rule, large refactor, or touching unrelated files | **Stop and ask the user** how to proceed |
| Dialyzer/PLT missing locally | Run `mix dialyzer --plt` once, then retry; if still blocked, ask the user |

### 1.2 Tests

Run the full suite the way CI does:

```bash
mix test
```

| Failure type | Action |
|--------------|--------|
| Clearly caused by your branch changes | Fix application or test code; re-run |
| Intermittent / ordering / mock leakage | Read and follow `.claude/skills/fix-flaky-tests/SKILL.md` |
| Unrelated failure on an old branch | Ask the user whether to merge/rebase `master` first |

Do not mark Phase 1 complete until `mix test` exits 0.

### 1.3 Coverage (delegate to improve-code-coverage)

**Read and follow** `.claude/skills/improve-code-coverage/SKILL.md` in full. Do not duplicate its loop here.

Summary for Phase 1:

1. Run the **improve-code-coverage** improve loop until `check_codecov_local.py` exits **0** (project + patch per `codecov.yml`).
2. If there are **uncommitted** `lib/*.ex` changes that must ship in this PR, use `--include-worktree` on the gate (see improve-code-coverage reference).
3. Do not mark Phase 1 complete until the improve-code-coverage skill reports **green**.

| Situation | Action |
|-----------|--------|
| Gate fails after tests added | Continue improve-code-coverage loop (max 5 loops per that skill) |
| Five loops without green (improve-code-coverage) | **Stop and ask the user** |
| Large unrelated test work only | **Stop and ask the user** |

CI still uploads `cover/excoveralls.json` after push (`.github/workflows/continuous-integration.yml`).

---

## Phase 2 — Review agent and high-risk gate

### 2.1 Run a review agent

Launch a **readonly** review pass over the full branch diff vs the default branch (`master` unless the repo uses another default):

- Use a subagent or structured self-review with the prompt in [reference.md](reference.md) § Review agent prompt.
- Produce findings tagged: **critical**, **major**, **minor**, **nit**.

Address **critical** and **major** items that are valid. Explain and skip invalid bot-style false positives.

### 2.2 High-risk changes — stop for confirmation

Before Phase 3, if the diff includes any of the following, **stop and ask the user** how to proceed (do not commit yet):

- Database migrations or destructive schema changes
- Auth, roles, API tokens, or organization scoping / `Repo.put_organization_id`
- Billing, payments, or external BSP/provider credentials
- Mass deletes, data backfills, or Oban jobs that change production behavior at scale
- Feature flags removed or default changed
- Security-sensitive plugs, webhooks, or public endpoints
- Large cross-cutting refactors outside the stated PR scope

Summarize risk, files touched, and recommended options.

---

## Phase 3 — Commit and push

Only after Phases 1–2 pass (and user cleared any high-risk gate).

1. `git status`, `git diff`, `git log -5` — follow repo commit message style.
2. Stage **only** files that belong to this change (no `git add -A` unless the user asked).
3. Commit with a HEREDOC message focused on **why**:

```bash
git commit -m "$(cat <<'EOF'
Your message here.

EOF
)"
```

4. Push the branch:

```bash
git push -u origin HEAD
```

Record the PR number (open one with `gh pr create` only if the user asked or no PR exists and they want one).

---

## Phase 4 — Post-push CI loop (1 minute cadence)

After the first push, enter a **polling loop every 1 minute** until all gates pass or you must stop for the user.

Use the [loop](~/.cursor/skills-cursor/loop/SKILL.md) pattern when available: background `sleep 60` + sentinel + `notify_on_output`, or re-invoke this phase on each wake. Between iterations, run the checks below.

### 4.1 GitHub Actions / CI tests

```bash
gh pr checks --watch=false   # or gh run list / gh run view for the branch HEAD
```

| Result | Action |
|--------|--------|
| **tests** (or test job) failing | Fetch logs (`gh run view --log-failed`). If related to your change, fix. If flaky, use **fix-flaky-tests** skill. **Commit locally; do not push.** |
| **code-quality** / **compile** failing | Fix locally if in scope; if fix needs CI/workflow change, **stop and ask the user** |
| Other failing checks (unknown, deploy, third-party) | **Stop and ask the user** — do not weaken CI |

### 4.2 Codecov

Wait for the Codecov status on the PR (names often `codecov/project`, `codecov/patch`).

| Result | Action |
|--------|--------|
| Pending | Wait next loop iteration |
| Failure | Open PR Codecov report for context (see [reference.md](reference.md) § Codecov). Then **read and follow** `.claude/skills/improve-code-coverage/SKILL.md` until the local gate is green. **Commit locally; do not push.** |
| Success | Continue |

### 4.3 CodeRabbit

Fetch unresolved review threads (see [reference.md](reference.md) § CodeRabbit).

| Comment severity | Action |
|------------------|--------|
| **Major** (architecture, security, wrong behavior, breaking API) | **Ask the user** whether to implement |
| **Minor / nit / style** | Implement if valid; skip with brief reason if not |
| **Critical** (same as major) | Fix or ask user if fix is disputed |

After fixes: **commit locally; do not push** during the loop.

### 4.4 Loop exit

Continue the 1-minute loop until **all** are true:

- Required CI jobs green (at minimum: `code-quality`, `tests`, `compile`, and coverage upload job if present)
- Codecov project + patch green
- No unresolved CodeRabbit threads you are responsible for (per CONTRIBUTING.md)
- No pending user decisions from this skill

If the same failure repeats after **3** fix attempts, **stop and ask the user**.

---

## Phase 5 — Final push and complete

When Phase 4 passes:

```bash
git push origin HEAD
```

Verify checks stay green once (single `gh pr checks` after push). Then report:

- Branch name and commit SHA
- PR URL
- Summary of fixes made in the loop (tests, coverage, CodeRabbit)
- Anything left for human reviewers

---

## When to ask the user (summary)

- Unsafe or ambiguous `MIX_ENV=test mix check` / Dialyzer fixes
- High-risk diff categories (Phase 2.2)
- Major CodeRabbit or review-agent suggestions
- CI failures outside PR scope or requiring workflow changes
- Coverage blocked per improve-code-coverage (5 loops or large unrelated test work)
- Repeated loop failures (3+ attempts on same issue)

## Related skills

- **improve-code-coverage** — `.claude/skills/improve-code-coverage/SKILL.md` (Phase 1.3 and Phase 4.2 failures)
- **fix-flaky-tests** — `.claude/skills/fix-flaky-tests/SKILL.md`
- **babysit** — keep an existing PR merge-ready after this workflow
- **loop** — timed wake for Phase 4

## Additional resources

- Glific conventions: `CLAUDE.md`
- Coverage config: `codecov.yml`
- CI workflow: `.github/workflows/continuous-integration.yml`
