# Equipment requests and the paper loan archive: design

Date: 2026-09-26. Status: approved in chat. Built as milestone A (equipment requests), then milestone B (the archive).

## Context

Bookings and smart storage share one database, but the link is used only when staff build a booking's kit by hand.

The user wants:
1. **An easy, optional way to ask for equipment,** for students, professors, classes, lab work, and taking things home. A professor who wants to share what a class needs should be able to do it in a minute.
2. **The paper archive digitised:** the old A4 sheets that recorded what students took home to work on projects. They feed statistics on what students used most and what to buy. This becomes a large thesis part (digital archive-atlas research).

Both must run on the lab's own machines: the edge node for orchestration, Studio's GPU for reading the sheets.

Decisions (user, 2026-09-26):
- Sheet photos go into a **shared folder on the node**.
- **Anyone with an email** may request equipment, as with Book me.
- **Both parts in one plan,** as two milestones.
- **No sheet photographed yet:** use a generic layout now and tune the prompts on the first photos.

What exists to reuse:
- **Book me's anonymous write path:** `request_consultation()` in `20260925090000_book_me_simpler.sql`, with `check_contact`/`file_student`, the honeypot, rate limits and status tokens. Its Jaspr pages are `apps/site/lib/pages/book_page.dart` and `status_page.dart`, with `rpc()` in `lib/book.dart`.
- **Kit lines, issue and return:** `activity_items` and `_kit`/`kitRows()` in `apps/office`.
- **Needs attention:** the `storage_issues` view.
- **Node jobs that call Studio:** `scripts/ideas_ai.py` (`AI_API=openai`, `AI_URL`, `AI_KEY`, runs every 15 min).
- **The shared-folder pattern:** `scripts/tv.py` (probing, `exif_orientation`) and the Samba setup in `edge-setup.sh` step 9.
- **The Mac OCR watcher:** `~/Nextcloud/InstantUpload/Screenshots/` (`prompts.py` PROMPT_OCR, model fallbacks, per-file state). Its prompts and retry idea are ported; the watchdog loop isn't, because cron fits the node.
- Studio vision models: `unsloth/gemma-4-26B-A4B-it-qat-GGUF`, `Qwen3.6-35B-A3B`, `qwen3.5`.

The catalogue fills once the smart storage import is applied.

**Public schedule:** an approved equipment booking with no room (a class kit, a take-home kit) is not exported. The class is already on the schedule, and a loan concerns nobody else. Lab work names the lab and shows as a booking, like any other use of the room.

## Milestone A: equipment requests (booking ↔ storage)

**Database** (`supabase/migrations/…_equipment_requests.sql`, test `09_equipment_requests.test.sql`):
- `items.lendable boolean`: true for portable items at migration time, and staff can untick any item. Only lendable, unmerged items appear in the public catalogue.
- `equipment_catalogue()` (anon, security definer): id, name and kind only. No places, counts or tags.
- `request_equipment(name, email, student_number, use, course, starts_at, ends_at, repeat_until, items jsonb, other, website)`:
  - `use` is one of: class, lab, home;
  - it creates an `activities` row, kind `equipment`, status requested, with a weekly `rrule` for a repeating class, plus its `activity_items`;
  - "something else" and the use go into `purpose`;
  - checks and limits as in Book me: `check_contact`, honeypot, 3 open requests per email, 30 in total, 1–20 lines;
  - it returns a status token.
- `equipment_status(token)`: the status, dates and items asked for.
- `storage_issues` gets `kit_not_returned`: an activity ended more than a day ago and still has issued minus returned > 0 (key `kit:<activity>`).

**Site** (Jaspr), `apps/site/lib/pages/kit_page.dart` and `kit_status_page.dart`, at `/kit/` and `/kit/status/?t=`:
- One short form:
  - who you are (name, email, student number optional);
  - what for: **for my class**, **lab work** or **take home**;
  - when: date and times, plus "every week until" for classes;
  - a searchable checklist from `equipment_catalogue()` with quantities, and "something else";
  - course (optional).
