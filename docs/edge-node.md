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

To reach the PC from the Mac: `ssh <user>@<ip>`, with the IP printed at the end of the setup, or over Tailscale (below).

The service key bypasses every privacy rule, so this machine must be physically in the lab and under your account only.

## The IADE network: two gotchas (found on TechLAB-01, 2026-09-24)

- **Outgoing SSH (port 22) is blocked,** so GitHub is reached over SSH on port 443 (`Hostname ssh.github.com`, `Port 443` in `~/.ssh/config`; `edge-setup.sh` writes this).
- **The first DNS server handed out by DHCP (`172.23.44.7`) doesn't answer.** Every lookup waited 5 seconds for it, which turned a 30-second scrape into 15 minutes. The fix puts the working one first:
  `sudo nmcli connection modify "Wired connection 1" ipv4.ignore-auto-dns yes ipv4.dns "172.20.44.52 172.23.44.7" && sudo nmcli connection up "Wired connection 1"`.
  Check it with `curl -s -o /dev/null -w "%{time_namelookup}\n" https://github.com`, which should be well under 1 second.
- **The MX firewall (ufw) is on,** so SSH needs a rule per network: `sudo ufw allow from 10.208.16.0/23 to any port 22 proto tcp` (campus) and `sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp` (lab router). Both are in.

## The lab router network (since 2026-09-24)

The node, the big PC with Unsloth Studio and the Mac are wired to the lab's ASUS router (`192.168.1.0/24`), which reaches the internet through campus. The node is `192.168.1.131`, Studio is `192.168.1.42:8888`. The host key didn't change with the address, so `ssh-keyscan -t ed25519 192.168.1.131 >> ~/.ssh/known_hosts` on the Mac is enough. On this network DNS answers quickly, GitHub over port 443 and Supabase work, and the DNS fix above isn't needed.

**Tailscale** (since 2026-09-25, one account): Mac `berlogas-macbook-pro` 100.97.176.12, node `techlab-01` 100.104.12.36, Studio PC `desktop-vdsrh2e` 100.96.84.51. From home: `ssh -i ~/.ssh/techlab TechLAB@techlab-01`, the showcase TV at `http://techlab-01/tv/`, Studio at `http://desktop-vdsrh2e:8888` (same key). The Windows PC needed a firewall rule for Studio on Tailscale (`New-NetFirewallRule -DisplayName "Unsloth Studio (Tailscale)" -Direction Inbound -Protocol TCP -LocalPort 8888 -RemoteAddress 100.64.0.0/10 -Action Allow`).

**The Studio PC** (Windows) starts Unsloth Studio at boot: a shortcut in its Startup folder (`shell:startup`), Windows signs in by itself (`netplwiz`), and sleep is off. It must be on for new ideas to be processed; everything else keeps running without it.

The node's `.env` sends chat to Studio and keeps embeddings on its own Ollama:
`AI_API=openai`, `AI_URL=http://192.168.1.42:8888`, `AI_KEY=sk-unsloth-…`, `IDEAS_MODEL=ornith-ai/Ornith-1.5-9B-GGUF`, `EMBED_URL=http://localhost:11434`, `EMBED_API=ollama`. If the big PC is off, the ideas job fails that run and retries 15 minutes later; to fall back for good, delete those six lines.

## The lab PC (TechLAB-01)

`192.168.1.131` on the lab router (earlier `10.208.17.166` on campus), user `TechLAB`: an i7-7700K with 8 threads, 46 GB RAM, a GTX 1070, Debian 13 with systemd. Ollama with `ornith-1.5:9b` and `nomic-embed-text` runs on the CPU: `ideas_ai.py --check` takes about 25 s including the model load.

**GPU: don't install the NVIDIA driver with `ddm-mx -i nvidia` on this PC.** On 2026-09-24 it installed a driver that fails on the GTX 1070 ("probe with driver nvidia failed with error -1"). The desktop and the network didn't come up, and `sudo ddm-mx -p nvidia` plus a reboot undid it. The cause is probably Debian 13's *open* NVIDIA kernel module, which only supports Turing (GeForce 16xx/20xx) and newer, while the 1070 is Pascal. To try again later, use the proprietary (non-open) kernel module of a driver branch that still supports Pascal, and check with `nvidia-smi` before rebooting into the desktop. The open `nouveau` driver is what drives the screen now. If the monitor shows no picture but the PC answers ping, check from SSH: `cat /sys/class/drm/card0-HDMI-A-1/status` should say `connected`, and `DISPLAY=:0 xrandr --output HDMI-1 --auto` re-sends the signal. If both look right, it's the monitor input or the cable. It's reachable from the Mac with `ssh -i ~/.ssh/techlab TechLAB@192.168.1.131`. Unsloth Studio runs on the big PC, not on this one; its OpenAI-compatible API needs a key.

## TV showcase

Step 9 of `edge-setup.sh` installs nginx, Samba and ffmpeg, and cron runs `scripts/tv.py` every minute.

