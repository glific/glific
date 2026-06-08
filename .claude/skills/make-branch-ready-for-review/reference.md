# Make Branch Ready for Review — Reference

Commands and prompts for Phase 2–4. Prefer `gh` over raw curl.

## Default branch

```bash
git remote show origin | sed -n '/HEAD branch/s/.*: //p'
```

Usually `master` for Glific.

## Diff scope for review

```bash
git fetch origin
git diff origin/master...HEAD
git log origin/master..HEAD --oneline
```

## Review agent prompt

Use with a readonly subagent or structured self-review:

```text
You are reviewing a Glific (Elixir/Phoenix) PR branch diff vs master.

Read the full diff and list findings as:
- critical: must fix before merge (bugs, security, data loss)
- major: should fix or needs human decision (API breaks, tenancy leaks)
- minor: worthwhile improvement
- nit: style only

Check specifically:
- organization_id scoping and Repo.put_organization_id usage
- {:ok, _} / {:error, _} and with/else patterns
- @spec and @moduledoc on new public functions
- tests for new behavior; no trivial assertions
- Oban jobs, migrations, webhooks — side effects and idempotency
- no secrets or debug IO left in

Return a numbered list with file:line when possible. No praise, no filler.
```

After the list, fix valid critical/major items unless Phase 2.2 high-risk stop applies.

## GitHub PR and checks

```bash
# Current branch PR
gh pr view --json number,url,headRefName,statusCheckRollup

# Check statuses (no watch)
gh pr checks

# Failed workflow logs
gh run list --branch "$(git branch --show-current)" --limit 5
gh run view <run-id> --log-failed
```

### Typical CI job names (Continuous Integration workflow)

| Check / job | Local equivalent |
|-------------|------------------|
| `code-quality` | `mix check` |
| `tests` | `mix test` (+ postgres) |
| `compile` | `mix compile --warnings-as-errors` |
| Coverage upload | **improve-code-coverage** skill (local gate), then CI `mix coveralls.json` |

## Codecov

Delegated to **improve-code-coverage** for local pass/fail:

```bash
mix coveralls.json
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py
```

See `.claude/skills/improve-code-coverage/SKILL.md` and its [reference.md](../improve-code-coverage/reference.md).

- Config: `codecov.yml` — project target **88.25%**, patch threshold **1%**
- PR report (after push, for debugging CI failures): `https://app.codecov.io/gh/glific/glific/pull/<PR_NUMBER>` → **Files changed**

Phase 1.3 and Phase 4.2 Codecov failures: run the full improve-code-coverage loop until the local script exits 0. Use `--include-worktree` if fixing coverage for uncommitted `lib/*.ex` changes.

## CodeRabbit

Config pointer: `.coderabbit.yaml` (remote config URL).

### Unresolved review comments

```bash
PR=$(gh pr view --json number -q .number)
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 10) {
              nodes {
                author { login }
                body
                path
                line
              }
            }
          }
        }
      }
    }
  }
' -f owner=glific -f repo=glific -F pr="$PR"
```

Filter `isResolved: false` and `author.login` matching CodeRabbit (often `coderabbitai` or similar).

### Classify severity (heuristic)

| Treat as **major** (ask user) | Treat as **minor** (fix if valid) |
|-------------------------------|-----------------------------------|
| Security, auth, tenancy | Formatting, naming |
| Public API / GraphQL schema break | Doc comments |
| Migration rollback safety | Small refactor suggestions |
| "This will break production…" | Test naming |

## Commit message (Glific style)

- Imperative subject, ~72 chars
- Body: why the change matters, not a file list
- Reference issue `Fixes #123` when applicable

## Phase 4 loop sentinel (optional)

When using Cursor loop tooling:

```bash
while true; do
  sleep 60
  echo 'AGENT_LOOP_TICK_make-branch-ready {"prompt":"Run Phase 4 checks for make-branch-ready-for-review skill"}'
done
```

Regex: `^AGENT_LOOP_TICK_make-branch-ready`
