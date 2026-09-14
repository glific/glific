#!/usr/bin/env python3
"""Collect mechanical security evidence from one or more repositories.

Emits JSON on stdout. Every finding carries a file path and, where relevant, a
line number, so the assessment that consumes this output can cite its sources.

Secret *values* are never emitted. When a credential-shaped string is found the
output records the rule that matched and the location only. This matters: the
report this feeds is meant to be shared, and a tool that copies secrets into a
shareable artefact has made the problem worse.

Usage:
    python3 collect_evidence.py                      # current repo
    python3 collect_evidence.py --repo . --repo ../glific-frontend
    python3 collect_evidence.py --repo . --pretty
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

MAX_FILE_BYTES = 512_000
SKIP_DIR_PARTS = {
    ".git", "node_modules", "_build", "deps", "cover", "dist", "build",
    ".venv", "venv", "__pycache__", ".next", "priv/plts", "coverage",
}

# --- credential-shaped strings -------------------------------------------------
# Deliberately high-signal. A noisy scanner trains people to ignore it, which is
# worse than no scanner. Provider-specific prefixes and assignments of a literal
# to a secret-sounding name are the two patterns that are almost never a false
# positive.
SECRET_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("aws_access_key_id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github_token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("openai_key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b")),
    ("anthropic_key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b")),
    ("google_api_key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("slack_token", re.compile(r"\bxox[abprs]-[0-9A-Za-z-]{10,}\b")),
    ("stripe_key", re.compile(r"\b[sr]k_live_[0-9A-Za-z]{20,}\b")),
    ("private_key_block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("jwt_literal", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    (
        "hardcoded_secret_assignment",
        re.compile(
            r"""(?ix)
            \b(?:secret|password|passwd|api[_-]?key|access[_-]?token|
               auth[_-]?token|client[_-]?secret|private[_-]?key)\b
            \s*[:=]\s*
            ["'][^"'\s${}<>]{12,}["']
            """
        ),
    ),
]

# Assignments that read from the environment or a vault are the healthy pattern;
# exclude them so the scanner does not punish correct code.
SECRET_EXEMPT = re.compile(
    r"(?i)(System\.get_env|os\.environ|os\.getenv|process\.env|import\.meta\.env|"
    r"fetch_env|Application\.(get|fetch)_env|vault|secretsmanager|\$\{|<%=|"
    r"example|sample|dummy|placeholder|changeme|your[-_]?(key|token|secret)|"
    r"xxx+|fake|test[-_]?token)"
)

SECRET_FILENAMES = re.compile(
    r"(?i)(^|/)(\.env(\..+)?|.*\.secret\.exs|.*\.pem|.*\.p12|.*\.pfx|"
    r"id_rsa|id_ed25519|.*credentials\.json|service[-_]account.*\.json)$"
)

# --- agent / LLM surface -------------------------------------------------------
LLM_VENDORS = re.compile(
    r"(?i)\b(openai|anthropic|claude|gemini|vertexai|vertex_ai|bedrock|azure_openai|"
    r"langchain|llama_index|llamaindex|mistral|cohere|ollama|huggingface)\b"
)
MCP_MARKERS = re.compile(r"(?i)(\bmcp\b|modelcontextprotocol|fastmcp|@mcp\.tool|mcp_servers)")
PROMPT_MARKERS = re.compile(r"(?i)(system_prompt|system prompt|prompt_template|\bprompt\b\s*[:=])")

# --- dangerous sinks -----------------------------------------------------------
# These are the classes that actually got Hugging Face: indirection in a data
# format, or a template engine, reachable from user-supplied input.
PY = {".py"}
EX = {".ex", ".exs", ".eex", ".heex"}
JS = {".js", ".jsx", ".ts", ".tsx"}
ANY: set[str] = set()

# Each rule is scoped to the extensions where it means anything. Without this
# scoping, Elixir's ordinary `def eval(` trips the JavaScript and Python
# `eval(` rules, and a reviewer who sees `expression.ex` labelled "js_eval"
# stops believing the whole report — correctly.
SINK_RULES: list[tuple[str, re.Pattern[str], set[str]]] = [
    ("python_pickle", re.compile(r"\b(?:pickle|cPickle|dill|joblib)\.loads?\b"), PY),
    ("python_yaml_unsafe", re.compile(r"\byaml\.load\s*\((?![^)]*Safe)"), PY),
    ("python_eval_exec", re.compile(r"(?<![\w.])(?:eval|exec)\s*\("), PY),
    ("python_subprocess_shell", re.compile(r"shell\s*=\s*True"), PY),
    ("jinja_from_string", re.compile(r"\b(?:Template|from_string|Environment)\s*\("), PY),
    ("hdf5_external", re.compile(r"(?i)(h5py|hdf5|external_link|ExternalLink)"), PY | EX),
    ("elixir_code_eval", re.compile(r"\bCode\.(?:eval_string|eval_quoted|compile_string)\b"), EX),
    ("elixir_atom_from_input", re.compile(r"\bString\.to_atom\b"), EX),
    ("elixir_os_cmd", re.compile(r"\b(?:System\.cmd|:os\.cmd)\b"), EX),
    ("eex_from_string", re.compile(r"\bEEx\.eval_string\b"), EX),
    ("js_eval", re.compile(r"(?<![\w.])eval\s*\(|new\s+Function\s*\("), JS),
    ("js_dangerous_html", re.compile(r"dangerouslySetInnerHTML|\.innerHTML\s*="), JS),
    ("archive_extract", re.compile(r"(?i)(extractall|tarfile\.open|:zip\.unzip|\bunzip\()"), PY | EX | JS),
    # Matching SQL *keywords* plus interpolation cannot tell a GraphQL mutation
    # from a query, and in an Ecto + Apollo codebase nearly every hit is a `.gql`
    # document. Target the raw-execution APIs instead — those are few, always
    # worth a look, and a real ORM bypass shows up here and nowhere else.
    (
        "raw_sql_execution",
        re.compile(
            r"(?:Ecto\.Adapters\.SQL\.query|Repo\.query|\bfragment\s*\(|"
            r"cursor\.execute\s*\(|\.executemany\s*\(|"
            r"knex\.raw\s*\(|sequelize\.query\s*\(|db\.query\s*\()"
        ),
        PY | EX | JS,
    ),
]

# A raw-execution hit only becomes interesting when the statement is built
# rather than parameterised, so the interpolation check is applied on top.
INTERPOLATION = re.compile(r"#\{|\$\{|%\s*\(|f\"|f'|\+\s*[A-Za-z_]")

CODE_SUFFIXES = {
    ".ex", ".exs", ".eex", ".heex", ".py", ".js", ".jsx", ".ts", ".tsx",
    ".rb", ".go", ".java", ".sh", ".yml", ".yaml", ".json", ".toml", ".tf",
    ".dockerfile", ".conf", ".env", ".md",
}


def run(cmd: list[str], cwd: Path) -> str:
    try:
        out = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=60, check=False
        )
        return out.stdout
    except (subprocess.SubprocessError, OSError):
        return ""


def tracked_files(root: Path) -> list[str]:
    out = run(["git", "ls-files"], root)
    if out.strip():
        return [line for line in out.splitlines() if line.strip()]
    # Not a git checkout — walk instead, still bounded.
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_PARTS]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            found.append(rel)
        if len(found) > 20000:
            break
    return found


def skip(rel: str) -> bool:
    parts = set(Path(rel).parts)
    if parts & SKIP_DIR_PARTS:
        return True
    return any(marker in rel for marker in ("priv/plts", "/fixtures/vcr", ".min.js"))


def read_lines(path: Path) -> list[str]:
    try:
        if path.stat().st_size > MAX_FILE_BYTES:
            return []
        return path.read_text(encoding="utf-8", errors="replace").splitlines()
    except (OSError, ValueError):
        return []


TEST_PATH = re.compile(r"(?i)(^|/)(test|tests|spec|specs|__tests__|cypress|e2e)(/|$)|_test\.|\.test\.|_spec\.|\.spec\.")
COMMENT_LINE = re.compile(r"^\s*(#|//|\*|/\*|<!--|--)")
DOC_TOGGLE = re.compile(r'"""')


