#!/usr/bin/env bash
#
# gigalixir-verify-deploy.sh - confirm a Gigalixir deploy actually went live and stayed live.
#
# Gigalixir rolls a bad release back automatically, and the app reports "healthy" again
# once it has. A deploy that never took therefore looks identical to a deploy that worked
# if you only check once. This script watches the rollout for a sustained window so a
# rollback is loud instead of silent.
#
#   Phase A  release picked up  - the pushed sha shows up in `gigalixir releases`
#   Phase B  converge           - every pod reaches that release and reports Healthy
#   Phase C  stability          - that state holds continuously for --stable-window
#
# Read-only: it never pushes, restarts, scales, or rolls anything back.
#
# Usage
#   bin/gigalixir-verify-deploy.sh --env staging
#   bin/gigalixir-verify-deploy.sh --env staging --probe        # one poll, print + exit
#   bin/gigalixir-verify-deploy.sh --app glific-staging --sha abc1234
#   bin/gigalixir-verify-deploy.sh --ci --app "$APP" --sha "$GITHUB_SHA"
#
# Exit codes
#   0 verified   2 release never appeared   3 never converged   4 rolled back
#   5 unhealthy  6 superseded by a newer release
#   1 usage / precondition failure

set -uo pipefail

readonly E_OK=0 E_USAGE=1 E_NO_RELEASE=2 E_NO_CONVERGE=3
readonly E_ROLLBACK=4 E_UNHEALTHY=5 E_SUPERSEDED=6

# --------------------------------------------------------------------------------------
# Deploy targets. Add a row here rather than editing the script body.
#   env|app name|git remote
# --------------------------------------------------------------------------------------
readonly TARGETS="
staging|glific-staging|staging
frontend-staging|glific-frontend-staging|gigalixir
production|glific|production
"

# --------------------------------------------------------------------------------------
# Field extraction. The Gigalixir CLI's JSON keys are not contractual, so every lookup
# falls back through the plausible spellings. If a key is wrong for your account, run
# --probe to see the raw payload and fix the one expression here.
# --------------------------------------------------------------------------------------
readonly JQ_REL_LIST='if type=="array" then . else (.releases // [.]) end'
readonly JQ_REL_SHA='((.sha // .commit // .git_sha // .revision // "") | tostring)'
readonly JQ_REL_VER='((.version // .release_version // .build_number // "") | tostring)'
readonly JQ_REL_APPVER='((.customer_app_version // .app_version // "") | tostring)'
readonly JQ_PODS='(.pods // .Pods // [])'
readonly JQ_POD_NAME='((.name // .Name // "?") | tostring)'
readonly JQ_POD_STATUS='((.status // .Status // "") | tostring)'
readonly JQ_POD_VER='((.version // .Version // "") | tostring)'
readonly HEALTHY_RE='^(healthy|running)$'

ENV_NAME="" APP="" SHA="" APP_VERSION=""
POLL=5 RELEASE_TIMEOUT=300 CONVERGE_TIMEOUT=300 STABLE_WINDOW=300
FLAP_TOLERANCE=3
CI_MODE=0 DEBUG=0 PROBE=0

usage() { sed -n '2,25p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; }

die() {
  printf '%s\n' "error: $*" >&2
  exit "$E_USAGE"
}

log() {
  printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"
}

# GitHub renders ::error:: as an annotation on the job; harmless noise anywhere else.
fail_annotation() {
  [ "$CI_MODE" -eq 1 ] || return 0
  printf '::error title=Gigalixir deploy verification failed::%s\n' "$*"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '**Deploy verification failed** - %s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  return 0
}

# Posts a Discord embed, falling back to nothing if no webhook is set. $1=ok|fail,
# $2=reason (failures only). Success stays terse - a 🟢 title and the facts; failures
# carry the reason. Reads APP / SHA / TARGET_VERSION / POD_NODE from the surrounding run.
notify() {
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] || return 0
  local kind="$1" desc="${2:-}" color title
  case "$kind" in
    ok) color=3066993; title="🟢 ${APP} deployment healthy" ;;
    fail) color=15158332; title="🔴 ${APP} deployment failed" ;;
    *) color=9807270; title="${APP} deployment" ;;
  esac

  local payload
  payload=$(jq -nc \
    --arg title "$title" \
    --arg desc "$desc" \
    --argjson color "$color" \
    --arg sha "${SHA:0:7}" \
    --arg rel "${TARGET_VERSION:-unknown}" \
    --arg node "${POD_NODE:-unknown}" \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{embeds:[
       ({ title: $title, color: $color, timestamp: $ts,
          fields: [
            {name: "Release", value: $rel,  inline: true},
            {name: "SHA",     value: $sha,  inline: true},
            {name: "Node",    value: $node, inline: false}
          ]
        } + (if $desc == "" then {} else {description: $desc} end))
     ]}')

  curl -fsS -m 10 -X POST "$DISCORD_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    --data "$payload" >/dev/null 2>&1 || true
}

