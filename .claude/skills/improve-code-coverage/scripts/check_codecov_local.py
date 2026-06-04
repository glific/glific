#!/usr/bin/env python3
"""
Local Codecov gate for Glific — no network, no push, no CODECOV_TOKEN.

Mirrors codecov.yml status checks using cover/excoveralls.json and a local git
diff (merge-base..HEAD by default). Optional: include unstaged/staged changes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

PROJECT_TARGET = 88.25
PROJECT_THRESHOLD = 0.5
PATCH_MAX_UNCOVERED_PCT = 1.0


@dataclass
class GateResult:
    name: str
    passed: bool
    detail: str


def run_git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def merge_base(base_branch: str) -> str:
    try:
        return run_git("merge-base", "HEAD", base_branch)
    except subprocess.CalledProcessError:
        return run_git("rev-parse", base_branch)


def git_diff_chunks(base_branch: str, include_worktree: bool) -> tuple[str, list[str]]:
    """Return (human-readable diff label, list of unified diff chunks)."""
    mb = merge_base(base_branch)
    label = f"{mb}..HEAD"
    specs: list[list[str]] = [[f"{mb}..HEAD"]]

    if include_worktree:
        label += " + staged/unstaged"
        specs.append(["--cached"])
        specs.append([])

    chunks: list[str] = []
    for spec in specs:
        cmd = ["git", "diff", "-U0", "--diff-filter=ACMR", *spec, "--", "lib/"]
        try:
            chunks.append(subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL))
        except subprocess.CalledProcessError:
            chunks.append("")

    return label, chunks


def paths_in_diffs(chunks: list[str]) -> list[str]:
    paths: set[str] = set()
    for text in chunks:
        for line in text.splitlines():
            if line.startswith("+++ b/") and line.endswith(".ex"):
                paths.add(line[6:])
    return sorted(paths)


def load_coverage(report_path: Path) -> dict[str, list[int | None]]:
    data = json.loads(report_path.read_text())
    files: dict[str, list[int | None]] = {}
    for entry in data.get("source_files", []):
        name = entry["name"].lstrip("./")
        files[name] = entry.get("coverage", [])
    return files


def project_coverage(coverage: dict[str, list[int | None]]) -> float:
    relevant = covered = 0
    for lines in coverage.values():
        for v in lines:
            if v is None:
                continue
            relevant += 1
            if v > 0:
                covered += 1
    if relevant == 0:
        return 100.0
    return 100.0 * covered / relevant


def parse_patch_lines(diff_text: str) -> dict[str, set[int]]:
    """Map file path -> line numbers in the new version that appear in the diff."""
    by_file: dict[str, set[int]] = {}
    current: str | None = None
    new_line = 0

    for line in diff_text.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            if path.endswith(".ex"):
                current = path
                by_file.setdefault(current, set())
            else:
                current = None
            continue
        if current is None:
            continue
        if line.startswith("@@"):
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if m:
                new_line = int(m.group(1))
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("\\"):
            continue
        if line.startswith("+"):
            by_file[current].add(new_line)
            new_line += 1
        elif line.startswith("-"):
            continue
        else:
            by_file[current].add(new_line)
            new_line += 1

    return by_file


def patch_coverage(
    coverage: dict[str, list[int | None]],
    patch_lines: dict[str, set[int]],
) -> tuple[float, list[tuple[str, int]]]:
    relevant = covered = 0
    misses: list[tuple[str, int]] = []

    for path, lines in patch_lines.items():
        cov = coverage.get(path)
        if cov is None:
            continue
        for line_no in sorted(lines):
            idx = line_no - 1
            if idx < 0 or idx >= len(cov):
                continue
            v = cov[idx]
            if v is None:
                continue
            relevant += 1
            if v > 0:
                covered += 1
            else:
                misses.append((path, line_no))

    if relevant == 0:
        return 100.0, []
    pct = 100.0 * covered / relevant
    return pct, misses


def check_project(
    pct: float, baseline_pct: float | None
) -> GateResult:
    floor = PROJECT_TARGET - PROJECT_THRESHOLD
    if baseline_pct is not None:
        floor = max(floor, baseline_pct - PROJECT_THRESHOLD)
    passed = pct >= floor
    detail = f"{pct:.2f}% (required >= {floor:.2f}%"
    if baseline_pct is not None:
        detail += f"; base {baseline_pct:.2f}% - {PROJECT_THRESHOLD}%"
    detail += f"; target {PROJECT_TARGET}%)"
    return GateResult("project", passed, detail)


def check_patch(pct: float, misses: list[tuple[str, int]]) -> GateResult:
    min_pct = 100.0 - PATCH_MAX_UNCOVERED_PCT
    passed = pct >= min_pct
    detail = f"{pct:.2f}% (required >= {min_pct:.2f}%; ≤{PATCH_MAX_UNCOVERED_PCT}% uncovered in patch)"
    if misses and not passed:
        sample = ", ".join(f"{p}:{n}" for p, n in misses[:15])
        if len(misses) > 15:
            sample += f", … (+{len(misses) - 15} more)"
        detail += f"; uncovered: {sample}"
    return GateResult("patch", passed, detail)


def main() -> int:
    parser = argparse.ArgumentParser(description="Local Codecov gate (no upload)")
    parser.add_argument(
        "-f",
        "--report",
        default="cover/excoveralls.json",
        help="ExCoveralls JSON report path",
    )
    parser.add_argument(
        "-b",
        "--base",
        default=os.environ.get("CODECOV_BASE_BRANCH", "master"),
        help="Local base branch for merge-base diff (default: master)",
    )
    parser.add_argument(
        "-w",
        "--include-worktree",
        action="store_true",
        help="Also treat staged/unstaged lib/*.ex changes vs merge-base",
    )
    parser.add_argument(
        "--baseline-file",
        default=os.environ.get("CODECOV_BASELINE_FILE", ""),
        help="JSON file with {\"project_pct\": N} from base branch run",
    )
    parser.add_argument(
        "--save-baseline",
        metavar="PATH",
        help="Write {\"project_pct\": N} from report and exit (run on base branch)",
    )
    args = parser.parse_args()

    report = Path(args.report)
    if not report.is_file():
        print(f"error: missing report {report} (run mix coveralls.json first)", file=sys.stderr)
        return 2

    coverage = load_coverage(report)
    proj_pct = project_coverage(coverage)

    if args.save_baseline:
        out = Path(args.save_baseline)
        out.write_text(json.dumps({"project_pct": round(proj_pct, 4)}))
        print(f"saved baseline project_pct={proj_pct:.2f}% to {out}")
        return 0

    try:
        diff_label, chunks = git_diff_chunks(args.base, args.include_worktree)
        diff_text = "".join(chunks)
        _paths = paths_in_diffs(chunks)
    except subprocess.CalledProcessError as e:
        print(f"error: git failed: {e}", file=sys.stderr)
        return 2

    patch_lines = parse_patch_lines(diff_text)
    patch_pct, misses = patch_coverage(coverage, patch_lines)

    baseline_pct: float | None = None
    if args.baseline_file:
        bp = Path(args.baseline_file)
        if bp.is_file():
            baseline_pct = json.loads(bp.read_text()).get("project_pct")

    results = [
        check_project(proj_pct, baseline_pct),
        check_patch(patch_pct, misses),
    ]

    print(f"diff: {diff_label}")
    print(f"report: {report}")
    all_ok = True
    for r in results:
        status = "PASS" if r.passed else "FAIL"
        print(f"[{status}] {r.name}: {r.detail}")
        all_ok = all_ok and r.passed

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