def classify_context(rel: str, line: str, in_doc: bool) -> str:
    """Say where a hit lives, so scoring can weight it honestly.

    A regex hit inside a docstring, a comment or a test fixture is usually the
    opposite of a defect — `expression.ex` names `Code.eval_quoted` in its
    moduledoc precisely to explain why it refuses to call it. Reporting those
    as findings is how a scanner loses its audience, so the context travels
    with every hit and the headline counts only production code.
    """
    if TEST_PATH.search(rel):
        return "test"
    if rel.lower().endswith((".md", ".txt", ".rst")):
        return "doc"
    if in_doc or COMMENT_LINE.match(line):
        return "doc"
    return "code"


def scan_repo(root: Path) -> dict[str, Any]:
    files = [f for f in tracked_files(root) if not skip(f)]
    is_git = bool(run(["git", "rev-parse", "--is-inside-work-tree"], root).strip())

    repo: dict[str, Any] = {
        "path": str(root),
        "name": root.name,
        "is_git_checkout": is_git,
        "default_branch_guess": run(
            ["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], root
        ).strip().replace("origin/", "") or None,
        "tracked_file_count": len(files),
        "stack": detect_stack(files),
        "secret_candidates": [],
        "tracked_secret_filenames": [],
        "gitignore_covers": {},
        "llm_surface": [],
        "mcp_surface": [],
        "dangerous_sinks": [],
        "workflows": [],
        "containers": [],
        "lockfiles": [],
        "security_tooling": [],
        "notes": [],
    }

    gitignore = read_lines(root / ".gitignore")
    ignore_text = "\n".join(gitignore)
    for needle in (".env", "*.secret.exs", "*.pem", "credentials"):
        repo["gitignore_covers"][needle] = needle in ignore_text

    for rel in files:
        abs_path = root / rel
        suffix = abs_path.suffix.lower()
        base = abs_path.name.lower()

        if SECRET_FILENAMES.search(rel) and not rel.endswith((".txt", ".example", ".sample")):
            repo["tracked_secret_filenames"].append(rel)

        if rel.startswith(".github/workflows/") and suffix in {".yml", ".yaml"}:
            repo["workflows"].append(inspect_workflow(abs_path, rel))

        if base in {"dockerfile", "dockerfile.dev"} or base.startswith("dockerfile"):
            repo["containers"].append(inspect_dockerfile(abs_path, rel))

        if base in {
            "mix.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
            "poetry.lock", "uv.lock", "requirements.txt", "gemfile.lock",
        }:
            repo["lockfiles"].append(rel)

        if suffix not in CODE_SUFFIXES and suffix != "":
            continue

        lines = read_lines(abs_path)
        if not lines:
            continue

        in_doc = False
        for idx, line in enumerate(lines, start=1):
            if len(DOC_TOGGLE.findall(line)) % 2 == 1:
                in_doc = not in_doc
                ctx_line_in_doc = True
            else:
                ctx_line_in_doc = in_doc

            if len(line) > 4000:
                continue

            ctx = classify_context(rel, line, ctx_line_in_doc)

            for rule, pattern in SECRET_RULES:
                if pattern.search(line) and not SECRET_EXEMPT.search(line):
                    repo["secret_candidates"].append(
                        {"rule": rule, "file": rel, "line": idx, "context": ctx}
                    )
                    break

            if LLM_VENDORS.search(line):
                repo["llm_surface"].append({"file": rel, "line": idx, "context": ctx})
            if MCP_MARKERS.search(line):
                repo["mcp_surface"].append({"file": rel, "line": idx, "context": ctx})

            for rule, pattern, langs in SINK_RULES:
                if langs and suffix not in langs:
                    continue
                if not pattern.search(line):
                    continue
                if rule == "raw_sql_execution" and not INTERPOLATION.search(line):
                    continue
                repo["dangerous_sinks"].append(
                    {"rule": rule, "file": rel, "line": idx, "context": ctx}
                )

    repo["security_tooling"] = detect_security_tooling(root, files)
    repo = summarise(repo)
    return repo


def detect_stack(files: list[str]) -> list[str]:
    stack = []
    names = set(files)
    if "mix.exs" in names:
        stack.append("elixir")
    if "package.json" in names:
        stack.append("node")
    if any(n in names for n in ("pyproject.toml", "requirements.txt", "setup.py")):
        stack.append("python")
    if any(n.endswith(".tf") for n in names):
        stack.append("terraform")
    if any(n.lower().startswith("dockerfile") or "/dockerfile" in n.lower() for n in names):
        stack.append("docker")
    return stack


def inspect_workflow(path: Path, rel: str) -> dict[str, Any]:
    lines = read_lines(path)
    text = "\n".join(lines)
    third_party = []
    for idx, line in enumerate(lines, start=1):
        m = re.search(r"uses:\s*([^\s#]+)", line)
        if not m:
            continue
        ref = m.group(1)
        if ref.startswith("./") or ref.startswith("docker://"):
            continue
        pinned = bool(re.search(r"@[0-9a-f]{40}$", ref))
        third_party.append({"action": ref, "sha_pinned": pinned, "line": idx})
    return {
        "file": rel,
        "declares_permissions": bool(re.search(r"^\s*permissions:", text, re.MULTILINE)),
        "uses_pull_request_target": "pull_request_target" in text,
        "uses_workflow_run": "workflow_run:" in text,
        "secrets_referenced": sorted(set(re.findall(r"secrets\.([A-Z0-9_]+)", text))),
        "third_party_actions": third_party,
        "unpinned_action_count": sum(1 for a in third_party if not a["sha_pinned"]),
    }


def inspect_dockerfile(path: Path, rel: str) -> dict[str, Any]:
    lines = read_lines(path)
    text = "\n".join(lines)
    return {
        "file": rel,
        "declares_non_root_user": bool(re.search(r"^\s*USER\s+(?!root\b)\S+", text, re.MULTILINE)),
        "has_healthcheck": "HEALTHCHECK" in text,
        "uses_add_remote": bool(re.search(r"^\s*ADD\s+https?://", text, re.MULTILINE)),
        "build_args_named_secret": sorted(
            set(re.findall(r"(?i)^\s*ARG\s+([A-Z0-9_]*(?:SECRET|TOKEN|KEY|PASSWORD)[A-Z0-9_]*)", text, re.MULTILINE))
        ),
    }


def detect_security_tooling(root: Path, files: list[str]) -> list[dict[str, Any]]:
    """Distinguish 'the tool is a dependency' from 'the tool runs in CI'.

    This gap is the single most common false sense of security in a repo: the
    scanner is installed, nobody runs it, and the dependency list implies
    coverage that does not exist.
    """
    tools = {
        "sobelow": ["sobelow"],
        "credo": ["credo"],
        "dialyzer": ["dialyxir", "dialyzer"],
        "trivy": ["trivy"],
        "codeql": ["codeql"],
        "semgrep": ["semgrep"],
        "gitleaks": ["gitleaks"],
        "trufflehog": ["trufflehog"],
        "dependabot": ["dependabot"],
        "npm_audit": ["npm audit", "yarn audit"],
        "mix_audit": ["mix_audit", "mix deps.audit"],
        "bandit_py": ["bandit"],
        "pip_audit": ["pip-audit"],
    }
    manifests = [
        f for f in files
        if Path(f).name in {"mix.exs", "package.json", "pyproject.toml", "requirements.txt"}
    ]
    workflow_files = [f for f in files if f.startswith(".github/")]

    manifest_text = "\n".join("\n".join(read_lines(root / f)) for f in manifests).lower()
    ci_text = "\n".join("\n".join(read_lines(root / f)) for f in workflow_files).lower()

    # An aggregate runner hides its roster behind one command. `mix check` in CI
    # tells you nothing about which tools actually run — .check.exs does, and a
    # tool set to `false` there is switched off on purpose. That is a different
    # and more interesting state than "never configured", because someone chose
    # it and the dependency list still implies coverage.
    aggregate = {"runner": None, "enabled": [], "disabled": []}
    check_exs = root / ".check.exs"
    if check_exs.is_file():
        check_text = "\n".join(read_lines(check_exs))
        aggregate["runner"] = ".check.exs"
        for name, state in re.findall(r"\{\s*:([a-z0-9_]+)\s*,\s*([^}]+)\}", check_text):
            if state.strip().startswith("false"):
                aggregate["disabled"].append(name)
            else:
                aggregate["enabled"].append(name)

    runner_in_ci = "mix check" in ci_text
    enabled_via_runner = set(aggregate["enabled"]) if runner_in_ci else set()
    disabled_via_runner = set(aggregate["disabled"])

    out: list[dict[str, Any]] = []
    for tool, needles in tools.items():
        declared = any(n in manifest_text for n in needles)
        direct_ci = any(n in ci_text for n in needles)
        via_runner = bool(enabled_via_runner & set(needles))
        disabled = bool(disabled_via_runner & set(needles))
        if not (declared or direct_ci or via_runner or disabled):
            continue
        out.append({
            "tool": tool,
            "declared_as_dependency": declared,
            "runs_in_ci": direct_ci or via_runner,
            "how": "direct" if direct_ci else ("aggregate_runner" if via_runner else None),
            "explicitly_disabled_in_runner": disabled,
        })
    if aggregate["runner"]:
        out.append({
            "tool": "_aggregate_runner",
            "declared_as_dependency": True,
            "runs_in_ci": runner_in_ci,
            "how": aggregate["runner"],
            "enabled_tools": sorted(aggregate["enabled"]),
            "disabled_tools": sorted(aggregate["disabled"]),
        })
    return out


def summarise(repo: dict[str, Any]) -> dict[str, Any]:
    """Collapse per-line hits into per-file counts.

    Raw hit lists get long enough to crowd out the analysis that matters; the
    detail stays available but the summary is what a reader needs first.
    """
    def by_file(hits: list[dict[str, Any]], key: str | None = None) -> list[dict[str, Any]]:
        agg: dict[tuple, dict[str, Any]] = {}
        for hit in hits:
            k = (hit["file"], hit.get(key) if key else None)
            entry = agg.setdefault(
                k,
                {"file": hit["file"], **({key: hit.get(key)} if key else {}), "count": 0, "first_line": hit["line"]},
            )
            entry["count"] += 1
            entry["first_line"] = min(entry["first_line"], hit["line"])
        return sorted(agg.values(), key=lambda e: (-e["count"], e["file"]))

    def code_only(hits: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [h for h in hits if h.get("context") == "code"]

    def ctx_counts(hits: list[dict[str, Any]]) -> dict[str, int]:
        counts: dict[str, int] = {}
        for hit in hits:
            counts[hit.get("context", "code")] = counts.get(hit.get("context", "code"), 0) + 1
        return counts

    repo["summary"] = {
        "secret_candidates_in_code": len(code_only(repo["secret_candidates"])),
        "secret_candidates_by_context": ctx_counts(repo["secret_candidates"]),
        "secret_candidates_by_rule": by_file(code_only(repo["secret_candidates"]), "rule")[:40],
        "secret_candidates_in_tests_or_docs": by_file(
            [h for h in repo["secret_candidates"] if h.get("context") != "code"], "rule"
        )[:20],
        "tracked_secret_filename_count": len(repo["tracked_secret_filenames"]),
        "llm_surface_files": [e["file"] for e in by_file(code_only(repo["llm_surface"]))][:40],
        "llm_surface_file_count": len({e["file"] for e in code_only(repo["llm_surface"])}),
        "mcp_surface_files": [e["file"] for e in by_file(code_only(repo["mcp_surface"]))][:25],
        "dangerous_sinks_by_rule": by_file(code_only(repo["dangerous_sinks"]), "rule")[:60],
        "dangerous_sinks_in_code": len(code_only(repo["dangerous_sinks"])),
        "dangerous_sinks_by_context": ctx_counts(repo["dangerous_sinks"]),
        "workflow_count": len(repo["workflows"]),
        "workflows_without_permissions": [
            w["file"] for w in repo["workflows"] if not w["declares_permissions"]
        ],
        "workflows_with_pull_request_target": [
            w["file"] for w in repo["workflows"] if w["uses_pull_request_target"]
        ],
        "unpinned_third_party_actions": sum(w["unpinned_action_count"] for w in repo["workflows"]),
        "ci_secret_names": sorted({
            name for w in repo["workflows"] for name in w["secrets_referenced"]
        }),
        "containers_running_as_root": [
            c["file"] for c in repo["containers"] if not c["declares_non_root_user"]
        ],
        "security_tools_declared_but_not_in_ci": [
            t["tool"] for t in repo["security_tooling"]
            if t["tool"] != "_aggregate_runner"
            and t["declared_as_dependency"] and not t["runs_in_ci"]
        ],
        "security_tools_explicitly_disabled": [
            t["tool"] for t in repo["security_tooling"]
            if t.get("explicitly_disabled_in_runner")
        ],
    }
    # Detail lists are kept but truncated; the summary is the contract.
    for key in ("secret_candidates", "llm_surface", "mcp_surface", "dangerous_sinks"):
        repo[key] = repo[key][:200]
    return repo


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo", action="append", default=None,
        help="Repository root to scan. Repeat for several. Defaults to the current directory.",
    )
    parser.add_argument("--pretty", action="store_true", help="Indent the JSON output.")
    parser.add_argument("--out", help="Write JSON to this path instead of stdout.")
    args = parser.parse_args()

    roots = [Path(p).resolve() for p in (args.repo or ["."])]
    missing = [str(r) for r in roots if not r.is_dir()]
    if missing:
        print(f"error: not a directory: {', '.join(missing)}", file=sys.stderr)
        return 2

    result = {
        "schema": "glific-ai-security-evidence/1",
        "generated_by": "collect_evidence.py",
        "repos": [scan_repo(r) for r in roots],
        "caveats": [
            "Secret values are never included; only rule name and location.",
            "Findings are candidates, not confirmed defects. Every one needs reading in context.",
            "Absence of a finding is not evidence of absence — see the 'unknown' rules in SKILL.md.",
        ],
    }

    payload = json.dumps(result, indent=2 if args.pretty else None, sort_keys=False)
    if args.out:
        Path(args.out).write_text(payload + "\n", encoding="utf-8")
        print(f"wrote {args.out}", file=sys.stderr)
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