# A value-taking flag passed as the last token leaves no $2 to consume; `shift 2`
# would then fail silently and the while-loop would spin on the same flag forever.
# need "$@" asserts a value follows before we shift past it.
need() { [ "$#" -ge 2 ] || die "missing value for $1"; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) need "$@"; ENV_NAME="$2"; shift 2 ;;
      --app) need "$@"; APP="$2"; shift 2 ;;
      --sha) need "$@"; SHA="$2"; shift 2 ;;
      --app-version) need "$@"; APP_VERSION="$2"; shift 2 ;;
      --poll) need "$@"; POLL="$2"; shift 2 ;;
      --release-timeout) need "$@"; RELEASE_TIMEOUT="$2"; shift 2 ;;
      --converge-timeout) need "$@"; CONVERGE_TIMEOUT="$2"; shift 2 ;;
      --stable-window) need "$@"; STABLE_WINDOW="$2"; shift 2 ;;
      --flap-tolerance) need "$@"; FLAP_TOLERANCE="$2"; shift 2 ;;
      --ci) CI_MODE=1; shift ;;
      --debug) DEBUG=1; shift ;;
      --probe) PROBE=1; shift ;;
      -h|--help) usage; exit "$E_OK" ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done
}

resolve_target() {
  if [ -n "$ENV_NAME" ]; then
    local row
    row=$(printf '%s' "$TARGETS" | grep "^${ENV_NAME}|") || die "unknown --env '$ENV_NAME'"
    [ -n "$APP" ] || APP=$(printf '%s' "$row" | cut -d'|' -f2)
  fi

  [ -n "$APP" ] || die "need --app or --env (one of: staging frontend-staging production)"

  if [ -z "$SHA" ]; then
    SHA=$(git rev-parse HEAD 2>/dev/null) || die "not in a git repo; pass --sha explicitly"
  fi
  SHA=$(printf '%s' "$SHA" | tr '[:upper:]' '[:lower:]')
}

preflight() {
  command -v gigalixir >/dev/null 2>&1 || die "gigalixir CLI not found"
  command -v jq >/dev/null 2>&1 || die "jq not found (brew install jq)"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  for n in "$POLL" "$RELEASE_TIMEOUT" "$CONVERGE_TIMEOUT" "$STABLE_WINDOW" "$FLAP_TOLERANCE"; do
    case "$n" in ''|*[!0-9]*) die "timeouts and counts must be integers, got '$n'" ;; esac
  done
  [ "$POLL" -ge 1 ] || die "--poll must be at least 1"
}

# The gigalixir CLI prepends a "new version available" banner to stdout, which is not
# JSON and makes jq choke. Print from the first line that *starts* with [ or { (the JSON
# opening) onward. Anchoring to the line start avoids matching a banner like
# "update [1.2.3] available", whose bracket sits mid-line.
strip_banner() {
  sed -n '/^[[:space:]]*[[{]/,$p'
}

# Both fetchers echo raw JSON on stdout and return non-zero if the CLI failed or the
# payload was not JSON, so a transient API blip is a skipped poll rather than a crash.
fetch_releases() {
  local out
  out=$(gigalixir releases -a "$APP" 2>/dev/null | strip_banner) || return 1
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s' "$out"
}

fetch_ps() {
  local out
  out=$(gigalixir ps -a "$APP" 2>/dev/null | strip_banner) || return 1
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s' "$out"
}

