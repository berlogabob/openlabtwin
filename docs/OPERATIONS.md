# Operations

The runbook. For the why behind any of this see [ARCHITECTURE.md](ARCHITECTURE.md).

## How data reaches the public site

| What | When | How |
|---|---|---|
| IADE timetable | every 6 h (00:15, 06:15, 12:15, 18:15 UTC) | `sync.yml` scheduled run; also on every push and by hand (Actions → Sync and deploy → Run workflow) |
| Approved bookings and events | within about 15 min | the lab edge node runs `scripts/publish.sh` every 10 min and pushes when data changed; the push deploys ([edge-node.md](edge-node.md)) |
| Code changes | on push to `main` | `sync.yml` scrapes, exports, builds both apps, deploys |

A deploy takes about 4–6 minutes.

Until the edge node runs, or if it is down, publish by hand with Actions → Sync and deploy → Run workflow.

GitHub's scheduler is unreliable for this repo. The 10-minute cron never fired, and the 6-hourly one may be delayed or skipped. The edge node's `--scrape` cron is the backup for the timetable.

## Secrets and where they live

| Secret | Where | Used by |
|---|---|---|
| Supabase service role key | `.env` (gitignored, mode 600) on the dev Mac and the edge node; GitHub secret `SUPABASE_SERVICE_KEY` | `timetable.py`, `export.py`, `publish.sh`, `sync.yml` |
| Supabase URL | `.env`; GitHub secret `SUPABASE_URL` and variable `SUPABASE_URL` | same, plus the office build |
| Anon (publishable) key | GitHub variable `SUPABASE_ANON_KEY` | office build. Public by design: anon has no grants. |
| Database password | `.env` as `DB_PASSWORD` (the only copy) | recovery, `supabase link` |
| Supabase access token (personal, `sbp_…`) | macOS keychain, via `supabase login` in a real terminal | `scripts/sqltest.py` (migrations, DB tests) |
| GitHub push access for the edge node | a deploy key on that machine | `publish.sh` |

The service key bypasses every privacy rule. Keep it out of browsers, chats and commits. If it leaks, rotate it in the Supabase dashboard (Settings → API) and update `.env` everywhere and the GitHub secret.

## Staff accounts

Staff sign in at the office with an emailed link. Sign-ups are disabled, so an admin creates each account:

```bash
set -a; . ./.env; set +a
curl -s -X POST "$SUPABASE_URL/auth/v1/admin/users" -H "apikey: $SUPABASE_SERVICE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" -H "Content-Type: application/json" \
  -d '{"email":"name@example.com","email_confirm":true}'          # note the returned "id"
uv run python -c "import sys; sys.path.insert(0,'scripts'); import sqltest; print(sqltest.query(
  \"insert into people (name, kind, email, is_staff, auth_user_id) values ('Name', 'staff', 'name@example.com', true, '<id>')\"))"
```

To remove access, set `is_staff = false` (RLS then shows them nothing) or delete the auth user in the dashboard.

Current staff: Andrey Dyakov (people id 4).

Sign-in links may only return to `https://berlogabob.github.io/openlabtwin/office/**` and `http://127.0.0.1:8765/**` (local tests). Both are set in Supabase Auth → URL configuration. Supabase's built-in mailer sends a few emails per hour. Enough for staff; if links stop arriving, configure custom SMTP.

## The public write path ("Book me")

Anonymous visitors can read and write no table. They can call exactly three functions, all `security definer`, defined in `supabase/migrations/20260924100000_book_me.sql`:
- `free_slots` lists free slots;
- `request_consultation` checks every field, the free slot and the limits (2 open per email, 20 in total), then files the student under `people` by email;
- `consultation_status` returns only status and time for a private token.

The form's hidden "website" field is a honeypot: bots that fill it in get a fake token and nothing is stored. If spam gets through anyway, add a captcha. Student data is kept, identifiable, as their lab history (a decision of 2026-09-24).

The site calls the functions with the anon key, which the Pages build gets from the `SUPABASE_URL` and `SUPABASE_ANON_KEY` repository variables. To build locally: `jaspr build --dart-define=BASE=/openlabtwin/ --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`.

To regenerate the printable QR code: `uv run --with segno python -c "import segno; segno.make('https://berlogabob.github.io/openlabtwin/book/', error='m').save('apps/site/web/qr/book.svg', scale=8, border=2)"`.

## Idea hub AI

`scripts/ideas_ai.py` runs on the edge node every 15 minutes, as a cron line from `edge-setup.sh`.
1. It reads new ideas (`ai_done_at is null`).
2. It asks the chat model for JSON: title, summary, keywords, and English `brings` / `needs` skill lists.
3. It embeds the summary and each skill phrase.
4. It rebuilds the matches between approved ideas. The upsert leaves the students' connect flags alone.

