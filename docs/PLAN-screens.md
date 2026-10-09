# Plan: all screens (labs, common TV, media store, Book me labs)

Status: `[ ]` open, `[x]` done. One task = one local-model run on Unsloth Studio; Claude reviews the diff and merges. Specs: [labs and common TV](superpowers/specs/2026-10-08-labs-and-common-tv-design.md); the media store spec is task 2.0.

## How to run a task

1. Worktree: `git worktree add ../olt-task -b task/<id>`.
2. Brief = the task row below + the paths it names. Nothing else; the model reads `AGENTS.md` itself.
3. Run pi on Studio (key in `~/.unsloth_key`): `PI_PROVIDER=studio PI_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF pi`. If pi hangs, call Studio's `/v1/chat/completions` directly. Stop pi by process group.
4. Gate: the task's **Test** passes, `git diff --stat` touches only the named files, the file ends with a newline.
5. Merge, tick the box here, commit. A task that changes behaviour updates its doc in the same commit. A decision gets a record + `Decision:` trailer.
6. Task too big for one run: split it here first.

Claude-only steps are marked **C** (specs, decisions, security review, anything touching the live database or the node).

## Phase 0: after reboot

| ID | Task | Test |
|---|---|---|
| [ ] 0.1 | **C** Find the TV Pi (`techlab-tv`; 192.168.1.194 Wi-Fi, .199 cable). Check `nmcli`, signal, `vcgencmd get_throttled`, the footer's video level | `ssh tv@…` works |
| [ ] 0.2 | **C** Watch the Reel and the Welcome loop on the Pi; confirm the 3b4c578 step-down stops the black video | no black; footer settles |
| [ ] 0.3 | **C** Get the node's nginx logs readable: `sudo usermod -aG adm TechLAB` | `tail /var/log/nginx/error.log` as TechLAB |
| [ ] 0.4 | **C** Check the hosted Supabase: sign-ups off (decision 0011); `config.toml` says `enable_signup = true` | dashboard shows off |

## Phase 1: labs and per-lab TVs

| ID | Repo | Task | Files | Test |
|---|---|---|---|---|
| [ ] 1.1 | olt | Migration: `labs(code pk, title, rooms text[])` staff-only RLS + audit; seed `techlab`, `3dlab`; `tv_slides.lab` FK, null = all | `supabase/migrations/<ts>_labs.sql`, `supabase/tests/database/<next>_labs.sql` | `uv run python scripts/sqltest.py` |
| [ ] 1.2 | olt | `tv.py`: `labs` read in `main()`; `slides_for(slides, lab)` keeps null + own lab | `scripts/tv.py`, `tests/test_tv.py` | `uv run python tests/test_tv.py` |
| [ ] 1.3 | olt | `tv.py`: write `tv/<code>.json` per lab with `rooms`; `lab` joins `SLIDE_KEYS`; `assert_public` on each | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 1.4 | olt | `tv.py`: `common` = null-lab pages, then round-robin by page over labs; each page tagged `lab`; `tv.json` = common | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 1.5 | olt | `write_public`: also `tv/<code>.json` and `labs.json` (`[{code,title}]`) | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 1.6 | olt | TV page: lab = last path segment under `/tv/`; fetch `../data/all.json` + `tv/<lab>.json`; rooms from json unless `?room=`; drop `DEFAULT_ROOM` | `apps/tv/index.html`, `tests/check_tv_page.py` | `uv run --with playwright python tests/check_tv_page.py` |
| [ ] 1.7 | olt | TV page: `?order=grouped` (schedule pages first, then each lab in turn) | `apps/tv/index.html`, `tests/check_tv_page.py` | same |
| [ ] 1.8 | olt | `sync.yml`: copy `apps/tv/index.html` into `tv/<code>/index.html` per lab in `labs.json` | `.github/workflows/sync.yml` | **C** workflow run |
| [ ] 1.9 | olt | nginx: `location ~ ^/tv/\w+/$` serves the page | `scripts/tv-nginx.conf` | `curl -sI localhost/tv/techlab/` 200 on the node |
| [ ] 1.10 | olt | Office TV screen: Lab dropdown on a slide (All labs + each lab), Lab filter on the list | `apps/office/lib/tv_screen.dart`, `apps/office/lib/data.dart`, `apps/office/test/logic_test.dart` | `cd apps/office && flutter test` |
| [ ] 1.11 | olt | Docs: ARCHITECTURE, OPERATIONS (add a lab), STAFF-GUIDE, edge-node (Pi URL `/tv/techlab/`), README URLs, ROADMAP | `docs/*.md`, `README.md` | read once |
| [ ] 1.12 | **C** | Apply migration; decision record; point the Pi at `/tv/techlab/` | live | TV shows Tech Lab |

## Phase 2: media store (one tree for TV and wall)

Layout: originals stay in `~/tv-media` (Samba share, flat, never auto-deleted). Derived copies go to `~/media-derived/<sha256>/` with `meta.json` (name, bytes, recipe, made, last_used), `tv-480.mp4`, `tv-720.mp4`, `thumb.jpg`, `wall-<recipe>/`. Everything derived is a disposable cache. Names come from content hash + recipe + version. A video page without its variant is skipped, never played from the original. Retention: delete a copy 30 days after its last use (referenced by any `tv_slides` or `wall_slides` row, or the file is under 30 days old). 1080p is dropped.