debug_dump() {
  [ "$DEBUG" -eq 1 ] || return 0
  printf -- '--- raw %s ---\n%s\n--- end ---\n' "$1" "$2"
}

# Find the release matching our sha (or app version) anywhere in the list, so we never
# depend on the API returning newest-first. Echoes "version<TAB>sha<TAB>app_version".
match_release() {
  local json="$1" sha7="${SHA:0:7}"
  printf '%s' "$json" | jq -r --arg sha7 "$sha7" --arg av "$APP_VERSION" "
    $JQ_REL_LIST
    | map(select(
        ((${JQ_REL_SHA} | ascii_downcase)[0:7] == \$sha7)
        or (\$av != \"\" and ${JQ_REL_APPVER} == \$av)
      ))
    | (.[0] // empty)
    | [${JQ_REL_VER}, ${JQ_REL_SHA}, ${JQ_REL_APPVER}] | @tsv
  " 2>/dev/null
}

max_release_version() {
  printf '%s' "$1" | jq -r "
    $JQ_REL_LIST | map(${JQ_REL_VER} | select(test(\"^[0-9]+$\")) | tonumber)
    | (max // empty)
  " 2>/dev/null
}

# Echoes "name<TAB>status<TAB>version" per pod.
pod_rows() {
  printf '%s' "$1" | jq -r "$JQ_PODS | .[] | [${JQ_POD_NAME}, ${JQ_POD_STATUS}, ${JQ_POD_VER}] | @tsv" 2>/dev/null
}

replica_counts() {
  printf '%s' "$1" | jq -r '[(.replicas_running // -1), (.replicas_desired // -1)] | @tsv' 2>/dev/null
}

# Reads pod state once. Sets POD_SUMMARY / POD_TOTAL / POD_AT_TARGET / POD_HEALTHY_AT_TARGET
# / POD_BEHIND / POD_AHEAD. Returns non-zero if the API call itself failed.
inspect_pods() {
  local target="$1" ps_json rows counts running desired
  ps_json=$(fetch_ps) || return 1
  debug_dump "gigalixir ps" "$ps_json"

  rows=$(pod_rows "$ps_json")
  counts=$(replica_counts "$ps_json")
  running=$(printf '%s' "$counts" | cut -f1)
  desired=$(printf '%s' "$counts" | cut -f2)

  POD_TOTAL=0 POD_AT_TARGET=0 POD_HEALTHY_AT_TARGET=0 POD_BEHIND=0 POD_AHEAD=0
  POD_SUMMARY="" POD_NODE=""

  local name status version status_lc
  while IFS=$'\t' read -r name status version; do
    [ -n "${name:-}" ] || continue
    POD_TOTAL=$((POD_TOTAL + 1))
    status_lc=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
    POD_SUMMARY="${POD_SUMMARY}${POD_SUMMARY:+, }${name}:${status:-?}@v${version:-?}"

    if [ "$version" = "$target" ]; then
      POD_AT_TARGET=$((POD_AT_TARGET + 1))
      if [[ "$status_lc" =~ $HEALTHY_RE ]]; then
        POD_HEALTHY_AT_TARGET=$((POD_HEALTHY_AT_TARGET + 1))
        POD_NODE="$name"
      fi
    elif [[ "$version" =~ ^[0-9]+$ ]] && [[ "$target" =~ ^[0-9]+$ ]]; then
      if [ "$version" -lt "$target" ]; then POD_BEHIND=$((POD_BEHIND + 1)); else POD_AHEAD=$((POD_AHEAD + 1)); fi
    fi
  done <<<"$rows"

  POD_REPLICAS="${running}/${desired}"
  # replicas_desired of -1 means the key was absent; treat pod count as authoritative then.
  if [ "$desired" -ge 0 ] 2>/dev/null; then POD_DESIRED="$desired"; else POD_DESIRED="$POD_TOTAL"; fi
  return 0
}

run_probe() {
  local rel_json ps_json match
  log "probing ${APP} (read-only, no waiting)"

  if rel_json=$(fetch_releases); then
    printf -- '--- gigalixir releases -a %s ---\n%s\n' "$APP" "$rel_json"
    match=$(match_release "$rel_json")
    if [ -n "$match" ]; then
      printf 'parsed: release matching sha %s -> version=%s sha=%s app_version=%s\n' \
        "${SHA:0:7}" "$(printf '%s' "$match" | cut -f1)" \
        "$(printf '%s' "$match" | cut -f2)" "$(printf '%s' "$match" | cut -f3)"
    else
      printf 'parsed: NO release matches sha %s (expected if this sha was never deployed)\n' "${SHA:0:7}"
    fi
    printf 'parsed: highest release version = %s\n' "$(max_release_version "$rel_json")"
  else
    printf 'FAILED to read releases - check `gigalixir releases -a %s` by hand\n' "$APP"
  fi

  if ps_json=$(fetch_ps); then
    printf -- '--- gigalixir ps -a %s ---\n%s\n' "$APP" "$ps_json"
    printf 'parsed pods (name/status/version):\n%s\n' "$(pod_rows "$ps_json")"
    printf 'parsed replicas (running/desired): %s\n' "$(replica_counts "$ps_json")"
  else
    printf 'FAILED to read ps - check `gigalixir ps -a %s` by hand\n' "$APP"
  fi

  printf '\nIf any "parsed" line above is empty but the raw JSON has the data,\nadjust the JQ_* expressions near the top of this script.\n'
}

# Phase A -------------------------------------------------------------------------------
wait_for_release() {
  local deadline=$((SECONDS + RELEASE_TIMEOUT)) rel_json match

  log "phase A: waiting for sha ${SHA:0:7} to appear in ${APP}'s releases (timeout ${RELEASE_TIMEOUT}s)"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if rel_json=$(fetch_releases); then
      debug_dump "gigalixir releases" "$rel_json"
      match=$(match_release "$rel_json")
      if [ -n "$match" ]; then
        TARGET_VERSION=$(printf '%s' "$match" | cut -f1)
        TARGET_APPVER=$(printf '%s' "$match" | cut -f3)
        MAX_VERSION=$(max_release_version "$rel_json")
        [ -n "$TARGET_VERSION" ] || { log "release matched but has no version field; run --debug"; return "$E_NO_RELEASE"; }
        log "phase A ok: release v${TARGET_VERSION} (app version ${TARGET_APPVER:-unknown})"
        return "$E_OK"
      fi
    else
      log "  releases lookup failed, retrying"
    fi
    sleep "$POLL"
  done

  log "phase A FAILED: sha ${SHA:0:7} never showed up in ${APP}'s releases within ${RELEASE_TIMEOUT}s"
  return "$E_NO_RELEASE"
}

# Phase B -------------------------------------------------------------------------------
wait_for_converge() {
  local deadline=$((SECONDS + CONVERGE_TIMEOUT))

  log "phase B: waiting for every pod to run v${TARGET_VERSION} and report healthy (timeout ${CONVERGE_TIMEOUT}s)"
  while [ "$SECONDS" -lt "$deadline" ]; do
    if inspect_pods "$TARGET_VERSION"; then
      if [ "$POD_AHEAD" -gt 0 ]; then
        log "phase B FAILED: a pod is running a newer release than v${TARGET_VERSION} - someone deployed over this one [$POD_SUMMARY]"
        return "$E_SUPERSEDED"
      fi
      if [ "$POD_TOTAL" -gt 0 ] && [ "$POD_HEALTHY_AT_TARGET" -eq "$POD_TOTAL" ] && [ "$POD_TOTAL" -ge "$POD_DESIRED" ]; then
        log "phase B ok: ${POD_TOTAL}/${POD_DESIRED} pods healthy on v${TARGET_VERSION} [$POD_SUMMARY]"
        return "$E_OK"
      fi
      log "  ${POD_HEALTHY_AT_TARGET}/${POD_TOTAL} healthy on target, replicas ${POD_REPLICAS} [$POD_SUMMARY]"
    else
      log "  ps lookup failed, retrying"
    fi
    sleep "$POLL"
  done

  log "phase B FAILED: pods never all reached a healthy v${TARGET_VERSION} within ${CONVERGE_TIMEOUT}s [${POD_SUMMARY:-no pod data}]"
  return "$E_NO_CONVERGE"
}

# Phase C -------------------------------------------------------------------------------
# A pod dropping to an older release is unambiguous - Gigalixir rolled us back - so that
# fails on sight. Anything else (a single pod restarting, an API blip) gets
# --flap-tolerance consecutive polls to recover before it counts as a failure.
watch_stability() {
  local deadline=$((SECONDS + STABLE_WINDOW)) strikes=0 last_log=0

  log "phase C: holding v${TARGET_VERSION} for ${STABLE_WINDOW}s to prove it does not roll back"
  while [ "$SECONDS" -lt "$deadline" ]; do
    sleep "$POLL"

    if ! inspect_pods "$TARGET_VERSION"; then
      strikes=$((strikes + 1))
      log "  ps lookup failed (${strikes}/${FLAP_TOLERANCE})"
      [ "$strikes" -ge "$FLAP_TOLERANCE" ] && { log "phase C FAILED: cannot read pod state"; return "$E_UNHEALTHY"; }
      continue
    fi

    if [ "$POD_BEHIND" -gt 0 ]; then
      log "phase C FAILED: ROLLED BACK - ${POD_BEHIND} pod(s) reverted to an older release [$POD_SUMMARY]"
      return "$E_ROLLBACK"
    fi

    if [ "$POD_AHEAD" -gt 0 ]; then
      log "phase C FAILED: superseded - a newer release is rolling out [$POD_SUMMARY]"
      return "$E_SUPERSEDED"
    fi

    if [ "$POD_TOTAL" -eq 0 ] || [ "$POD_HEALTHY_AT_TARGET" -ne "$POD_TOTAL" ]; then
      strikes=$((strikes + 1))
      log "  unhealthy (${strikes}/${FLAP_TOLERANCE}) [$POD_SUMMARY]"
      [ "$strikes" -ge "$FLAP_TOLERANCE" ] && {
        log "phase C FAILED: pods stayed unhealthy on v${TARGET_VERSION} [$POD_SUMMARY]"
        return "$E_UNHEALTHY"
      }
      continue
    fi

    strikes=0
    if [ $((SECONDS - last_log)) -ge 30 ]; then
      log "  stable, $((deadline - SECONDS))s remaining [$POD_SUMMARY]"
      last_log=$SECONDS
    fi
  done

  log "phase C ok: v${TARGET_VERSION} held healthy for the full ${STABLE_WINDOW}s"
  return "$E_OK"
}

main() {
  parse_args "$@"
  resolve_target
  preflight

  if [ "$PROBE" -eq 1 ]; then
    run_probe
    exit "$E_OK"
  fi

  log "app=${APP} sha=${SHA:0:7}"
  log "budget: up to $((RELEASE_TIMEOUT + CONVERGE_TIMEOUT + STABLE_WINDOW))s total"

  local rc
  wait_for_release; rc=$?
  if [ "$rc" -eq "$E_OK" ]; then wait_for_converge; rc=$?; fi
  if [ "$rc" -eq "$E_OK" ]; then watch_stability; rc=$?; fi

  if [ "$rc" -eq "$E_OK" ]; then
    log "VERIFIED: ${APP} is live on release v${TARGET_VERSION} and stable"
    notify ok
  else
    local reason
    case "$rc" in
      "$E_NO_RELEASE") reason="release never registered" ;;
      "$E_NO_CONVERGE") reason="pods never became healthy on the new release" ;;
      "$E_ROLLBACK") reason="ROLLED BACK to an older release" ;;
      "$E_UNHEALTHY") reason="pods went unhealthy after deploy" ;;
      "$E_SUPERSEDED") reason="superseded by another deploy" ;;
      *) reason="unknown failure" ;;
    esac
    log "DEPLOY VERIFICATION FAILED (${reason})"
    log "investigate: gigalixir logs -a ${APP} ; gigalixir ps -a ${APP} ; gigalixir releases -a ${APP}"
    fail_annotation "${APP}: ${reason}"
    notify fail "$reason"
  fi
  exit "$rc"
}

main "$@"