- **Settings (`.env` on the edge node):**
  - `AI_API`: `ollama` (default) or `openai`, for any OpenAI-compatible server such as Unsloth Studio, llama.cpp or vLLM;
  - `AI_URL`: the server address (default `http://localhost:11434`; the older `OLLAMA_URL` still works);
  - `AI_KEY`: optional, for servers that want a key;
  - `IDEAS_MODEL` (default `ornith-1.5:9b`; use a small model such as `qwen2.5:3b` if the PC has under 16 GB of RAM);
  - `EMBED_MODEL` (default `nomic-embed-text`);
  - `EMBED_URL` and `EMBED_API`: a separate server for embeddings (default: the chat server).

  **Unsloth Studio** runs on the big lab PC (`http://192.168.1.42:8888` on the router network). It serves chat through `/v1/chat/completions` and also embeddings through `/v1/embeddings`: without a loaded embedding model it uses its built-in `bge-small-en-v1.5` (384 numbers per vector). With "Switch model by request" on (Studio → Settings → API) it serves any downloaded model by name, for example `ornith-ai/Ornith-1.5-9B-GGUF` or `ollama/qwen3-embedding:8b`. The key comes from Studio → avatar → Settings → API and starts with `sk-unsloth-`; `GET /v1/models` lists the model IDs.

  **Chosen setup (2026-09-24): chat on Studio, embeddings on the node.** The idea tables store 768-number vectors from `nomic-embed-text`, and the thresholds were measured on it, so embeddings stay on the node's Ollama. Settings: `AI_API=openai`, `AI_URL=http://192.168.1.42:8888`, `AI_KEY=sk-unsloth-…`, `IDEAS_MODEL=<model id>`, `EMBED_URL=http://localhost:11434`, `EMBED_API=ollama`. Chat on Studio's GPU took 6 s per idea, against about 1 minute on the node's CPU. If the big PC is off, ideas wait until it's back.

  **Check a server before switching:** `set -a; . ./.env; set +a; uv run python scripts/ideas_ai.py --check` runs one tiny chat and one embedding, and prints what works. It writes nothing. Both modes were verified against Ollama on 2026-09-24.
- **Changing the embedding model** (or its server) changes the vector numbers. Reprocess every idea afterwards (Office → Reprocess, or `update ideas set ai_done_at = null`), so all vectors come from the same model. Vectors from different models can't be compared.
- **Thresholds** (constants at the top of `ideas_ai.py`, measured on 2026-09-24 with a handful of examples):
  - `SIMILAR = 0.68`, the cosine between summaries;
  - `COMPLEMENTARY = 0.60`, the best phrase-to-phrase cosine between one side's needs and the other's skills;
  - `TOP = 5` matches per idea and kind.

  Re-tune them once there are real ideas, by printing the scores for pairs that staff agree should or shouldn't match.
- **Failures:** if the model doesn't give usable JSON twice, the idea waits for the next run (logged in `~/ideas_ai.log`). To test from the Mac, point `OLLAMA_URL` at the Mac's Ollama.
- **Anonymous access** is exactly three more functions: `submit_idea` (the same contact checks as Book me, 5 ideas per email per day, and a honeypot), `idea_status`, and `idea_connect` (both ideas must be approved). Contact details leave the database only when both sides have connected.

## Rooms and the TV

The lab rooms are rows in `places` (`kind = 'room'`). `iade_name` must be the exact room name the IADE timetable uses, so lessons, bookings and filters line up. `public = true` lets the room appear in the export. To add the second lab room:

```bash
# list the timetable's room names
uv run python -c "import sys; sys.path.insert(0,'scripts'); import sqltest; print(sqltest.query(\"select distinct unnest(rooms) r from lessons order by r\"))"
# add the room
uv run python -c "import sys; sys.path.insert(0,'scripts'); import sqltest; print(sqltest.query(
  \"insert into places (name, kind, iade_name, public) values ('Short name', 'room', '<exact IADE name>', true)\"))"
```

There are two TV pages, both showing the rooms named in the URL (`?room=<IADE name>&room=<IADE name>`, spaces as `+` or `%20`; without `room`, the Tech Lab), stacked in the left third under a top line with the day and the room names:
- **Showcase TV** `http://192.168.1.131/tv/…`, served by the edge node on the lab network (or over Tailscale): the right two thirds play the pages from the office TV list. Every screen shows the page the clock says (so several TVs stay in sync) and reloads at second 20 of each minute; takeovers switch on the TV's own clock; the last good copy keeps playing if a reload fails, and the footer says in red when the playlist is over 5 minutes old. Details in [edge-node.md → TV showcase](edge-node.md#tv-showcase).
- **Public TV** `https://berlogabob.github.io/openlabtwin/tv/…`: the same layout, with only the Book me and Idea hub QR codes and upcoming events on the right. It works anywhere.

## Database changes

1. Write the pgTAP test first in `supabase/tests/database/NN_name.test.sql`, wrapped in `begin … rollback`. Put every top-level pgTAP call at the start of a line as `select …`. `sqltest.py` captures exactly those lines, so indent any other `select`.
2. Add `supabase/migrations/<timestamp>_name.sql`.
3. Run `uv run python scripts/sqltest.py`. It applies pending migrations (recorded in `supabase_migrations.schema_migrations`, the same table `supabase db push` uses), then runs every test file in a rolled-back transaction.