- The link to the private status page, as in Book me.
- A QR code `apps/site/web/qr/kit.svg` (segno, as `book.svg`), and a "Need equipment?" link on the Book me page.
- Pure logic (building the request, validation) in `lib/kit.dart`, tested in `test/logic_test.dart`.

**Office:**
- A request arrives in the bookings list as *equipment*, with its kit already filled in. Staff approve it, tick lines as prepared, and use Issue kit / Return kit as today.
- The booking form gains a **demand warning**: for each kit line, the sum of approved overlapping bookings that need the item, compared with its total stock. A pure `demandWarnings()` in `logic.dart`, tested.
- The Inventory item list gets a lendable toggle.

## Milestone B: the paper loan archive (thesis)

**Intake:** `edge-setup.sh` adds a Samba share `smb://192.168.1.131/archive` over `~/archive/inbox`, as the `tv` share is set up. Staff drop sheet photos into it from a phone or the Mac.

**Reading** (`scripts/archive_ocr.py`, cron every 15 min on the node, on Studio through the ideas env variables and `ARCHIVE_MODEL`, default the gemma-4-26B vision model):
- For each new image (by sha256, so a copy is never read twice):
  - turn it upright (reuse `tv.exif_orientation`) and downscale it to about 2000 px;
  - pass 1 transcribes it (the ported PROMPT_OCR);
  - pass 2 extracts JSON: date out, date back, name, student number, course, lines (item text, quantity), notes, and a confidence per field.
- The original moves to `~/archive/originals/`. The copy goes to a **private Supabase Storage bucket** `archive` (staff-only policy), so the HTTPS office can show it.
- If Studio is off, it retries next run. Errors are stored on the row.
- The model can't be trusted, so everything stays a proposal until a person reviews it (the RIMS rule).

**Database** (`…_loan_archive.sql`, test `10_loan_archive.test.sql`):
- `archive_sheets`: sha, file name, image path, photo date, raw text, extracted jsonb, model, status (new, extracted, reviewed, rejected), error, reviewer, time. Staff-only, audited.
- `archive_loans`: sheet, person, item, quantity, out_on, back_on. **Kept apart from `movements`,** so historic loans never change today's stock or who holds what.
- `match_item(text)`: the best items by `name_norm` trigram similarity, for the review form.
- Statistics views over `archive_loans` plus the `issue` movements, with source `archive` or `live`:
  - `usage_by_item` (per month and semester);
  - `usage_by_course`;
  - `peak_on_loan` (the most out at once versus units owned). Where the peak reaches what is owned, that is the "buy more" list.

**Office:**
- An **Archive** screen, a review queue: the sheet image next to a form prefilled from the extraction.
  - The person is matched by student number or name, or created as a student.
  - Each line gets its item suggested by `match_item`, a new item, or "unknown".
  - Approve writes the `archive_loans`; Reject keeps the sheet, marked rejected.
- A **Usage** screen: top items, top courses, and the buy list. Pure helpers are tested.

**For the thesis:** every step keeps its provenance: original image → downscaled copy → raw text → extraction (model, time) → the person's corrections → loans. The node's mirror (`psql openlabtwin`) serves the analysis queries, and `scripts/usage_export.py` writes CSVs for the thesis.

## Verification

- **Milestone A:**
  - `sqltest.py` 01–09 green: anon can request and read status, can't read items or stock, and the rate limits and honeypot hold.
  - Site `dart test`; office `flutter test`.
  - A browser e2e of `/kit/`: request → the office shows it with its kit → approve → issue → return. Throwaway rows.
  - The overdue rule appears for an ended, unreturned test booking.
- **Milestone B:**
  - Unit tests for the prompt parsing and JSON validation (as `tests/test_ideas_ai.py`).
  - A run on 3 sample sheet photos once the user has them, with field accuracy against a hand check reported in the doc.
  - Review of one sheet in the office writes `archive_loans`, and `usage_by_item` shows it.
  - `sqltest.py` 10 green: staff-only access, stock unaffected.