- **TV page:** `http://192.168.1.131/tv/?room=…&room=…` (nginx site file `scripts/tv-nginx.conf`, installed as `/etc/nginx/sites-available/tv`). It serves `apps/tv/` from the repo checkout, so a push reaches the TV within 10 minutes (the next `publish.sh` pull).
- **Shared folder:** `~/tv-media`, shared as `smb://192.168.1.131/tv` (user `TechLAB`, Samba password set by `sudo smbpasswd -a TechLAB`). Flat: subfolders and dot-files are ignored.
- **Playlist:** `~/tv-out/tv.json` and `~/tv-out/qr/`, written atomically by `tv.py`. Only public fields go in; ideas only as the AI title and summary.
- **Firewall:** ports 80 and 445 are open to `192.168.1.0/24` and `10.208.16.0/23`.
- **Lighter video copies:** for every video, `tv.py` makes 480p, 720p and 1080p H.264 copies without sound (never above the source's height, 480p always) in `~/tv-media/.tv/` (hidden in the shared folder), one run at a time under a lock, after the playlist is written. A 6-minute 1080p video takes a few minutes. Copies of deleted or replaced files are removed. This also makes iPhone `.mov`/HEVC files playable.
- **Probe cache and Mac clutter:** `tv.py` re-reads a file's details only when its size or time changed (`~/tv-out/probe.json`), and deletes the `._*` and `.DS_Store` files a Mac leaves in the share; Samba is also set to refuse them (`veto files`, from `edge-setup.sh`).
- **Heartbeat:** every run writes `tv_status` (last build, pages, files, takeover, or the last error), which the office TV screen shows.
- **Checks:** `cat ~/tv.log` is empty when all is well; `head -c 300 ~/tv-out/tv.json`; `curl -sI localhost/tv/` returns 200.
- **The TV itself:** Chromium full screen (kiosk) on the address above; videos autoplay because they're muted.

## The TV computer (Raspberry Pi)

The lab's TV Pi is `192.168.1.194` (maker code `b8:27:eb`: a Pi 3 or older, 1 GB). The TV page does the work it can for such a device: it plays the node's lighter video copies (480p/720p/1080p, picked by dropped frames and shown in the footer as "video 720p"), draws no blurred shadows, and shrinks a busy schedule to fit. The rest is set up on the Pi:

- **Clock:** the TV's now-line, "past" cards and takeover times use the Pi's own clock. `sudo raspi-config nonint do_change_timezone Europe/Lisbon` and `sudo timedatectl set-ntp true`, then check with `date`.
- **Kiosk:** Raspberry Pi OS Lite with only Chromium, started full screen at boot on `http://192.168.1.131/tv/?room=…&room=…` (flags `--kiosk --noerrdialogs --disable-infobars --autoplay-policy=no-user-gesture-required --enable-gpu-rasterization --ignore-gpu-blocklist`), mouse pointer hidden, screen blanking off, and a nightly Chromium restart against slow memory growth.
- **Pi 3:** `gpu_mem=256` in `/boot/firmware/config.txt`, zram swap, Bluetooth and unused services off; draw at 720p (`--force-device-scale-factor` or a 720p output) and let the TV scale up.
- **Better hardware:** a Pi 4 (2 GB or more) or Pi 5 plays the 1080p copies in hardware without trouble.
- **The TV itself** (Samsung UE55H6200, 2014): its built-in browser is too old for the page; use it as a screen only. HDMI-CEC ("Anynet+") lets the Pi switch it on and off.

## Backups

The Supabase free plan keeps **no** backups. Every night `scripts/backup.py` saves each table as JSON to `~/openlabtwin-backups/YYYY-MM-DD/` and keeps the newest 30 days (about 4 MB a day). The folder is mode 700 and outside the repo because it holds emails. To restore, insert each file's rows back in the order of `TABLES` in `backup.py` (parents first), with the service key.

## What it does

`scripts/publish.sh` pulls, optionally scrapes, and exports. It commits and pushes `apps/site/web/data` and `apps/site/web/calendar` only if they changed. The push triggers "Sync and deploy", which rebuilds and publishes the site. If an export fails, nothing is pushed and the site keeps its last version.

## Checks

- `tail ~/publish.log`: one block every 10 minutes, ending in `no changes` or `pushed`.
- `ls ~/openlabtwin-backups`: a new dated folder every morning.
- `tail ~/ideas_ai.log`: `normalised N, approved M, matches K` every 15 minutes.
- Hardware check before choosing the model: `free -h` (RAM), `nproc` (cores), `lspci | grep -i nvidia` (GPU). Ornith needs about 8 GB free; on a CPU it takes 1–3 minutes per idea.
- **Idea AI server:** `set -a; . ./.env; set +a; uv run python scripts/ideas_ai.py --check` runs one chat and one embedding against the configured servers (Studio for chat, the node's Ollama for embeddings) and writes nothing.
- Approve a test booking in the office: within about 15 minutes it's on the schedule. Then cancel it.
- If the node dies, publish by hand (Actions → Sync and deploy → Run workflow) until it's back.
