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

# The public TV (tv.py writes ~/tv-public): one commit, force-pushed to the tv-public branch, so replaced videos don't pile
# up in the repo. Its commit id goes into data/tv-public.sha, so the push to main below deploys it (a push to tv-public
# can't: that branch has no workflow). A failure here doesn't stop the schedule from publishing.
public_tv() {
  local p=$HOME/tv-public
  [ -f "$p/tv.json" ] || return 0
  if [ ! -d "$p/.git" ]; then git -C "$p" init -q -b tv-public && git -C "$p" remote add origin "$(git remote get-url origin)"; fi
  git -C "$p" config user.name "$(git config user.name)"; git -C "$p" config user.email "$(git config user.email)"
  git -C "$p" add -A
  if ! git -C "$p" rev-parse -q --verify HEAD >/dev/null; then git -C "$p" commit -q -m "Public TV (edge node)"
  elif ! git -C "$p" diff --cached --quiet; then git -C "$p" commit -q --amend -m "Public TV (edge node)"; fi
  if [ "$(git -C "$p" rev-parse HEAD)" != "$(git -C "$p" rev-parse -q --verify origin/tv-public || true)" ]; then
    git -C "$p" push -q -f origin tv-public:tv-public && git -C "$p" update-ref refs/remotes/origin/tv-public HEAD && echo "pushed tv-public"
  fi
  git -C "$p" rev-parse HEAD > apps/site/web/data/tv-public.sha
}
public_tv || echo "tv-public push failed"
git add apps/site/web/data apps/site/web/calendar
if git diff --cached --quiet; then echo "no changes"; exit 0; fi
git commit -q -m "Publish schedule (edge node)"
git push -q
echo "pushed"
