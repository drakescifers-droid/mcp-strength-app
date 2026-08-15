#!/usr/bin/env bash
#
# Apply every migration to a throwaway Postgres and run the schema + RLS tests.
#
#   ./supabase/tests/run.sh
#
# Needs Docker. Nothing else — no Supabase CLI, no project, no network beyond
# pulling the postgres image once. The container is removed on exit, so this is
# safe to run against nothing and cannot touch a real project.
#
# The point of this script is that the RLS policies are executable claims
# rather than good intentions. A policy nobody has run is a guess, and the
# failure mode is silent: one user reading another user's training history.

set -euo pipefail

IMAGE="postgres:17-alpine"
CONTAINER="mcpstrength-schema-test"
PASSWORD="postgres"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPABASE_DIR="$(dirname "$HERE")"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "==> starting $IMAGE"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e POSTGRES_DB=postgres \
  "$IMAGE" >/dev/null

echo -n "==> waiting for postgres"
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -q 2>/dev/null; then
    echo " ready"
    break
  fi
  echo -n "."
  sleep 1
done

run_sql() {
  local label="$1" file="$2"
  echo "==> $label"
  docker exec -i "$CONTAINER" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q < "$file"
}

run_sql "shim" "$HERE/00_shim.sql"

for migration in "$SUPABASE_DIR"/migrations/*.sql; do
  run_sql "migration $(basename "$migration")" "$migration"
done

for test_file in "$HERE"/0[1-9]_*.sql; do
  run_sql "test $(basename "$test_file")" "$test_file"
done

echo
echo "==> ALL PASS"
