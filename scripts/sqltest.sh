#!/usr/bin/env bash
# Database tests without Docker: push migrations to the hosted Supabase project, run each pgTAP file with psql.
# Every test file wraps itself in begin ... rollback, so nothing stays in the database.
# Needs DB_URL in .env (session pooler connection string) and libpq (brew install libpq).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${DB_URL:?DB_URL missing from .env}"
PSQL="$(brew --prefix libpq)/bin/psql"

supabase db push --db-url "$DB_URL" --include-all --yes

fail=0
for f in supabase/tests/database/*.sql; do
  out=$("$PSQL" "$DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f "$f" 2>&1) || { echo "✗ $f (SQL error)"; echo "$out"; fail=1; continue; }
  if grep -qE '^not ok|Looks like' <<<"$out"; then
    echo "✗ $f"; grep -E '^not ok|^#' <<<"$out"; fail=1
  else
    echo "✓ $f ($(grep -c '^ok' <<<"$out") passed)"
  fi
done
exit $fail
