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

## The TV and the public site

- **Public schedule:** https://berlogabob.github.io/openlabtwin/. Every filter takes several values (two professors, two rooms). Bookings are blue and events green.
- **Lab TV:** `…/tv/?room=<room>&room=<room>` shows the rooms side by side for today. Finished items are dimmed and the current one is outlined.
- **Calendar:** `…/calendar/lab.ics` subscribes in Google Calendar, Apple Calendar or Outlook.
