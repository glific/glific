#!/usr/bin/env bash
# Samples what a k6 run costs the machine: BEAM CPU, Postgres CPU, and the number of database
# transactions Glific actually ran. The transaction delta is the clearest signal of the
# uncached-organization-lookup bug — CPU percentages move around, a query count does not.
#
#   k6/sample_resources.sh master 150
#   k6/sample_resources.sh fixed  150
#
# Writes k6/results/<label>-resources.csv and prints a summary. Run it just before `k6 run`.

set -euo pipefail

LABEL="${1:-run}"
SECONDS_TO_SAMPLE="${2:-150}"
PORT="${PORT:-4000}"
DB_NAME="${DB_NAME:-glific_dev}"

RESULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results"
mkdir -p "$RESULTS_DIR"
CSV="$RESULTS_DIR/${LABEL}-resources.csv"

beam_pid() {
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1
}

BEAM_PID="$(beam_pid || true)"
if [ -z "$BEAM_PID" ]; then
  echo "No listener on port $PORT — start the Glific server first." >&2
  exit 1
fi

# Returns empty when psql cannot reach the database, which downgrades to CPU-only sampling
# rather than failing the run.
db_xact() {
  psql -d "$DB_NAME" -t -A -c \
    "select xact_commit + xact_rollback from pg_stat_database where datname = '$DB_NAME'" \
    2>/dev/null || true
}

beam_cpu() {
  ps -o %cpu= -p "$BEAM_PID" 2>/dev/null | tr -d ' ' || echo 0
}

postgres_cpu() {
  ps -A -o %cpu=,comm= 2>/dev/null |
    awk '$2 ~ /postgres/ { total += $1 } END { printf "%.1f", total + 0 }'
}

XACT_START="$(db_xact)"
if [ -z "$XACT_START" ]; then
  echo "warning: could not read pg_stat_database for '$DB_NAME'; sampling CPU only." >&2
fi

echo "elapsed_s,beam_cpu_pct,postgres_cpu_pct" > "$CSV"
echo "Sampling pid $BEAM_PID on port $PORT for ${SECONDS_TO_SAMPLE}s -> $CSV"

for elapsed in $(seq 0 $((SECONDS_TO_SAMPLE - 1))); do
  echo "${elapsed},$(beam_cpu),$(postgres_cpu)" >> "$CSV"
  sleep 1
done

XACT_END="$(db_xact)"

echo
echo "Resource summary — $LABEL"
awk -F, 'NR > 1 {
  beam += $2; if ($2 > beam_max) beam_max = $2
  pg += $3; if ($3 > pg_max) pg_max = $3
  n++
}
END {
  if (n == 0) { print "  no samples"; exit }
  printf "  beam cpu       avg %6.1f%%   peak %6.1f%%\n", beam / n, beam_max
  printf "  postgres cpu   avg %6.1f%%   peak %6.1f%%\n", pg / n, pg_max
}' "$CSV"

if [ -n "$XACT_START" ] && [ -n "$XACT_END" ]; then
  printf "  db transactions %d\n" "$((XACT_END - XACT_START))"
fi
