// Video wall status, 2026-09-29. Build: typst compile docs/reports/2026-09-29-videowall.typ
#import "lib.typ": *
#show: report.with((title: "Video wall: status and next steps", footer: "OpenLabTwin · IADE Tech Lab · 2026-09-29"))

#title-block("Video wall: status and next steps", subtitle: "Old Samsung monitors as one screen", meta-line: "29 September 2026 · IADE Tech Lab", standfirst: [Where the video wall stands on 29 September, the plan to the finished wall, and the bench test for tomorrow.])

= Bottom line
#callout(title: "Ready for a bench test, not for the wall", tone: "warn")[ Tomorrow can start with step 0, the bench pilot with two screens, A1 and B1. The setup script is written and tested only on a fake card; it has never run on a real Pi. No wall software (server or Pi client) exists yet, so tomorrow is hardware and setup, not synced playback. ]

= What's done
#scorecard((
  ("Plan and design", "Done", "ok", "README + ROADMAP in the videowall repo"),
  ("Pi setup script", "Written", "ok", "scripts/pi-setup.sh, parallel over SSH, safe to rerun"),
  ("Boot-file test", "Passes", "ok", "tests/test_pi_setup.sh, fake card"),
  ("Script on a real Pi", "Not yet", "warn", "first run tomorrow"),
  ("Lab access", "Ready", "ok", "Tailscale; node techlab-01 is jump host, resolves wall-a1.local"),
  ("TV Pi experience", "Done", "ok", "Pi 3 B kiosk live; same OS and tuning path"),
  ("Several screens same page in sync", "Done", "ok", "TV pages follow the clock"),
  ("Render server + Pi client", "Not started", "neutral", "roadmap steps 1-3"),
  ("Office control (wall_state / wall_status)", "Not started", "neutral", "step 5, last"),
))

= Hardware
#data-table(
  ("Item", "State"),
  (
    ("Monitors", "Samsung SyncMaster 720N, 17 in, 1280x1024, VGA only; 5x3 = 15 now, then 5x5, target 6x6"),
    ("Computers", "Raspberry Pi 3B+, one per screen, wired Ethernet"),
    ("Adapters", "HDMI to VGA; 2-3 models to compare on the bench, then buy one model for all"),
    ("Switch", "TP-Link TL-SG1024D, 24 ports: enough for 15 + server, not for 25"),
    ("Power", "Shared USB charger, 5 V / 2 A per port, below the 2.5 A a Pi 3B+ wants: undervoltage risk"),
    ("Mount", "3D-printed bracket, measurements to redo before printing"),
  ),
  widths: (22%, 1fr),
  right-from: none,
)

= Overall plan
+ Step 0, Pis and bench: flash all cards, run the setup script, pick the adapter, settle Pi 3 video memory and hardware decode.
+ Step 1, Mosaic with stills: pool folder on the node share, each Pi cycles its images, test pattern, Identify Screen. 5x3.
+ Step 2, Videowall with stills: FFmpeg builds one canvas (6400x3072), slices it, synced image change.
+ Step 3, Video: tile render, preload, play_at, chrony; measure drift across 15 screens.
+ Step 4, Composition: Fit/Fill/Center, logo, title, credits, frame.
+ Step 5, Office link: wall_state and wall_status tables, Video wall screen in the office.
+ Step 6, Physical build: bracket, power fix, second switch, 5x5 then 6x6.

= Steps for tomorrow
+ Bring: two Pi 3B+ with cards, two 720N monitors side by side (A1 left, B1 right), 2-3 HDMI-VGA adapter models, a proper 2.5 A supply and the shared USB charger, Ethernet cable.
+ Flash both cards on the Mac with Raspberry Pi Imager: Raspberry Pi OS Lite (64-bit), hostnames `wall-a1` and `wall-b1` (grid code: letter = column, number = row, A1 top-left, E5 bottom-right of a 5×5), user techlab, SSH public-key only with `~/.ssh/techlab.pub`, time zone Europe/Lisbon, Wi-Fi = lab network with country PT (2.4 or 5 GHz).
+ Before ejecting: `scripts/pi-setup.sh --boot /Volumes/bootfs` (sets 1280x1024 output on the card).
+ Boot on the lab network, check: `ping wall-a1.local`, `ping wall-b1.local`.
+ Run: `scripts/pi-setup.sh wall-a1.local wall-b1.local`, then reboot if it says REBOOT NEEDED. Read `logs/wall-a1.local.log` and `logs/wall-b1.local.log`.
+ Check power: `throttled=0x0` in the report, on both the 2.5 A supply and the shared charger.
+ Try each adapter: picture at 1280×1024 at 60 Hz, sharp, no black border.
+ Play the test tile (`~/Downloads/wall-test/tile-1280x1024.mp4`, command in videowall `docs/pi-setup.md`) with mpv; watch for dropped frames. Note what video memory setting it needs.
+ Write the results in videowall docs/pi-setup.md and ROADMAP.md; if the pilot is good, flash the rest of the grid (5×3: `wall-a1` to `wall-e3`).

= Open questions
#callout(title: "Decide soon", tone: "info")[ Which machine hosts the wall server: the edge node (has nginx, Samba, FFmpeg) if its CPU copes, or an old laptop. Power: buy 2.5 A supplies or a stronger charger. Repo public or private. ]
