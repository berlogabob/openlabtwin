# TV showcase: design

Date: 2026-09-24. Status: approved in chat.

## Why

The lab TV shows only the room schedule. Andrey wants to run it like a small showcase: videos and photos of lab work, professor and staff bios, events, QR codes to Book me and the Idea hub, and student ideas. He manages what plays from the office.

## Decisions (user, 2026-09-24)

| Topic | Decision |
|---|---|
| Layout | Left third: the schedule column, two rooms stacked (from `?room=`). Right two thirds: a carousel, one slide at a time in a passe-partout frame that fits each slide's aspect ratio. Footer: one small "updated HH:MM" line. Less is more. |
| Media files | Kept on the edge node (TechLAB-01). Added by dropping them into a shared folder on the lab network. No upload from the office for now. |
| Consequence | Browsers block `http://` media on an `https://` page, so the node serves the showcase TV page itself, on the lab network only. GitHub Pages `/tv/` stays as the schedule-only fallback. |
| Automatic slides | Approved events (next 14 days), the Book me and Idea hub QR codes, and **3 random approved ideas** per loop (AI title and summary, no names). |
| Seed ideas | 20 lab ideas under Andrey's name, approved, normalised by the AI job like any other (list below). |

## Screen

`http://192.168.1.131/tv/?room=<IADE name>&room=<IADE name>` on the lab router network.

- **Schedule column** (left third): each room's name, then today's lessons, bookings and events, as on the current TV (past dimmed, current highlighted, bookings blue, events green). Two rooms stack; one room fills the column.
- **Carousel** (right two thirds): one slide at a time, centred in a passe-partout: a plain mat whose inner opening takes the slide's aspect ratio (from the file's width and height, 16:9 for text slides). Photos, bios, QR and text slides stay for their `seconds`. Videos play once, muted (autoplay needs muted), then the next slide comes up. If a video fails to load, the next slide comes up after 2 seconds.
- **Footer**: "updated HH:MM" from the newest of `tv.json` and `all.json`.
- Data reloads every minute; if a reload fails the last good copy keeps playing.

The page is one plain file, `apps/tv/index.html` (HTML, CSS and JavaScript, no build step). The node already pulls the repo every 10 minutes, so a push updates the TV.

## Slides

The playlist loops in this order:

1. **Manual slides** from the office, by `position`: only active ones, inside their start and end dates, and (for media and bios with a photo) only when the file exists and plays on the TV.
   - `media`: a video or photo from the node's folder, with an optional caption.
   - `bio`: photo (optional), name (`title`), role and text (`body`).
   - `qr`: a link (`url`) and a caption. The node draws the QR code.
   - `text`: a title and text.
2. **Events**: approved `event` activities in the next 14 days: title, day and time, place, public note.
3. **QR**: Book me (`/openlabtwin/book/`) and Idea hub (`/openlabtwin/ideas/`), using the existing `apps/site/web/qr/*.svg`.
4. **Ideas**: the TV picks 3 at random, each loop, from all approved ideas with an AI title: title and summary only.

Default `seconds` is 10. Videos use their own length.

## Node (TechLAB-01)

- **Shared folder**: Samba shares `~/tv-media` as `smb://192.168.1.131/tv` (user `TechLAB`, its own Samba password). Flat folder; subfolders and dot-files are ignored.
- **nginx** (it handles the byte-range requests video seeking needs):
  - `/tv/` → `~/openlabtwin/apps/tv/`
  - `/tv/media/` → `~/tv-media/`
  - `/tv/data/all.json` → `~/openlabtwin/apps/site/web/data/all.json`
  - `/tv/qr/` → `~/openlabtwin/apps/site/web/qr/` plus generated codes in `~/tv-out/qr/`
  - `/tv/tv.json` → `~/tv-out/tv.json`
- **`scripts/tv.py`**, cron every minute:
  1. reads each file in `~/tv-media` with `ffprobe` (width, height, length, codec) and marks it playable if it is MP4 or WebM with H.264, VP8, VP9 or AV1 video, or a JPG, PNG or WebP image;
  2. upserts `tv_media` and deletes rows for files that are gone;
  3. builds the playlist from `tv_slides`, approved events and approved ideas, with the service key, and writes `~/tv-out/tv.json` atomically (write, then rename);
  4. draws a QR code for each `qr` slide into `~/tv-out/qr/<id>.svg` (`segno`).
