---
name: improve-code-coverage
description: >-
  Check whether branch changes meet Glific Codecov thresholds using only local
  git and ExCoveralls (no push, no CODECOV_TOKEN), add focused tests for gaps,
  and re-run until the local gate passes. Use when the user asks to improve
  coverage, fix Codecov failures, or satisfy codecov.yml on the current branch.
disable-model-invocation: true
---

# Improve Code Coverage

Iterative workflow: generate an ExCoveralls report, validate **project** and **patch** gates with a **local script** (mirrors `codecov.yml`), add tests for uncovered changed lines, and repeat until the gate is **green**.

No `git push`, no Codecov upload, and no network required.

## Prerequisites

- On a feature branch (or `master` only if the user explicitly wants that).
- Postgres available locally (`mix coveralls.json` runs `test_full` and needs the test DB).
- **Python 3** and **`jq`** (optional, for ad-hoc inspection) on the machine.
- **Local git only**: diff uses `git merge-base HEAD <base>` and `git diff` — no `git fetch` or `origin` push required.
- Committed branch changes are compared to local **`master`** (override with `CODECOV_BASE_BRANCH`). Uncommitted `lib/*.ex` changes are included only when using `--include-worktree` (see [reference.md](reference.md)).

Read [reference.md](reference.md) for commands and troubleshooting.

## Project requirements (`codecov.yml`)

| Check | Local rule (see reference) |
|-------|----------------------------|
| **Project** | target **88.25%**, threshold **0.5%** |
| **Patch** | at most **1%** uncovered lines in the branch diff |

CI still uploads to Codecov after push; this skill approximates the same gates offline.

## Hard rules

- **Never** weaken `codecov.yml` or disable checks to get green.
- **Never** add tests that only hit lines without asserting behavior.
- **Never** `git push` or call Codecov upload APIs as part of this skill unless the user explicitly asks for a remote check afterward.
- **Stop and ask the user** after **5** loops without green, or if fixes need large unrelated test work.
- Do **not** commit unless the user asked; run the loop on the current tree (commits ± optional worktree).

## Progress checklist

```
- [ ] Loop N — mix coveralls.json
- [ ] Loop N — scripts/check_codecov_local.py (exit 0)
- [ ] Loop N — Add/fix tests for reported uncovered patch lines
- [ ] Final — local gate green (project + patch)
```

---

## Improve loop (repeat until green)

### Step 1 — Generate coverage artifact

```bash
mix coveralls.json
```

| Result | Action |
|--------|--------|
| Tests fail | Fix first (flaky: `.claude/skills/fix-flaky-tests/SKILL.md`), then re-run |
| Success | Confirm `cover/excoveralls.json` exists |

### Step 2 — Local Codecov gate

From repo root:

```bash
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py
```

Include unstaged/staged `lib/*.ex` changes in the patch (optional):

```bash
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py --include-worktree
```

| Result | Action |
|--------|--------|
| Exit **0** (both `PASS`) | Report project %, patch %, loop count; stop |
| Exit **1** (`FAIL` project and/or patch) | Go to Step 3 |
| Exit **2** (missing report / git error) | Fix setup per [reference.md](reference.md) |

The script prints uncovered `path:line` for patch failures.

### Step 3 — Add tests

1. Target lines/files from Step 2 patch `FAIL` output.
2. Add or extend tests under `test/` mirroring `lib/`:
   - `Glific.DataCase` / `ConnCase` as appropriate
   - Organization fixtures / `Repo.put_organization_id/1`
   - `Tesla.Mock` for external HTTP
   - Real behavior assertions
3. Run targeted tests, then return to **Step 1**.

### Step 4 — Loop exit

Repeat until Step 2 exits 0. Report branch, `HEAD` SHA, loops, tests added, and final percentages.

---

## Optional: stricter project check vs local base

To mirror Codecov’s “no drop vs base branch” project rule:

1. On local `master` (or base branch): `mix coveralls.json` then  
   `python3 .../check_codecov_local.py --save-baseline` (see reference).
2. On the feature branch: run the gate with `--baseline-file .coverage-baseline.json`.

Skip unless the user wants base-relative project comparison.

---

## When to ask the user

- Five loops without green
- Patch failures only in files outside the intended PR scope
- Coverage gaps requiring broad unrelated suites
- Whether to use `--include-worktree` for uncommitted work

## Related skills

- **make-branch-ready-for-review** — push + CI/Codecov after local gates pass
- **fix-flaky-tests** — failures during `mix coveralls.json`

## Additional resources

- `CLAUDE.md`, `codecov.yml`, [reference.md](reference.md)
