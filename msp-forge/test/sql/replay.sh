#!/usr/bin/env bash
# Replays every migration into a fresh local database. Usage: test/sql/replay.sh [last_number]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; MIG="$HERE/../../supabase/migrations"
PSQL="psql -h /tmp -p 55432 -U postgres -v ON_ERROR_STOP=1 -q"
LAST="${1:-999}"
$PSQL -d postgres -c "drop database if exists cnc_test" -c "create database cnc_test"
$PSQL -d cnc_test -f "$HERE/00_supabase_stub.sql" >/dev/null
for f in "$MIG"/[0-9][0-9][0-9]_*.sql; do
  n=$(basename "$f" | cut -c1-3); [ "$((10#$n))" -le "$LAST" ] || continue
  # pgvector is not installed locally; the precedent embedding column becomes real[].
  sed 's/extensions\.vector([0-9]*)/real[]/g' "$f" | $PSQL -d cnc_test -f - >/dev/null 2>"$HERE/.last_err" || { echo "FAIL $(basename "$f")"; cat "$HERE/.last_err"; exit 1; }
  echo "ok   $(basename "$f")"
done
