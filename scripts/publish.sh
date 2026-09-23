#!/usr/bin/env bash
# Edge node (the lab machine): publish approved bookings, and optionally re-scrape the IADE timetable.
# Pushes only when the exported data changed; the push triggers "Sync and deploy" on GitHub.
# Cron on the lab machine (see docs/edge-node.md):
#   */10 * * * *  cd ~/openlabtwin && scripts/publish.sh          >> ~/publish.log 2>&1
#   15 */6 * * *  cd ~/openlabtwin && scripts/publish.sh --scrape >> ~/publish.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== $(date -u +%FT%TZ) publish ${1:-}"
git pull -q --rebase
set -a; . ./.env; set +a
if [ "${1:-}" = "--scrape" ]; then uv run python scripts/timetable.py; fi
uv run python scripts/export.py
git add apps/site/web/data apps/site/web/calendar
if git diff --cached --quiet; then echo "no changes"; exit 0; fi
git commit -q -m "Publish schedule (edge node)"
git push -q
echo "pushed"
