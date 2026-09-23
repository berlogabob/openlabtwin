# Edge node

The always-on lab machine (a Raspberry Pi or any Linux or macOS box) that publishes approved bookings every 10 minutes and re-scrapes the timetable every 6 hours. It exists because GitHub's scheduler never fired the 10-minute cron for this repo (see [ARCHITECTURE → Decisions](ARCHITECTURE.md#decisions-and-why)). It's also the thesis's first edge node.

It needs HTTPS to GitHub and Supabase, which the IADE network allows. It needs no Postgres port.

## Setup (once)

1. **OS and tools:** a 64-bit Linux, `git` and `curl`, and `uv`:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
2. **Push access:** create a deploy key with write access, for this repo only.
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/openlabtwin -N "" -C "lab edge node"
   cat ~/.ssh/openlabtwin.pub   # add at github.com/berlogabob/openlabtwin → Settings → Deploy keys, tick "Allow write access"
   printf 'Host github.com\n  IdentityFile ~/.ssh/openlabtwin\n' >> ~/.ssh/config
   git clone git@github.com:berlogabob/openlabtwin.git ~/openlabtwin
   git -C ~/openlabtwin config user.name "lab edge node"
   git -C ~/openlabtwin config user.email "lab-edge-node@users.noreply.github.com"
   ```
3. **Secrets:** create `~/openlabtwin/.env` with mode 600:
   ```
   SUPABASE_URL=https://huqecytswaswkswofrqd.supabase.co
   SUPABASE_SERVICE_KEY=<service role key>
   ```
   The service key bypasses every privacy rule, so this machine must be physically in the lab and under your account only.
4. **Check it by hand:**
   ```bash
   cd ~/openlabtwin && uv sync && scripts/publish.sh --scrape
   ```
   Expected: `Exported N records … and lab.ics`, then `no changes` or `pushed`.
5. **Schedule it** with `crontab -e`:
   ```
   */10 * * * *  cd ~/openlabtwin && scripts/publish.sh          >> ~/publish.log 2>&1
   15 */6 * * *  cd ~/openlabtwin && scripts/publish.sh --scrape >> ~/publish.log 2>&1
   ```

## What it does

`scripts/publish.sh` pulls, optionally scrapes, and exports. It commits and pushes `apps/site/web/data` and `apps/site/web/calendar` only if they changed. The push triggers "Sync and deploy", which rebuilds and publishes the site. If an export fails, nothing is pushed and the site keeps its last version.

## Checks

- `tail ~/publish.log`: one block every 10 minutes, ending in `no changes` or `pushed`.
- Approve a test booking in the office: within about 15 minutes it's on the schedule. Then cancel it.
- If the node dies, publish by hand (Actions → Sync and deploy → Run workflow) until it's back.
