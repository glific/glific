#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-30}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
DISCORD_MENTION_ROLE_ID="${DISCORD_MENTION_ROLE_ID:-}"
SMOKE_TEST_URL="${SMOKE_TEST_URL:-}"
SMOKE_TEST_ATTEMPTS="${SMOKE_TEST_ATTEMPTS:-3}"
APPSIGNAL_CPU_COUNT=""
LAST_LOG_FILE=$(mktemp)
DISCORD_MESSAGE_ID=""
FROM_SIZE=""
DIRECTION=""
NODE=""
DURATION=""
SMOKE_RESULT=""
STARTED_AT=""

log() {
  echo "[$(date -u +%FT%TZ)] $*"
  # Kept in a file so lines logged inside $(...) subshells still reach the failure notification.
  printf '%s' "$*" >"$LAST_LOG_FILE"
}

http() { curl -sS --connect-timeout 10 --max-time "$REQUEST_TIMEOUT_SECONDS" "$@"; }

discord_title() {
  local app=${GIGALIXIR_APP:-unknown}
  case "$1" in
    progress) echo "🟡 ${app} resizing ${DIRECTION}" ;;
    ok) echo "🟢 ${app} resized ${DIRECTION}" ;;
    smoke_fail) echo "🔴 ${app} smoke test failed after resizing ${DIRECTION}" ;;
    fail) echo "🔴 ${app} resize failed" ;;
  esac
}

# Same embed layout and colours as bin/gigalixir-verify-deploy.sh.
# $1=progress|ok|smoke_fail|fail, $2=reason. $1=ping posts only a role mention plus the $2 text.
discord_payload() {
  local kind=$1 reason=${2:-} color

  if [[ "$kind" == ping ]]; then
    jq -nc --arg text "$reason" --arg role "$DISCORD_MENTION_ROLE_ID" \
      '{content: ((if $role == "" then "" else "<@&\($role)> " end) + $text),
        allowed_mentions: {roles: (if $role == "" then [] else [$role] end)}}'
    return
  fi

  case "$kind" in
    progress) color=16705372 ;;
    ok) color=3066993 ;;
    smoke_fail | fail) color=15158332 ;;
  esac

  jq -nc \
    --arg title "$(discord_title "$kind")" \
    --argjson color "$color" \
    --arg reason "${reason:0:1000}" \
    --arg role "$DISCORD_MENTION_ROLE_ID" \
    --arg size "${FROM_SIZE:-?} → ${TARGET_SIZE:-?}" \
    --arg duration "$DURATION" \
    --arg smoke "$SMOKE_RESULT" \
    --arg node "$NODE" \
    --arg cpus "$APPSIGNAL_CPU_COUNT" \
    --arg execution "${CLOUD_RUN_EXECUTION:-local run}" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{
       content: (if $role == "" then "" else "<@&\($role)>" end),
       allowed_mentions: {roles: (if $role == "" then [] else [$role] end)},
       embeds: [
         {title: $title, color: $color, timestamp: $ts,
          fields: ([
            {name: "Size", value: $size, inline: true},
            {name: "Duration", value: $duration, inline: true},
            {name: "Smoke test", value: $smoke, inline: true},
            {name: "AppSignal CPUs", value: $cpus, inline: true},
            {name: "Node", value: $node, inline: false},
            {name: "Execution", value: $execution, inline: false}
          ] | map(select(.value != "")))}
         + (if $reason == "" then {} else {description: $reason} end)
       ]
     }'
}

# Prints the new message's id so it can be edited later. Never fails the job.
discord_post() {
  [[ -n "$DISCORD_WEBHOOK_URL" ]] || return 0
  local separator='?'
  [[ "$DISCORD_WEBHOOK_URL" == *\?* ]] && separator='&'
  http --fail -H 'Content-Type: application/json' -d "$(discord_payload "$@")" \
    "${DISCORD_WEBHOOK_URL}${separator}wait=true" | jq -r '.id // empty' ||
    echo "Failed to send Discord notification" >&2
}

