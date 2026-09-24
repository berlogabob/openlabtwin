# Edge node

The always-on lab machine (a Raspberry Pi or any Linux or macOS box) that publishes approved bookings every 10 minutes and re-scrapes the timetable every 6 hours. It exists because GitHub's scheduler never fired the 10-minute cron for this repo (see [ARCHITECTURE → Decisions](ARCHITECTURE.md#decisions-and-why)). It's also the thesis's first edge node.

It needs HTTPS to GitHub and Supabase, which the IADE network allows. It needs no Postgres port.

## Setup (once)

On the MX Linux PC, in a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/berlogabob/openlabtwin/main/scripts/edge-setup.sh | bash
```

`scripts/edge-setup.sh` is safe to run again, and `--dry-run` shows the steps without doing them. It:

1. installs `git`, `curl`, `openssh-server` and `cron`, and starts SSH and cron at boot (sysVinit or systemd);
2. installs `uv`;
3. creates a deploy key. It **pauses** for you to add the printed key at github.com/berlogabob/openlabtwin → Settings → Deploy keys, with "Allow write access" ticked;
4. clones the repo to `~/openlabtwin`;
5. **asks** for the Supabase service role key (hidden input) and writes `~/openlabtwin/.env` with mode 600;
6. installs **Ollama** with `nomic-embed-text`, and `ornith-1.5:9b` only if the PC has at least 16 GB of RAM. Otherwise it tells you to set `IDEAS_MODEL` to a small model (for example `qwen2.5:3b`) or `OLLAMA_URL` to a machine that runs ornith. On sysVinit it also starts Ollama at boot;
7. runs everything once: scrape, export, push if changed, backup, idea AI;
8. installs the cron lines: publish every 10 minutes, scrape every 6 hours, idea AI every 15 minutes, back up nightly at 03:30.

Before running it, turn off sleep and suspend in MX's power settings.

To reach the PC from the Mac: `ssh <user>@<ip>`, with the IP printed at the end of the setup. If the campus network blocks device-to-device traffic, install Tailscale on both machines (`curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up` on the PC, the App Store app on the Mac) and use `ssh <user>@<pc-name>`.

The service key bypasses every privacy rule, so this machine must be physically in the lab and under your account only.

## Backups

The Supabase free plan keeps **no** backups. Every night `scripts/backup.py` saves each table as JSON to `~/openlabtwin-backups/YYYY-MM-DD/` and keeps the newest 30 days (about 4 MB a day). The folder is mode 700 and outside the repo because it holds emails. To restore, insert each file's rows back in the order of `TABLES` in `backup.py` (parents first), with the service key.

## What it does

`scripts/publish.sh` pulls, optionally scrapes, and exports. It commits and pushes `apps/site/web/data` and `apps/site/web/calendar` only if they changed. The push triggers "Sync and deploy", which rebuilds and publishes the site. If an export fails, nothing is pushed and the site keeps its last version.

## Checks

- `tail ~/publish.log`: one block every 10 minutes, ending in `no changes` or `pushed`.
- `ls ~/openlabtwin-backups`: a new dated folder every morning.
- `tail ~/ideas_ai.log`: `normalised N, approved M, matches K` every 15 minutes.
- Hardware check before choosing the model: `free -h` (RAM) and `nproc` (cores). Ornith needs about 8 GB free; on a CPU it takes 1–3 minutes per idea.
- Approve a test booking in the office: within about 15 minutes it's on the schedule. Then cancel it.
- If the node dies, publish by hand (Actions → Sync and deploy → Run workflow) until it's back.
