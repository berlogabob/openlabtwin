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

## TV showcase, later

- **"Play now" button in the office:** tell the TV to reload within seconds after a change (today: within a minute).
- **Preview link in the office:** see the TV page from anywhere over Tailscale.
- **Upload from the office:** needs HTTPS on the node (for example a Tailscale certificate) and a staff check on the node. Today files go in through the shared folder, on the lab network only.
- **Event pages with photos:** approved events carry an optional image, shown on their TV page.
- **Video wall:** several screens in sync.

## Other

- **Milestone 5, thesis layer:** demand forecast and a Godot view. Scope depends on the thesis topic.
- **Idea hub:** re-tune the matching thresholds once there are real student ideas.
- **Local models for development:** `pi` hangs at start-up now and then; asking Unsloth Studio's API directly works (a draft in 13 to 60 s, always checked by tests). Look into the hang, or keep the direct route.
- **Fully local database** (Postgres and PostgREST on the edge node, no Docker), if the node proves reliable. Supabase stays until then.
