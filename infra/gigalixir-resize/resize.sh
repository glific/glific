#!/usr/bin/env bash
set -euo pipefail

: "${GIGALIXIR_APP:?GIGALIXIR_APP is required}"
: "${TARGET_SIZE:?TARGET_SIZE is required}"
: "${GIGALIXIR_USERNAME:?GIGALIXIR_USERNAME is required}"
: "${GIGALIXIR_PASSWORD:?GIGALIXIR_PASSWORD is required}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"

API="https://api.gigalixir.com/api/apps/${GIGALIXIR_APP}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

uri_encode() { jq -rn --arg v "$1" '$v | @uri'; }

fetch_api_key() {
  local response code body
  response=$(curl -sS -w '\n%{http_code}' \
    -u "$(uri_encode "$GIGALIXIR_USERNAME"):$(uri_encode "$GIGALIXIR_PASSWORD")" \
    "https://api.gigalixir.com/api/login")
  code=${response##*$'\n'}
  body=${response%$'\n'*}

  case "$code" in
    200) jq -r '.data.key' <<<"$body" ;;
    303) log "Login failed: account has two-factor auth enabled, which this job cannot complete" >&2; return 1 ;;
    *) log "Login failed with HTTP ${code}: ${body}" >&2; return 1 ;;
  esac
}

API_KEY=$(fetch_api_key)

api() {
  curl -sS --fail-with-body -u "${GIGALIXIR_USERNAME}:${API_KEY}" \
    -H 'Content-Type: application/json' "$@"
}

app_status() { api "${API}/status" | jq '.data'; }

current=$(app_status)

if jq -e --argjson t "$TARGET_SIZE" '.size == $t' <<<"$current" >/dev/null; then
  log "${GIGALIXIR_APP} is already size ${TARGET_SIZE}, nothing to do"
  exit 0
fi

# Resizing replaces the pod, so the resize is only done once none of these old pods remain.
old_pods=$(jq -c '[.pods[].name]' <<<"$current")

log "Resizing ${GIGALIXIR_APP} from $(jq -r '.size' <<<"$current") to ${TARGET_SIZE}"
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
    exit 0
  fi

  log "Waiting: $(jq -c '{size, pods: [.pods[] | {name, status}]}' <<<"$status")"
done

log "Timed out after ${TIMEOUT_SECONDS}s waiting for ${GIGALIXIR_APP} to become healthy at size ${TARGET_SIZE}"
exit 1
