# Improve Code Coverage — Reference

Local-only gate: **no** `CODECOV_TOKEN`, **no** `git push`, **no** Codecov CLI upload.

## Local gate script

```bash
# After mix coveralls.json
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py
```

| Flag | Purpose |
|------|---------|
| `-f PATH` | Report path (default: `cover/excoveralls.json`) |
| `-b BRANCH` | Base branch for merge-base (default: `master`, or `CODECOV_BASE_BRANCH`) |
| `-w`, `--include-worktree` | Include staged/unstaged `lib/*.ex` vs merge-base |
| `--baseline-file PATH` | JSON `{"project_pct": N}` from a base-branch run |

Exit codes: **0** = green, **1** = project or patch failed, **2** = missing report or git error.

## How gates map to `codecov.yml`

| Codecov check | Local implementation |
|---------------|----------------------|
| **Project** target 88.25%, threshold 0.5% | Pass if project % ≥ **87.75%** (target − threshold). With `--baseline-file`, pass if current ≥ baseline − 0.5%. |
| **Patch** threshold 1% | Pass if ≥ **99%** of relevant executable lines in the diff are hit (≤1% uncovered). |

Diff scope:

- `MERGE_BASE=$(git merge-base HEAD "$BASE")`
- Committed patch: `git diff -U0 $MERGE_BASE..HEAD -- lib/`
- Worktree (optional): also `git diff --cached` and `git diff` under `lib/`

Uses only **local** refs (`master`, `HEAD`, merge-base). `git fetch` is not required.

## Generate coverage

```bash
mix coveralls.json
```

Artifact: `cover/excoveralls.json` (same as CI). Uses `test_full` per `mix.exs`; allow several minutes.

## Default branch and changed files

```bash
BASE="${CODECOV_BASE_BRANCH:-master}"
MB=$(git merge-base HEAD "$BASE")
git diff "${MB}..HEAD" --name-only -- 'lib/**/*.ex'
```

## Inspect uncovered lines (optional)

After a patch `FAIL`, the script lists `path:line`. For more detail with `jq`:

```bash
BASE="${CODECOV_BASE_BRANCH:-master}"
MB=$(git merge-base HEAD "$BASE")
for f in $(git diff "${MB}..HEAD" --name-only -- 'lib/**/*.ex'); do
  jq -r --arg f "$f" '
    .source_files[]
    | select(.name == $f or .name == ("./" + $f))
    | . as $file
    | [$file.coverage | to_entries[] | select(.value == 0 or .value == null) | .key + 1]
    | select(length > 0)
    | "\($f): uncovered lines \(.)"
  ' cover/excoveralls.json 2>/dev/null
done
```

Cross-check line numbers with `git diff` hunks so tests target **patch** lines.

## Save project baseline (optional)

On a clean local base branch (e.g. `master`):

```bash
git checkout master
mix coveralls.json
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py \
  --save-baseline .coverage-baseline.json
git checkout -
```

Then on the feature branch:

```bash
mix coveralls.json
python3 .claude/skills/improve-code-coverage/scripts/check_codecov_local.py \
  --baseline-file .coverage-baseline.json
```

Add `.coverage-baseline.json` to `.gitignore` if you keep it locally.

## Writing tests (Glific)

| Area | Convention |
|------|------------|
| Layout | `test/glific/...` mirrors `lib/glific/...` |
| Case modules | `use Glific.DataCase, async: true` when isolated |
| Org context | DataCase or `Repo.put_organization_id/1` |
| HTTP | `Tesla.Mock` |
| Examples | `test/glific/flows/common_webhook_test.exs`, `test/support/fixtures.ex` |

```bash
mix test path/to/test_file.exs
```

## Thresholds (`codecov.yml`)

```yaml
coverage:
  status:
    project:
      default:
        target: 88.25
        threshold: "0.5%"
    patch:
      default:
        threshold: "1%"
```

## Troubleshooting

| Symptom | Likely fix |
|---------|------------|
| `missing report` | Run `mix coveralls.json` |
| `git failed` / no merge-base | Ensure local `master` (or `-b`) exists: `git branch master` |
| Patch `FAIL` with few lines | Add tests for listed `path:line`; re-run full loop |
| Project `FAIL` | Broader suite coverage; optional baseline comparison |
| Uncommitted changes ignored | Re-run with `--include-worktree` |
| DB errors in coveralls | `mix ecto.reset` in test env per README |
| Need exact Codecov UI after push | Use **make-branch-ready-for-review** Phase 4.2 (out of scope here) |

## Limits vs cloud Codecov

- Local patch uses unified-diff line mapping; edge cases (renames, huge hunks) may differ slightly from Codecov’s UI.
- Project gate without a baseline file uses an absolute floor (87.75%), not Codecov’s stored base-branch history.
- After push, CI Codecov remains the merge authority; run this skill first to avoid remote failures.

## Remote Codecov (out of scope)

Do **not** use `codecovcli` upload or `CODECOV_TOKEN` in this skill. For post-push verification, see **make-branch-ready-for-review**.