discord_edit() {
  [[ -n "$DISCORD_WEBHOOK_URL" && -n "$DISCORD_MESSAGE_ID" ]] || return 0
  local query=""
  [[ "$DISCORD_WEBHOOK_URL" == *\?* ]] && query="?${DISCORD_WEBHOOK_URL#*\?}"
  http -o /dev/null --fail -X PATCH -H 'Content-Type: application/json' -d "$(discord_payload "$@")" \
    "${DISCORD_WEBHOOK_URL%%\?*}/messages/${DISCORD_MESSAGE_ID}${query}" ||
    echo "Failed to update Discord notification" >&2
}

notify_failure() {
  local exit_code=$? last_log
  last_log=$(cat "$LAST_LOG_FILE" 2>/dev/null || true)
  rm -f "$LAST_LOG_FILE"

  if [[ $exit_code -ne 0 ]]; then
    last_log=${last_log:-unknown, check the job logs}

    if [[ "$SMOKE_RESULT" == "Running" ]]; then
      # The resize itself succeeded: keep its message green and report the smoke test on its own.
      SMOKE_RESULT="Failed"
      discord_edit ok
      discord_post smoke_fail "$last_log" >/dev/null
    elif [[ -n "$DISCORD_MESSAGE_ID" ]]; then
      DURATION="$((SECONDS - STARTED_AT))s"
      [[ "$SMOKE_RESULT" == "Pending" ]] && SMOKE_RESULT="Not run"
      discord_edit fail "$last_log"
      # Edits don't notify anyone, so a short follow-up pings the role to point at the updated message.
      discord_post ping "$(discord_title fail), see the message above" >/dev/null
    else
      discord_post fail "$last_log" >/dev/null
    fi
  fi

  # Re-raise the original status so Cloud Run still sees the failure.
  exit "$exit_code"
}

trap notify_failure EXIT

required_vars=(GIGALIXIR_APP TARGET_SIZE GIGALIXIR_USERNAME GIGALIXIR_PASSWORD)
[[ -n "$SMOKE_TEST_URL" ]] && required_vars+=(SMOKE_TEST_PHONE SMOKE_TEST_PASSWORD)

for var in "${required_vars[@]}"; do
  [[ -n "${!var:-}" ]] || { log "${var} is required"; exit 1; }
done

