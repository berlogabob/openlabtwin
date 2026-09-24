# "Book me": consultation requests by QR, design

Date: 2026-09-24. Status: approved in chat; written for review.

## Why

Students ask Andrey (lab technician) for time to work on their projects. Today that happens by email back and forth. A QR code (printed, or on the lab TV) should lead to a form that shows Andrey's free consultation slots and takes a request. The request lands in the back office as a `requested` consultation to approve, and the student follows its status through a private link.

Every request is kept, **identifiable, as the student's lab history**: a logbook of what each student works on and when they needed help. It feeds Andrey's monthly reports and the lab's ongoing ethnographic research, and helps shape courses around students' real interests. Students already consented through their IADE agreements (user, 2026-09-24), so there's no extra consent step, no deletion and no pseudonymisation. Access stays staff-only (RLS), as for all personal data.

This is also the first **guarded public write path**. Until now the anonymous role could do nothing at all, and the idea hub (next project) will reuse the pattern.

## Decisions (user, 2026-09-24)

| Topic | Decision |
|---|---|
| Who can be booked | Andrey only for now. Each hours row carries a staff member, so other staff can be added later without a schema change. |
| Picking a time | from free slots generated from weekly consultation hours set in the office |
| Replying to the student | a private status link (requested / approved / declined, plus the time). No email service. |
| Data kept | everything, identifiable, indefinitely: the student's history is the point. No consent tick, only a one-line notice. |

## Student flow

1. The QR leads to `https://berlogabob.github.io/openlabtwin/book/`.
2. The page shows the free 30-minute slots of the next 14 days, grouped by day, in Lisbon time.
3. The student picks a slot and fills in:
   - name;
   - email;
   - project (a few lines);
   - an optional link (example, repository, social);
   - optional student number (to match official records);

   Under **Send**, one line of text: "Your request is saved in your lab history, visible to lab staff only."
4. **Send** shows the private status link `…/book/status/?t=<token>` with the advice to bookmark it.
5. The status page shows `requested`, `approved`, `rejected` (shown as "declined"), `cancelled` or `done`, plus the slot. Nothing else.

## Staff flow

- **Office:** a new "Consultation hours" screen (weekday, from, to, slot length) to add and remove rows.
- **Requests:** they appear in the bookings list as `requested` consultations titled "Consultation". The student's name and email come from `people`, the project is in `purpose`, and the link is in `contact_link`. The booking form shows the link and the student's earlier consultations, both read-only. Approve, reject or cancel as usual; the status page follows.
- **Public view:** an approved consultation appears on the site as "Consultation" in the Tech Lab, with no student name (`requester_display` stays null).

## Data (migration)

- `consultation_hours`: `id, staff_id → people, place_id → places, weekday` (ISO 1–7), `from_time, to_time, slot_minutes` (default 30). Staff-only RLS, audited, no grants for anon, the same as every table.
- `activities.status_token uuid unique`: set only by `request_consultation`. It is a capability: knowing it reveals only status and time.
- `activities.contact_link text`: the student's optional link, kept apart from `purpose` so it can be removed on its own. Links often identify a person.
- `people.student_number text`: optional, unique when present.

## Public functions (the only things anon can call)

All are `security definer`, with `search_path = public` and `EXECUTE` granted to `anon` and `authenticated` only.

- **`free_slots(p_from date, p_to date) → (starts_at timestamptz, ends_at timestamptz)`**
  - Scope: the days from `max(p_from, today)` to `min(p_to, today + 14)`, and only slots starting at least 1 hour from now.
  - For each `consultation_hours` row whose weekday matches, it generates slots in Lisbon local time.
  - It drops slots that overlap:
    - a lesson on that date in the hour row's place, matched by `places.iade_name` against `lessons.rooms`;
    - a `requested` or `approved` activity in that place, one-off or weekly. A weekly activity (`FREQ=WEEKLY;UNTIL=YYYYMMDD…`, the only kind the office creates) occurs on dates with the same ISO weekday between its start date and the UNTIL date, except its `exdates`.
- **`request_consultation(p_name, p_email, p_project, p_link, p_starts_at, p_student_number, p_website) → uuid`**
  - **Honeypot:** a non-empty `p_website` (a field hidden from people) returns a random uuid and writes nothing.
  - **Validation:**
    - name: 2–100 characters;
    - email: `^[^@\s]+@[^@\s]+\.[^@\s]+$`, stored lowercase, 3–200 characters;
    - project: 10–2000 characters;
    - link: empty, or `http(s)://…` up to 500 characters;
    - student number: empty, or 1–30 letters, digits or dashes;
    - `p_starts_at` must be a current free slot.
  - **Limits:** at most 2 `requested` consultations per email, and 20 in total. Otherwise it raises a readable error.
  - **Records:**
    - the `people` row by email, created as kind `student` if new. The name is updated, and so is the student number when given;
    - the activity: title "Consultation", layer booking, kind consultation, the hour row's place and staff member as owner, status `requested`, `purpose` = project, `contact_link` = link, and a fresh `status_token`.
- **`consultation_status(p_token uuid) → (status text, starts_at timestamptz, ends_at timestamptz)`**, or no row for an unknown token.

**Student history (office).** A student's `people` row gathers every consultation (and later ideas). The office booking form shows the requester's earlier consultations (date, status, project) under the requester field, so the story is at hand when a request arrives. Reports are queries over `activities` joined to `people`, grouped by month.

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
  - a repeat request by the same email reuses the same `people` row, so the history is linked;
  - the honeypot writes nothing.
- **Site:** `dart test` for grouping and validation.
- **Browser (live database):**
  - open `/book/`, pick a slot, submit, and see the status "requested";
  - approve it in the database, and see "approved";
  - remove the test rows.

## Out of scope

- Email notifications, a captcha (add one if spam appears), and booking other staff (only the data is ready).
- A QR code on the status page. The link is shown to copy or bookmark.