There are no down migrations; write the inverse by hand. The seed (`supabase/seed.sql`) has already been loaded into production. Load it into a fresh project with `sqltest.py --seed`.

Anything new that must be public goes through `export.py`: add it to the explicit column list and to `KEYS`. Nothing else is exported.

## Tests

| What | Command | In CI |
|---|---|---|
| Python (parser, export, db helpers, idea AI, TV playlist) | `for t in tests/test_*.py; do uv run python "$t"; done` | yes |
| Showcase TV page (layout, carousel, takeover, video copies, busy days) | `uv run --with playwright python tests/check_tv_page.py` | yes (Chrome on the runner) |
| Database (schema, access, inventory, Book me, ideas, TV) | `uv run python scripts/sqltest.py` | no, run locally before pushing migrations |
| Site logic (filters, calendar maths) | `cd apps/site && dart analyze && dart test` | yes |
| Office logic (repeats, clashes, movements) | `cd apps/office && flutter analyze && flutter test` | yes |
| Browser, end to end | Playwright with system Chrome: `uv run --with playwright python …` | no |

For browser tests of the office, build it with `--dart-define=E2E=true`. That turns on Flutter's accessibility tree, which Playwright reads. Sign in with an admin-generated link (`POST /auth/v1/admin/generate_link`, type `magiclink`), so no email is needed. Wait about 400 ms after focusing a field before typing: Flutter drops keys typed too early.

To test Jaspr pages, use Playwright on system Chrome, not headless `--dump-dom` / `--virtual-time-budget`. The virtual clock makes the 3 MB data fetch look stuck at "Loading…".

## Network

The IADE network blocks outgoing Postgres ports 5432 and 6543, so `psql` and `supabase db push` time out from the lab. HTTPS works, so everything here uses it:
- the scripts use PostgREST;
- migrations and database tests use the Management API's SQL endpoint (`scripts/sqltest.py`);
- the office uses the Supabase REST and auth APIs.

The lab machines sit on the lab's ASUS router (`192.168.1.0/24`); the Mac, the node and the Studio PC are also on one Tailscale network, for access from home: [edge-node.md → The lab router network](edge-node.md#the-lab-router-network-since-2026-09-24).

## Keeping the project alive, and backups

- **Pausing:** free Supabase projects pause after 7 days of low activity, and any API request resets the timer. The edge node's 10-minute export keeps it awake. A paused project can be restored from the dashboard within a year.
- **Backups:** the free plan keeps none. `scripts/backup.py` on the edge node writes a nightly JSON copy of every table ([edge-node.md → Backups](edge-node.md#backups)).

## Security advisor

Run it after schema changes: Supabase dashboard → Advisors, or `GET https://api.supabase.com/v1/projects/<ref>/advisors/security` with the access token. As of 2026-09-24, the accepted findings are:
- `is_staff()` is callable by signed-in users. The RLS policies call it as the user, and it only reveals whether you yourself are staff.
- Leaked-password protection is off. There are no passwords, only email links.
- The performance advisor lists foreign keys without indexes. The tables are tiny; add indexes when `movements` or `activities` reach thousands of rows.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| An approved booking isn't on the site | nothing has exported since | check the edge node log (`~/publish.log`), or run Actions → Sync and deploy by hand |
| The site shows old lessons | the scheduled scrape didn't fire | run the workflow by hand; confirm the edge node's `--scrape` cron |
| `sync.yml` fails at `timetable.py` with "Too few lessons" | the IADE site changed or is down | the published site keeps its last version; check the source site, fix `timetable_parse.py` |
| `supabase login` fails with "non-TTY" | it needs a real terminal | run it in Terminal.app, from any folder |
| `sqltest.py` says "Cannot read migration history" | no or expired Supabase login | run `supabase login` again |
| The office says "Could not start" | the build is missing `SUPABASE_URL` or `SUPABASE_ANON_KEY` | check the GitHub variables |
| A sign-in link opens the office but stays on the login page | a different browser, or an expired link (1 h) | open the link in the same browser; send a new one |
| The office TV screen is red: "TV not updating" | the edge node is off, or `tv.py` fails (the error is shown) | check the node; `cat ~/tv.log` |
| A TV page says FILE MISSING | its file was renamed or deleted in the shared folder | put the file back (same name), or pick another file |
| The TV goes full screen or stays on one page at the wrong time | a takeover page is on; the office shows "Takeover: … until …" | switch that page off, or fix its dates and times |
| Videos stutter on the TV | the TV computer is slow | the TV steps down to lighter copies by itself (footer: "video 480p"); see [edge-node.md → The TV computer](edge-node.md#the-tv-computer-raspberry-pi) |

## The old site

`iade-lab-schedule` (https://berlogabob.github.io/iade-lab-schedule/) still runs on its own 6-hourly workflow until the TV computer is set to the showcase TV address for good (a [roadmap](ROADMAP.md) item). After that:
- replace its `docs/index.html` with a link to the new site;
- tell `lab.ics` subscribers the new address;
- archive the repo.