- `edge-setup.sh` gains the installs: `nginx-light`, `samba`, `ffmpeg`, the nginx site file and the cron line.

`tv.json` shape:

```json
{"generated": "2026-09-24T14:05:00+01:00",
 "slides": [
   {"kind": "media", "src": "media/demo.mp4", "video": true, "w": 1920, "h": 1080, "caption": "Robot arm"},
   {"kind": "bio", "src": "media/andrey.jpg", "w": 800, "h": 1000, "title": "Andrey Dyakov", "body": "Lab technician…", "seconds": 10},
   {"kind": "qr", "src": "qr/12.svg", "title": "Our Instagram", "seconds": 10},
   {"kind": "text", "title": "…", "body": "…", "seconds": 10},
   {"kind": "event", "title": "Open day", "when": "Thu 25 Sep · 10:00–12:00", "place": "Aula Magna", "body": "", "seconds": 10}],
 "ideas": [{"title": "…", "summary": "…"}]}
```

Nothing private goes into `tv.json`: no emails, names of students, purposes or contact links.

## Database

Migration `…_tv_showcase.sql`, staff only (RLS through `is_staff()`, audit trigger, no anon grants), like the other tables:

- `tv_media`: `name text primary key`, `kind` (`video`/`photo`), `width`, `height`, `seconds numeric`, `bytes bigint`, `playable boolean`, `seen_at timestamptz`. Written by the node.
- `tv_slides`: `id`, `kind` (`media`/`bio`/`qr`/`text`), `title`, `body`, `media_name` (references `tv_media`, `on delete set null`), `url`, `seconds int default 10 check (seconds > 0)`, `position int`, `starts_on date`, `ends_on date`, `active boolean default true`, `created_at`.

## Office

A **TV** icon in the top bar opens the slide list:
- drag to reorder; a switch per slide for on/off;
- **Add** and edit: kind, title, text, file (picked from `tv_media`, with "won't play on the TV" shown for unplayable files), link, seconds, start and end dates;
- a note with the TV address and the shared folder address.

## Idea hub changes

- The form's notice becomes: "Your idea is saved in your lab history, visible to lab staff only; matched students see its title and your first name. Approved ideas may be shown on the lab TV without your name."
- Seed ideas (Andrey Dyakov, approved), inserted once with the service key; the AI job normalises them:
  1. Micro robot arm powered by an ESP32
  2. Automated camera slider for hyperlapses
  3. Camera tracker that follows a person in frame ("big brother is watching you")
  4. Plant watering: soil moisture sensor and a pump
  5. Weather station with a web dashboard (ESP32 and BME280)
  6. Reaction-time game: LEDs and buttons, best score on a screen
  7. Ultrasonic distance meter or parking sensor
  8. Lab occupancy counter with an infrared beam at the door
  9. RFID tool check-out logger
  10. LED matrix sign scrolling the next Tech Lab lesson from the schedule
  11. Ultrasonic theremin with a buzzer or speaker
  12. Line-following robot car
  13. Self-balancing robot (MPU6050)
  14. Wi-Fi RGB mood lamp (WS2812 strip)
  15. Pomodoro timer with an OLED screen
  16. Desk light that turns on with motion (PIR sensor)
  17. MIDI controller with knobs and sliders
  18. Bluetooth gamepad for Unity games (ESP32)
  19. Noise-level traffic light for the lab
  20. "Simon says" memory game

## Failure behaviour

- Node off: the showcase TV is dark; the GitHub Pages `/tv/` still works on any network.
- Internet down: the TV keeps playing the last `tv.json` and `all.json` from the node.
- Big PC (Studio) off: only new ideas wait for the AI; the TV is unaffected.

## Tests

- `tests/test_tv.py`: playlist building (dates, active, missing or unplayable files, events window, no private keys, ideas without names) and the playable check, as pure functions.
- `supabase/tests/database/06_tv.sql`: RLS (staff only, anon denied), `on delete set null`.
- Office: logic tests for slide ordering and the date window; `flutter analyze`.
- Playwright: `apps/tv/index.html` with a sample `tv.json` and `all.json`: two room columns, the frame's aspect ratio follows the slide, the carousel advances.

## Later

- Video wall: several screens in sync.
- Upload from the office (needs HTTPS on the node).