if [[ -n "$SMOKE_TEST_URL" && "$SMOKE_TEST_URL" != https://* ]]; then
  log "SMOKE_TEST_URL must use https:// so the smoke-test credentials are encrypted in transit"
  exit 1
fi

if [[ ! "$TARGET_SIZE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  log "TARGET_SIZE must be a number, got '${TARGET_SIZE}'"
  exit 1
fi

# A Gigalixir replica gets 2 CPUs per 3 units of size. AppSignal parses this with
# binary_to_float, so "8" crashes the app on boot while "8.0" works.
APPSIGNAL_CPU_COUNT=$(jq -rn --argjson size "$TARGET_SIZE" \
  '$size * 2 / 3 * 100 | round / 100 | tostring | if test("\\.") then . else . + ".0" end')

API="https://api.gigalixir.com/api/apps/${GIGALIXIR_APP}"

uri_encode() { jq -rn --arg v "$1" '$v | @uri'; }

fetch_api_key() {
  local response code body
  response=$(http -w '\n%{http_code}' \
    -u "$(uri_encode "$GIGALIXIR_USERNAME"):$(uri_encode "$GIGALIXIR_PASSWORD")" \
    "https://api.gigalixir.com/api/login")
  code=${response##*$'\n'}
  body=${response%$'\n'*}

  case "$code" in
    200) jq -r '.data.key' <<<"$body" ;;
    000) log "Login failed: no response from Gigalixir" >&2; return 1 ;;
    303) log "Login failed: account has two-factor auth enabled, which this job cannot complete" >&2; return 1 ;;
    *) log "Login failed with HTTP ${code}: ${body}" >&2; return 1 ;;
  esac
}

API_KEY=$(fetch_api_key)

api() {
  http --fail-with-body -u "${GIGALIXIR_USERNAME}:${API_KEY}" \
    -H 'Content-Type: application/json' "$@"
}

app_status() { api "${API}/status" | jq '.data'; }

smoke_test() {
  local attempt response code body
  for ((attempt = 1; attempt <= SMOKE_TEST_ATTEMPTS; attempt++)); do
    response=$(http --proto '=https' -w '\n%{http_code}' -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg phone "$SMOKE_TEST_PHONE" --arg password "$SMOKE_TEST_PASSWORD" \
        '{user: {phone: $phone, password: $password}}')" \
      "${SMOKE_TEST_URL%/}/api/v1/session") || response=$'\n000'
    code=${response##*$'\n'}
    body=${response%$'\n'*}

    if [[ "$code" == 200 ]] && jq -e '.data.access_token | length > 0' <<<"$body" >/dev/null 2>&1; then
      log "Smoke test passed: logged in to ${SMOKE_TEST_URL}"
      return 0
    fi

    log "Smoke test attempt ${attempt}/${SMOKE_TEST_ATTEMPTS} failed with HTTP ${code}"
    ((attempt < SMOKE_TEST_ATTEMPTS)) && sleep "$POLL_INTERVAL_SECONDS"
  done

  log "Smoke test failed: could not log in to ${SMOKE_TEST_URL} after resizing to ${TARGET_SIZE}"
  return 1
}

current=$(app_status)

if jq -e --argjson t "$TARGET_SIZE" '.size == $t' <<<"$current" >/dev/null; then
  log "${GIGALIXIR_APP} is already size ${TARGET_SIZE}, nothing to do"
  exit 0
fi

# Resizing replaces the pod, so the resize is only done once none of these old pods remain.
old_pods=$(jq -c '[.pods[].name]' <<<"$current")

FROM_SIZE=$(jq -r '.size | tostring | sub("\\.0$"; "")' <<<"$current")
DIRECTION=$(jq -r --argjson t "$TARGET_SIZE" 'if .size < $t then "up" else "down" end' <<<"$current")
STARTED_AT=$SECONDS
[[ -n "$SMOKE_TEST_URL" ]] && SMOKE_RESULT="Pending" || SMOKE_RESULT="Not configured"

# avoid_restart: the resize below restarts the app, which picks up the new value in that same restart.
if ! api -X POST "${API}/configs" \
  -d "$(jq -nc --arg v "$APPSIGNAL_CPU_COUNT" '{configs: {APPSIGNAL_CPU_COUNT: $v}, avoid_restart: true}')" >/dev/null; then
  log "Failed to set APPSIGNAL_CPU_COUNT=${APPSIGNAL_CPU_COUNT} on ${GIGALIXIR_APP}, not resizing"
  exit 1
fi
log "Set APPSIGNAL_CPU_COUNT=${APPSIGNAL_CPU_COUNT} on ${GIGALIXIR_APP}"

log "Resizing ${GIGALIXIR_APP} from ${FROM_SIZE} to ${TARGET_SIZE}"
DISCORD_MESSAGE_ID=$(discord_post progress)
api -X PUT "${API}/scale" -d "$(jq -nc --argjson size "$TARGET_SIZE" '{size: $size}')" >/dev/null

deadline=$((SECONDS + TIMEOUT_SECONDS))
while ((SECONDS < deadline)); do
  sleep "$POLL_INTERVAL_SECONDS"

  if ! status=$(app_status); then
    log "Status check failed, retrying"
    continue
  fi

  if jq -e --argjson t "$TARGET_SIZE" --argjson old "$old_pods" '
      .size == $t
      and (.pods | length) == .replicas_desired
      and all(.pods[]; .status == "Healthy" and (.name as $n | ($old | any(. == $n)) | not))
    ' <<<"$status" >/dev/null; then
    log "${GIGALIXIR_APP} is size ${TARGET_SIZE} and healthy"
    NODE=$(jq -r '[.pods[].name] | join(", ")' <<<"$status")
    DURATION="$((SECONDS - STARTED_AT))s"

    if [[ -n "$SMOKE_TEST_URL" ]]; then
      SMOKE_RESULT="Running"
      discord_edit ok
      smoke_test
      SMOKE_RESULT="Passed"
    fi
    discord_edit ok
    exit 0
  fi

  log "Waiting: $(jq -c '{size, pods: [.pods[] | {name, status}]}' <<<"$status")"
done

log "Timed out after ${TIMEOUT_SECONDS}s waiting for ${GIGALIXIR_APP} to become healthy at size ${TARGET_SIZE}"
exit 1
