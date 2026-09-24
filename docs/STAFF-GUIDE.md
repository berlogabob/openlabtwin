# Staff guide

For lab technicians. Everything here happens in the back office: https://berlogabob.github.io/openlabtwin/office/

## Signing in

Type your staff email and press **Send sign-in link**. Open the link from the email in the same browser. If your email isn't a staff account, ask an admin ([Operations → Staff accounts](OPERATIONS.md#staff-accounts)).

## A request arrives by email

1. **New booking.**
2. **Title:** what the public sees, for example "Physical Computing workshop".
3. **Booking** or **Event.** Bookings are the lab's own use (classes, consultations, clubs). Events are wider: IADE-wide, off-site, workshops. They show in different colours on the site.
4. **Kind:** class, consultation, club, workshop, equipment, maintenance or external.
5. **Rooms:** tick one or more. For an off-site event, type the location instead.
6. **Date, from, to.** For a club that meets every week, switch on **Repeats weekly**, pick the end date, and list any dates to skip (holidays).
7. **Requested by:** pick the person, or add them with the person button. Their email stays private. **Shown on the site as** fills itself (for example "Prof. Cláudia"); change it if needed.
8. Optional: club or course, number of people, **Purpose and notes** (private), **Public note** (shown on the site).
9. **Save** keeps it as *requested*; nothing is public yet. **Approve** publishes it: it's on the schedule, the TV and `lab.ics` within about 15 minutes.

After every save the form lists **clashes**:
- lessons in the same rooms;
- other approved bookings in those rooms;
- the same machine (laser cutter, printer…) booked twice.

They are warnings. You decide.

Later: **Reject**, **Cancel booking** (removes it from the site), or **Mark done**.

## Equipment for a booking

Save the booking first. Then:
- **Add equipment:** pick an item, or type a new one, and set the quantity. Tick each line as you prepare it.
- **Issue kit:** hands the whole list out, from a place (default: fast storage) to a person (default: the requester). If the place doesn't hold enough, you're told what's short and can still go ahead.
- **Return kit:** takes the whole list back into a place.

## Inventory

The **Inventory** button (box icon, top bar) shows every item: how many are in each place, who has some on loan, and the total.

**Record movement** covers everything else:

| Kind | Meaning |
|---|---|
| receive | new stock arrives into a place |
| move | from one place to another (for example long-term → fast storage before a class) |
| issue | from a place to a person |
| return | from a person back into a place |
| consume | used up (resistors, filament) |
| adjust | correct a count (+ or −) after a stock check |

Movements are never edited or deleted. Fix a mistake with an **adjust**, so the history stays true. It's also what the thesis measures.

## "Book me": students request consultations by QR

Students scan the QR code (`apps/site/web/qr/book.svg`, served at `…/openlabtwin/qr/book.svg`, ready to print) or open https://berlogabob.github.io/openlabtwin/book/. They see your free slots for the next 14 days, pick one, and send their name, email, project, an optional link and an optional student number.

- **Your hours.** In the office, the clock icon in the top bar opens **Consultation hours**. Add your weekly hours (for example Tuesday 14:00–17:00, 30-minute slots). A slot is offered only when there's no lesson and no requested or approved booking in that room at that time. Without hours, students see "No free times".
- **Requests** arrive in the bookings list as **Consultation**, status *requested*. Open one to see the student, their link, and **their history**: every earlier request with its date, status and project. Approve, reject or cancel as usual.
- **The student's private link** shows the status (requested, approved, declined, cancelled or done) and the time. Nothing else is shown, and there's no email. Write to them from your mail if needed.
- **Public view:** an approved consultation shows on the schedule and TV only as "Consultation" in the room, with no name.
- **Limits:** at most 2 open requests per student and 20 in total. A student's requests are all linked to one person by their email: that's the lab history you report on.

## Idea hub

Students drop project ideas at https://berlogabob.github.io/openlabtwin/ideas/. The printable QR code is `…/openlabtwin/qr/ideas.svg`. The form asks for name, email, an optional student number, the idea, an optional link, "I can bring" and "I'm looking for". They get a private link.

- **The AI.** Every 15 minutes the lab PC reads new ideas with the local model (ornith). It writes an English title, a summary and keywords, and turns "I can bring" and "I'm looking for" into skill names. The student sees this on their link straight away. Nothing leaves the lab.
- **The office.** The bulb icon in the top bar opens **Ideas** (New / Approved / Archived, with a keyword filter). An idea shows what the student wrote, the AI version (edit it and press **Save AI text**), their other ideas, and its matches.
  - **Approve** makes an idea matchable. Matches appear only between approved ideas, on the next AI run.
  - **Archive** retires an idea.
  - **Workshop bank** marks it for workshops (the list shows a cap icon).
  - **Reprocess** has the AI read it again.
- **Matches.** *Similar* means a close topic. *Complementary* means one student is looking for what the other can bring. A student sees each match as the other idea's AI title and the other student's first name. When **both** tap "I'd like to connect", each sees the other's email and link. The lab never gives out contacts otherwise.
- **A consultation about an idea.** The student's link has **Book a consultation about this idea**. It opens the booking form with the idea filled in as the project.

## The TV and the public site

- **Public schedule:** https://berlogabob.github.io/openlabtwin/. Every filter takes several values (two professors, two rooms). Bookings are blue and events green.
- **Lab TV:** `…/tv/?room=<room>&room=<room>` shows the rooms side by side for today. Finished items are dimmed and the current one is outlined.
- **Calendar:** `…/calendar/lab.ics` subscribes in Google Calendar, Apple Calendar or Outlook.
