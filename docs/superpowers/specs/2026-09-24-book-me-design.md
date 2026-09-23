# "Book me": consultation requests by QR, design

Date: 2026-09-24. Status: approved in chat; written for review.

## Why

Students ask Andrey (lab technician) for time to work on their projects. Today that happens by email back and forth. A QR code (printed, or on the lab TV) should lead to a form that shows Andrey's free consultation slots and takes a request. The request lands in the back office as a `requested` consultation to approve, and the student follows its status through a private link.

This is also the first **guarded public write path**. Until now the anonymous role could do nothing at all, and the idea hub (next project) will reuse the pattern.

## Decisions (user, 2026-09-24)

| Topic | Decision |
|---|---|
| Who can be booked | Andrey only for now. Each hours row carries a staff member, so other staff can be added later without a schema change. |
| Picking a time | from free slots generated from weekly consultation hours set in the office |
| Replying to the student | a private status link (requested / approved / declined, plus the time). No email service. |

## Student flow

1. The QR leads to `https://berlogabob.github.io/openlabtwin/book/`.
2. The page shows the free 30-minute slots of the next 14 days, grouped by day, in Lisbon time.
3. The student picks a slot and fills in:
   - name;
   - email;
   - project (a few lines);
   - an optional link (example, repository, social);
   - consent: "My contact is used only to arrange this consultation and is deleted 6 months after it."
4. **Send** shows the private status link `…/book/status/?t=<token>` with the advice to bookmark it.
5. The status page shows `requested`, `approved`, `rejected` (shown as "declined"), `cancelled` or `done`, plus the slot. Nothing else.

## Staff flow

- **Office:** a new "Consultation hours" screen (weekday, from, to, slot length) to add and remove rows.
- **Requests:** they appear in the bookings list as `requested` consultations titled "Consultation". The student's name and email come from `people`, and the project and link are in `purpose`. Approve, reject or cancel as usual; the status page follows.
- **Public view:** an approved consultation appears on the site as "Consultation" in the Tech Lab, with no student name (`requester_display` stays null).

## Data (migration)

- `consultation_hours`: `id, staff_id → people, place_id → places, weekday` (ISO 1–7), `from_time, to_time, slot_minutes` (default 30). Staff-only RLS, audited, no grants for anon, the same as every table.
- `activities.status_token uuid unique`: set only by `request_consultation`. It is a capability: knowing it reveals only status and time.

## Public functions (the only things anon can call)

All are `security definer`, with `search_path = public` and `EXECUTE` granted to `anon` and `authenticated` only.

- **`free_slots(p_from date, p_to date) → (starts_at timestamptz, ends_at timestamptz)`**
  - Scope: the days from `max(p_from, today)` to `min(p_to, today + 14)`, and only slots starting at least 1 hour from now.
  - For each `consultation_hours` row whose weekday matches, it generates slots in Lisbon local time.
  - It drops slots that overlap:
    - a lesson on that date in the hour row's place, matched by `places.iade_name` against `lessons.rooms`;
    - a `requested` or `approved` activity in that place, one-off or weekly. A weekly activity (`FREQ=WEEKLY;UNTIL=YYYYMMDD…`, the only kind the office creates) occurs on dates with the same ISO weekday between its start date and the UNTIL date, except its `exdates`.
- **`request_consultation(p_name, p_email, p_project, p_link, p_starts_at, p_consent, p_website) → uuid`**
  - **Honeypot:** a non-empty `p_website` (a field hidden from people) returns a random uuid and writes nothing.
  - **Validation:**
    - `p_consent` must be true;
    - name: 2–100 characters;
    - email: `^[^@\s]+@[^@\s]+\.[^@\s]+$`, stored lowercase, 3–200 characters;
    - project: 10–2000 characters;
    - link: empty, or `http(s)://…` up to 500 characters;
    - `p_starts_at` must be a current free slot.
  - **Limits:** at most 2 `requested` consultations per email, and 20 in total. Otherwise it raises a readable error.
  - **Records:**
    - the `people` row by email, created as kind `student` if new;
    - the activity: title "Consultation", layer booking, kind consultation, the hour row's place and staff member as owner, status `requested`, `purpose` = project + link, and a fresh `status_token`.
- **`consultation_status(p_token uuid) → (status text, starts_at timestamptz, ends_at timestamptz)`**, or no row for an unknown token.

`purge_consultation_contacts()` is **not** granted to anon or authenticated. Once a student's consultations all ended more than 6 months ago and nothing else refers to them (movements, other activities), it sets their email to null and their name to "Former student". The edge node's nightly `backup.py` calls it with the service key, after the backup.

## Site

- `apps/site` gets `/book/` and `/book/status/`, both `@client` pages. They call the functions through PostgREST (`POST /rest/v1/rpc/<name>`) with the anon key, passed to the build as `--dart-define=SUPABASE_URL=…` and `SUPABASE_ANON_KEY=…`. The keys are public by design, and `sync.yml` already has both as variables.
- The form logic (slot grouping by day, field checks mirroring the database rules) is pure Dart with `dart test`.
- A QR code for `/book/` is committed as `apps/site/web/qr/book.svg` (generated once with `segno`), ready to print and for the TV project.

## Tests

- **Database (`04_consultations.test.sql`):**
  - anon can execute the 3 functions and cannot read `activities`, `people` or `consultation_hours`;
  - `free_slots` excludes a lesson clash and a requested booking;
  - a request creates a `requested` activity with a token, and `consultation_status` returns it;
  - the same slot again is refused;
  - a third open request by the same email is refused;
  - missing consent is refused;
  - the honeypot writes nothing.
- **Site:** `dart test` for grouping and validation.
- **Browser (live database):**
  - open `/book/`, pick a slot, submit, and see the status "requested";
  - approve it in the database, and see "approved";
  - remove the test rows.

## Out of scope

- Email notifications, a captcha (add one if spam appears), and booking other staff (only the data is ready).
- A QR code on the status page. The link is shown to copy or bookmark.
