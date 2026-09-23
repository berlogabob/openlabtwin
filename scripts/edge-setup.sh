#!/usr/bin/env bash
# One-command setup of the lab edge node (MX Linux / Debian). Safe to run again. See docs/edge-node.md.
#   curl -fsSL https://raw.githubusercontent.com/berlogabob/openlabtwin/main/scripts/edge-setup.sh | bash
#   (or, from a clone:  scripts/edge-setup.sh [--dry-run])
set -euo pipefail
DRY=$([ "${1:-}" = "--dry-run" ] && echo 1 || echo 0)
REPO=git@github.com:berlogabob/openlabtwin.git
DIR=$HOME/openlabtwin
KEY=$HOME/.ssh/openlabtwin
run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }
step() { echo; echo "== $*"; }

step "1/7 packages (git, curl, openssh-server) and SSH at boot"
run sudo apt-get update -qq
run sudo apt-get install -y -qq git curl openssh-server cron
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then run sudo systemctl enable --now ssh cron
else run sudo update-rc.d ssh enable; run sudo update-rc.d cron enable; run sudo service ssh start; run sudo service cron start; fi

step "2/7 uv"
command -v uv >/dev/null || [ -x "$HOME/.local/bin/uv" ] || run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
export PATH="$HOME/.local/bin:$PATH"

step "3/7 deploy key (write access to this repo only)"
if [ ! -f "$KEY" ]; then run ssh-keygen -t ed25519 -f "$KEY" -N "" -C "lab edge node"; fi
grep -q "IdentityFile $KEY" "$HOME/.ssh/config" 2>/dev/null || run sh -c "printf 'Host github.com\n  IdentityFile $KEY\n' >> '$HOME/.ssh/config'"
if [ "$DRY" = 0 ] && ! ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "Add this key at https://github.com/berlogabob/openlabtwin/settings/keys  (tick 'Allow write access'):"
  cat "$KEY.pub"; read -rp "Press Enter once it is added… " _ </dev/tty
fi

step "4/7 clone"
if [ -d "$DIR/.git" ]; then run git -C "$DIR" pull -q --rebase; else run git clone -q "$REPO" "$DIR"; fi
run git -C "$DIR" config user.name "lab edge node"
run git -C "$DIR" config user.email "lab-edge-node@users.noreply.github.com"

step "5/7 secrets (.env, mode 600)"
if [ ! -f "$DIR/.env" ]; then
  if [ "$DRY" = 1 ]; then echo "  would ask for the service role key and write $DIR/.env"
  else read -rsp "Supabase service role key (input hidden): " SK </dev/tty; echo
    umask 077; printf 'SUPABASE_URL=https://huqecytswaswkswofrqd.supabase.co\nSUPABASE_SERVICE_KEY=%s\n' "$SK" > "$DIR/.env"; fi
fi

step "6/7 first run (sync deps, scrape, export, push if changed, backup)"
run sh -c "cd '$DIR' && uv sync -q && scripts/publish.sh --scrape && uv run python scripts/backup.py"

step "7/7 cron (publish every 10 min, scrape every 6 h, backup nightly)"
CRON="*/10 * * * *  cd $DIR && scripts/publish.sh          >> \$HOME/publish.log 2>&1
15 */6 * * *  cd $DIR && scripts/publish.sh --scrape >> \$HOME/publish.log 2>&1
30 3 * * *    cd $DIR && $HOME/.local/bin/uv run python scripts/backup.py >> \$HOME/backup.log 2>&1"
if [ "$DRY" = 1 ]; then echo "  would install (replacing older openlabtwin lines):"; echo "$CRON" | sed 's/^/    /'
else { crontab -l 2>/dev/null | grep -v openlabtwin || true; echo "PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"; echo "$CRON"; } \
  | awk '!seen[$0]++' | crontab -; crontab -l; fi

step "done: tail -f ~/publish.log   ·   ip: $(hostname -I 2>/dev/null | cut -d' ' -f1)"
