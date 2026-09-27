# Roadmap

What's next, in rough order. Done work moves to the status table in [ARCHITECTURE.md](ARCHITECTURE.md#status); this file holds only what is still open. Update it in the same commit that finishes or adds an item.

## Next: the TV computer (Raspberry Pi)

Waiting for access to the Pi (`192.168.1.194`, a Pi 3 or older by its network maker code; it lags on the showcase TV). Needed first: `ssh-copy-id -i ~/.ssh/techlab.pub <user>@192.168.1.194` from the Mac, and the user name. Details in [edge-node.md → The TV computer](edge-node.md#the-tv-computer-raspberry-pi).

1. Check the model (`cat /proc/device-tree/model`) and memory.
2. Clock: time zone Europe/Lisbon and network time. The TV's now-line, finished cards and takeover switching use the Pi's own clock.
3. Kiosk: Raspberry Pi OS Lite with only Chromium, full screen at boot on `http://192.168.1.131/tv/?room=…&room=…`, pointer hidden, no screen blanking, nightly Chromium restart.
4. Pi 3 tuning: `gpu_mem=256`, zram swap, Bluetooth and unused services off, Chromium GPU flags, draw at 720p.
5. HDMI-CEC: switch the Samsung on in the morning and off at night.
6. Measure: which video level the TV settles on (its footer shows "video 480p/720p/1080p") and whether cards and slides stay smooth. If a Pi 3 can't manage, get a Pi 4 (2 GB+) or Pi 5, or an old laptop or mini-PC.
7. Then retire the old site: point the TV at the new address for good, and follow [OPERATIONS → The old site](OPERATIONS.md#the-old-site) (the local branch `retire-to-openlabtwin` in `iade-lab-schedule` is ready and not pushed).

## Next: finish the node setup (needs sudo, 2026-09-27)

The node runs the new code and the loan-sheet reader (cron every 15 min, `~/archive/inbox`, tested with a fictional sheet). What needs the node's sudo password, from a terminal: `ssh -t -i ~/.ssh/techlab TechLAB@techlab-01 'cd openlabtwin && scripts/edge-setup.sh'`. It adds the `smb://192.168.1.131/archive` share (until then, copy photos in with `scp`) and installs Postgres for the nightly read-only mirror (step 10).

## Smart storage: first stocktakes

The office side is built (2026-09-26); what's left is walking the store with a phone.

1. Print labels and stick them on: all 28 places and all 83 tagged items were generated on 2026-09-27 (`~/Downloads/labels-places.html`, `labels-assets.html`); later ones with `scripts/labels.py --root CODE` or `--assets`.
2. Count every place in Room 15 and the Vitrine; Needs attention empties as you go. Merge the duplicate names it finds.
3. -2 floor: add the racks and shelves from the office (`B2-R1`, `B2-R1-S1`, …), print their labels, count them.
4. Classroom cupboards `CUP1`–`CUP8`: set each one's room (Edit → Inside) and name.
5. PlayStation loans: the import (applied 2026-09-27) listed 12 student loan records and one console outside IADE. Record the ones still out as issue movements (tagged console to the student).
6. Godot: name each storage node after its place code and read `stock` and `asset_place`. Staff sign-in is awkward from Godot; the likely route is a node-written LAN JSON of place codes and counts, like `tv.json`.
7. A tagged item's own QR (`office/?asset=TL-0003`): where it is, who has it, its history, with issue and return from there.
8. After the first counts, re-tune the duplicate threshold (0.5 flags 21 pairs in the import, about 6 real; 0.6 would flag 14).

## Paper loan archive: first sheets

1. Photograph 3–5 real sheets and read them with `scripts/archive_ocr.py --file` (from the Mac with the Studio settings, or on the node). Compare field by field with the paper, tune `PROMPT_READ` / `PROMPT_FIELDS`, and note the accuracy for the thesis.
2. On the node: `git pull`, run `edge-setup.sh` (the `archive` share and the 15-minute job), then drop the photos in.
3. Check the first sheets in the office; match unmatched lines to items as the catalogue grows.
4. Export the statistics for the thesis: `scripts/usage_export.py`.

## TV showcase, later

- **"Play now" button in the office:** tell the TV to reload within seconds after a change (today: within a minute).
- **Preview link in the office:** see the TV page from anywhere over Tailscale.
- **Upload from the office:** needs HTTPS on the node (for example a Tailscale certificate) and a staff check on the node. Today files go in through the shared folder, on the lab network only.
- **Event pages with photos:** approved events carry an optional image, shown on their TV page.
- **Video wall:** one picture split across several screens, built in its own repo [videowall](https://github.com/berlogabob/videowall) (Pi per monitor, FFmpeg server on the lab network; plan in its `docs/ROADMAP.md`). This repo's part comes last: tables `wall_state` (mode, play/stop, blackout) and `wall_status` (heartbeat), which the wall server polls like `tv.py`, plus a Video wall screen in the office. The office can't call the wall directly: HTTPS page, plain-http LAN server. (Several screens showing the same page in sync is done: they follow the clock.)

## Other

- **Milestone 5, thesis layer:** demand forecast and a Godot view. Scope depends on the thesis topic.
- **Idea hub:** re-tune the matching thresholds once there are real student ideas.
- **Flaky CI test:** `tests/check_tv_page.py` failed once on GitHub (2026-09-27, run 36308277095) waiting 4 s for the takeover step's "Normal page"; it passed on rerun and 3 of 3 locally. Give that wait more time or wait for the page change itself.
- **Local models for development:** `pi` hangs at start-up now and then; asking Unsloth Studio's API directly works (a draft in 13 to 60 s, always checked by tests). Look into the hang, or keep the direct route. pi also renames its process, so `pkill -f` doesn't find it: stop it by process group.
- **Fully local database:** the node already keeps a read-only mirror (nightly, from the backup). Making it the main database (PostgREST, HTTPS for the office) stays open, if the node proves reliable. Supabase stays until then.