| ID | Repo | Task | Files | Test |
|---|---|---|---|---|
| [ ] 2.0 | **C** | Write the spec from the layout above; decision record | `docs/superpowers/specs/…-media-store-design.md` | review |
| [ ] 2.1 | olt | Migration: `media_variants(sha, name, kind, recipe, bytes, made_at, last_used, state)` node-write, staff-read; `cache_control(id=1, clear_at)` staff-write | migration + pgTAP | `sqltest.py` |
| [ ] 2.2 | olt | `scripts/media_hash.py`: sha256 of a file, cached by size+mtime in `probe` cache | new + `tests/test_media_hash.py` | `uv run python tests/test_media_hash.py` |
| [ ] 2.3 | olt | `tv.py`: derived dir `~/media-derived/<sha>/`, names `tv-<h>.mp4`, tiers 480/720 only | `scripts/tv.py`, `tests/test_tv.py` | `test_tv.py` |
| [ ] 2.4 | olt | `tv.py`: skip a video page with no variant (`build`); never use `src` of the original | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 2.5 | olt | `tv.py`: touch `meta.json.last_used` for files in use; write `media_variants` rows | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 2.6 | olt | Janitor: delete variants with `last_used` older than 30 days; originals never | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 2.7 | olt | Clear command: if `cache_control.clear_at` > last clear, delete `~/media-derived`, record time in `tv_status` | `scripts/tv.py`, `tests/test_tv.py` | same |
| [ ] 2.8 | olt | One-off `scripts/migrate_derived.py`: move `.tv/*` copies into the new tree (dry run first) | new + test | **C** run on the node |
| [ ] 2.9 | olt | nginx: serve `/tv/media/.tv/` from `~/media-derived/` | `scripts/tv-nginx.conf`, `scripts/edge-setup.sh` | `curl -sI` on the node |
| [ ] 2.10 | olt | Office "Media" screen: originals with their variants, size, state, expiry | `apps/office/lib/media_screen.dart`, `main.dart`, `data.dart` | `flutter test` |
| [ ] 2.11 | olt | Office: "Clear prepared copies" button + confirmation, writes `cache_control.clear_at` | `apps/office/lib/media_screen.dart` | `flutter test` |
| [ ] 2.12 | vw | Wall renders write into `~/media-derived/<sha>/wall-<recipe>/` with `meta.json`, set `last_used` | `server/render.py` | `uv run pytest` in videowall |
| [ ] 2.13 | vw | Wall: 30-day age rule + react to `cache_control.clear_at` | `server/render.py`, `server/app.py` | same |
| [ ] 2.14 | olt | Docs: ARCHITECTURE, OPERATIONS, STAFF-GUIDE, edge-node, ROADMAP | `docs/*.md` | read once |
| [ ] 2.15 | **C** | Apply migration, run 2.8, restart wall server, check disk | live | office Media lists all |

## Phase 3: Book me with a lab choice

| ID | Repo | Task | Files | Test |
|---|---|---|---|---|
| [ ] 3.0 | **C** | Spec: lab in the form, lesson lookup per lab, which room/staff gets the request | spec file | review |
| [ ] 3.1 | olt | Migration: `request_consultation(…, p_lab text)`; place from `labs.rooms`; pgTAP | migration + test | `sqltest.py` |
| [ ] 3.2 | olt | Site: lab picker on `/book/` (`?lab=` preselects); lessons shown for that lab | `apps/site/lib/pages/book_page.dart`, `apps/site/lib/schedule.dart` | `cd apps/site && dart test` |
| [ ] 3.3 | olt | Status page shows the lab | `apps/site/lib/pages/idea_status_page.dart` or book status page | `dart test` |
| [ ] 3.4 | olt | Office bookings: lab column and filter | `apps/office/lib/bookings.dart` | `flutter test` |
| [ ] 3.5 | olt | A Book me QR slide per lab (`/book/?lab=…`) | office TV screen | by hand |
| [ ] 3.6 | olt | Docs | `docs/*.md` | read once |

## Phase 4: audit fixes (2026-10-09)

| ID | Repo | Task | Files | Test |
|---|---|---|---|---|
| [ ] 4.1 | **C** | `file_student()`: set `student_number` only when null; never touch a non-student row | migration + pgTAP | `sqltest.py` |
| [ ] 4.2 | **C** | Book me: don't overwrite an existing person's name with the number | migration + pgTAP | `sqltest.py` |
| [ ] 4.3 | **C** | Rate limit on public forms: pick per-IP at the edge or Turnstile (spec first) | spec | review |
| [ ] 4.4 | olt | Off-node backup: `scripts/backup_offsite.sh` copies the newest folder to the Mac over Tailscale, cron line in `edge-setup.sh` | script, `edge-setup.sh`, `docs/edge-node.md` | dry run |
| [ ] 4.5 | olt | `tv.log` rotation (logrotate file in `edge-setup.sh`) | `scripts/edge-setup.sh` | by hand |
| [ ] 4.6 | olt | Public forms: `autocomplete` and `required` attributes | `apps/site/lib/pages/*.dart` | `dart test` + e2e |
| [ ] 4.7 | olt | Docs: Book me has no identity check (staff confirm) | `docs/ARCHITECTURE.md` | read once |

## Phase 5: other labs and the university subdomain

| ID | Task |
|---|---|
| [ ] 5.1 | **C** Add `print` lab when its room exists in the timetable; set up the 3D Lab TV on Pages |
| [ ] 5.2 | **C** Request the subdomain; Pages custom domain + DNS; update README and kiosk URLs |
| [ ] 5.3 | **C** TV hardware: HDMI-CEC check, Pi 4 or mini-PC if the Pi 3 stutters (from ROADMAP) |

## Order

0 → 1 → 2 → 4 (4.1, 4.2 can go first at any time) → 3 → 5. Phases 1 and 2 touch `tv.py` and `tests/test_tv.py`: run them one at a time, never in parallel.
