#!/usr/bin/env bash
# Starts a Cloudflare Quick Tunnel (random *.trycloudflare.com URL, no account needed) exposing
# the local Phoenix backend (localhost:4000), and writes its public URL to $GITHUB_ENV as
# GLIFIC_API_HOST_OVERRIDE. Each job gets its own URL, so parallel shards never collide.
set -euo pipefail

LOG_FILE="${TUNNEL_LOG_FILE:-cloudflared.log}"
METRICS_ADDR="127.0.0.1:4041"

# Rewrite Host so Phoenix sees the same host it does locally.
nohup cloudflared tunnel --no-autoupdate \
  --url http://localhost:4000 \
  --http-host-header glific.test:4000 \
  --metrics "$METRICS_ADDR" \
  >"$LOG_FILE" 2>&1 &

count=0
hostname=""
until [ -n "$hostname" ] || [ $count -eq 30 ]; do
  sleep 2
  count=$((count + 1))
  hostname=$(curl -s --max-time 5 "http://${METRICS_ADDR}/quicktunnel" | jq -r '.hostname // empty' 2>/dev/null || true)
  echo "waiting for quick tunnel hostname..."
done

if [ -z "$hostname" ]; then
  echo "ERROR: Cloudflare quick tunnel did not start" >&2
  tail -n 50 "$LOG_FILE" >&2
  exit 1
fi

# The URL is handed out before the edge connection is registered; wait for that too.
count=0
until grep -q "Registered tunnel connection" "$LOG_FILE" || [ $count -eq 30 ]; do
  sleep 2
  count=$((count + 1))
done
if ! grep -q "Registered tunnel connection" "$LOG_FILE"; then
  echo "ERROR: Cloudflare quick tunnel never connected" >&2
  tail -n 50 "$LOG_FILE" >&2
  exit 1
fi

echo "GLIFIC_API_HOST_OVERRIDE=https://${hostname}" >>"$GITHUB_ENV"
echo "Tunnel ready at https://${hostname}"
