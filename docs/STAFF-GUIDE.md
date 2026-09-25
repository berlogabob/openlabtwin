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
9. **Save** keeps it as *requested*; nothing is public yet. **Approve** publishes it: it's on the schedule, the TV and `lab.ics` within about 15 minutes, listed under the requester and the staff member in charge (you, for bookings you create), so the **Professor / staff** filter finds it.

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

Students scan the QR code (`apps/site/web/qr/book.svg`, served at `…/openlabtwin/qr/book.svg`, ready to print) or open https://berlogabob.github.io/openlabtwin/book/. Students and professors see your free slots for the next 7 days, pick one, and send their name, email and one line saying what they need (3–300 characters). That line lands in **Purpose and notes (private)**; add your own notes there, and a link or student number if it matters.

- **Your hours.** In the office, the clock icon in the top bar opens **Consultation hours**. Add your weekly hours (for example Tuesday 14:00–17:00, 30-minute slots). A slot is offered only when there's no lesson and no requested or approved booking in that room at that time. Without hours, students see "No free times".
- **Requests** arrive in the bookings list as **Consultation**, status *requested*. Open one to see who asked, and **their history**: every earlier request with its date, status and project. Approve, reject or cancel as usual.
- **The student's private link** shows the status (requested, approved, declined, cancelled or done) and the time. Nothing else is shown, and there's no email. Write to them from your mail if needed.
- **Public view:** an approved consultation shows on the schedule and TV only as "Consultation" in the room, under the staff member's name, never the student's.
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
- **A consultation about an idea.** The student's link has **Book a consultation about this idea**. It opens the booking form with the idea's title filled in as what they need.

## The TV and the public site

- **Public schedule:** https://berlogabob.github.io/openlabtwin/. Every filter takes several values (two professors, two rooms). Bookings are blue and events green. A red line marks the current time in the list, day and week views.
- **Lab TV (showcase):** `http://192.168.1.131/tv/?room=<room>&room=<room>`, on the lab network, or from anywhere over Tailscale as `http://techlab-01/tv/…` (served by the edge node). A top line shows the day (left) and the room names (right); the left third shows the rooms stacked for today, as compact cards (finished items dimmed, the current one outlined, a red line at the current time); the right two thirds play the slides. Room names are the full IADE names from the schedule's Room filter, with spaces as `%20`.
- **Public TV:** `…/tv/?room=<room>&room=<room>` on GitHub Pages works on any network, in the same layout. Its right side cycles only the Book me and Idea hub QR codes and upcoming events (your videos, photos, bios and the ideas live on the node). On a phone it shows the schedule only.

## The TV slides

- **Files:** copy videos and photos into the shared folder `smb://192.168.1.131/tv` (Finder: Go → Connect to Server; Windows: `\\192.168.1.131\tv`), user `TechLAB` with its Samba password, from the lab network. Within a minute they appear in the office. The TV plays MP4 or WebM (H.264, VP8, VP9 or AV1) and JPG, PNG or WebP. The node also makes lighter copies of every video (480p, 720p, 1080p), which takes a few minutes after you add one; iPhone `.mov` and HEVC videos become playable once their copies exist. The TV picks the copy its computer plays smoothly: it starts from the device's memory and processor, steps down when it drops frames and back up after 5 smooth plays. Its footer shows the level in use ("video 720p").
- **The office:** the TV icon in the top bar opens the list of every page the TV plays, in order; the TV loops through it. **Add page** makes:
  - **Video or photo:** a file from the folder, with an optional caption. The frame takes the file's shape. Videos play muted and, by default, to the end (**Play the whole video**); switch that off to cut one after a number of seconds.
  - **Bio:** a name, role and short bio, with an optional photo.
  - **QR code:** a link and a caption; the node draws the code.
  - **Text:** a title and text.
  - **Upcoming events (automatic):** each approved event of the next 14 days, one page each, at this place in the loop.
  - **3 random student ideas (automatic):** a new random pick each loop, in the AI's version, with no names.
  - **Event mode**, on any page: **times** (for example 17:00–20:00, on top of the dates), **Full screen** (the page fills the TV and the schedule hides while it plays) and **Takeover** (during its dates and times the TV plays only takeover pages, in a loop, and switches back by itself afterwards; it switches at the exact minute, by the TV's own clock). The list marks in red a takeover whose dates and times overlap another takeover, and two pages that use the same file. A takeover must have an end ("Until" date or time), otherwise it would hold the TV for good.

  Each slide has its seconds on screen (default 10), optional start and end dates, and an on/off switch. Drag to reorder. If a page's file is missing from the folder (renamed or deleted), the page keeps its file name, the list says FILE MISSING, and the TV skips it until the file is back.
- **Starting pages:** the Book me QR code, the Idea hub QR code, Upcoming events and 3 random student ideas. Reorder, edit, hide or delete them like any other page.
- **Is the TV alive?** The top of the office TV screen shows the node's heartbeat: what plays now ("Takeover: PROTO26 until 20:00" or "Normal loop: 4 pages"), when the playlist was last built, and how many files. It turns red when the build is more than 5 minutes old or the last run failed (with the error). The TV's own footer also says so in red when its playlist is more than 5 minutes old.
- **Several screens:** every TV works out the current page from the clock, so all screens show the same page (and the same second of a video, the same three ideas) at the same moment. They need correct clocks.
- **Busy days:** the schedule column shrinks its text until every card fits.
- The TV reloads every minute. If the internet drops it keeps playing what it has; if the edge node is off, the showcase TV is dark and the public TV still works.
- **The TV computer:** see [edge-node.md → The TV computer](edge-node.md#the-tv-computer-raspberry-pi); its setup is the next [roadmap](ROADMAP.md) item.
- **Calendar:** `…/calendar/lab.ics` subscribes in Google Calendar, Apple Calendar or Outlook.
