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
- the same machine (laser cutter, printer…) booked twice;
- portable equipment asked for by overlapping approved bookings beyond what the lab owns ("ESP32 needed 14 (this 10, Club 4), the lab has 12").

They are warnings. You decide.

Later: **Reject**, **Cancel booking** (removes it from the site), or **Mark done**.

## Equipment for a booking

Save the booking first. Then:
- **Add equipment:** pick an item, or type a new one, and set the quantity. Tick each line as you prepare it.
- **Issue kit:** hands the whole list out, from a place (default: Room 15) to a person (default: the requester). Tagged units on that shelf go first, and the office shows which tags before recording anything. If the place doesn't hold enough, you're told what's short and can still go ahead.
- **Return kit:** takes the whole list back into a place, starting with the tags that person holds.

## Inventory

The **Inventory** button (box icon, top bar) shows every item: how many are in each place, who has some on loan, and the total. Items with nothing left (all used up, broken and taken apart, given away) are hidden; **Show items with nothing left** brings them back. To take something out for good, record a **consume** with a note (for example "disassembled: broken"); its history stays.

Every long list in the office (items, places, people) is a search field: type part of a name, pick from the list, and **×** clears it. The public site works the same way.

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

For a tagged item (a console, a headset, a lab PC), pick it in **Tagged one** after the item: it moves on its own, quantity 1, and the office then knows exactly where that one is or who has it.

### Places and QR labels

**Places** (tree icon on the Inventory page) lists every room, cabinet, shelf and box, indented, with its code, how many items it holds and when it was last counted. Every place has a QR label. Scanning it with your phone opens that place in the office. If you're signed out, sign in: the email link opens that same place.

On a place's screen:
- **what should be here:** each item's quantity (and how many of those are untagged), then the tagged items with their condition. Tap a tagged item to mark it ok, broken or missing;
- **Record movement** starts from this place;
- **Edit** (pencil) changes the name, code, tier or where it sits. Don't change a code once its label is printed: the label and the Godot twin both use it;
- **Add a place inside** (folder icon), for example the racks and shelves on the -2 floor: `B2-R1`, then `B2-R1-S1`;
- **Tag an item** (QR icon): give one of the items here a tag. Leave the tag empty for the next `TL-` number, or type its old tag (`GS-031`). Then print its label.

### Stocktake: count a place

The spreadsheet from the previous team isn't trusted, so every place starts as **never counted**. To count one, open it (scan its label) and tap **Count**:
1. Type how many of each untagged item are really there.
2. Tick every tagged item you can see. Unticked ones are marked **missing**.
3. A tagged item that's here but not on the list (recorded on another shelf, still marked as lent, or never placed): type its tag or serial under **Found a tagged item that is not listed?** and tap **Found here**. It's moved here and ticked.
4. **Save count.** The differences are recorded as adjust movements (marked "stocktake"), and the place shows today's date. A tagged item you didn't find stays in the stock, marked missing, until a later count ticks it.

Something that's here but not on the list: cancel the count, **Record movement** → receive, then count.

### Needs attention

The top of the Inventory page lists what to sort out: places never counted (or not for 6 months), stock below zero, broken or missing tagged items, and items that look like the same thing under two names ("Cabo HDMI" / "Cabos HDMI"). Tap a place issue to open the place. For a pair of names, **Merge** keeps the name you pick and moves everything to it; **Not the same** hides the pair. **Dismiss** hides any other issue.

### Printing labels

From the Mac, in the repo: `uv run python scripts/labels.py --root R15` (one room and everything in it) or `--assets` for tagged items. It writes `~/Downloads/labels.html`; open it and print at 100 % on A4 (3 × 8 labels).

## Equipment requests (by QR or link)

Anyone with an email can ask for equipment at https://berlogabob.github.io/openlabtwin/kit/ (QR: `apps/site/web/qr/kit.svg`), **for a class** (with "every week until" for a course), **for lab work** in the Tech Lab, or **to take home** for a project. They pick courses from the timetable and items from the lab's list the same way as the schedule filters (type to search, pick from the list, × to remove), set a quantity on each item, and can describe anything else. Every public form (equipment, Book me, ideas) asks for the **student number**: the lab's local ID for a person; staff give their staff number. It's optional: nothing else in the lab needs it.

- The request arrives in the bookings list as **Equipment**, *requested*, titled Class kit, Lab work or Take-home kit, with the kit already listed and what it's for in **Purpose and notes**. Approve, prepare the lines, then **Issue kit** / **Return kit** as usual.
- The list only shows items marked **can be requested**: portable items start ticked. Change it on the Inventory page: tap an item.
- Only lab work appears on the public schedule (it uses the lab). Class kits and take-home kits stay private.
- A kit still out a day after its booking ended shows in **Needs attention** as *kit not returned*.
- The requester's private link shows the status, the dates and the items.

## The paper loan archive

The old A4 sheets of what students took home become data for statistics, in three steps:

1. **Photograph** each sheet flat, in good light, and drop the photos into the shared folder `smb://192.168.1.131/archive` (on the lab network; Finder → Go → Connect to Server on a Mac, or the Files app on a phone). The same photo twice is read once.
2. **Wait** up to 15 minutes: the lab computer reads each sheet with the AI on the big PC (about 1–2 minutes a sheet) and fills in its fields.
3. **Check**: Inventory → **Archive** (scroll icon) lists the sheets to check. Open one: the photo on one side (pinch or scroll to zoom), the fields on the other. Fix what the AI got wrong:
   - **Student:** picked by student number or name when they're already known; otherwise **New student**.
   - **Course**, **Out on**, **Back on** (dates as 2019-03-12).
   - **Lines:** the item as written, the quantity, and the lab item it is (suggested when the name is close). Leave "No item (keep the text)" when it matches nothing: the text is kept, and you can match it later.
   - **Approve** saves the loans; **Reject** keeps the sheet out of the statistics.

The AI's version is never used without your check. Historic loans don't change today's stock.

**Usage** (chart icon on the Inventory page) shows what was used most (archive and today's loans), what ran out (the most out at once reached what the lab owns: a candidate to buy more of), and use by course.

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

## The video wall

Office → the grid button (Video wall). The current picture appears above the screen grid. The top line says what the wall plays and how many screens are on. **Today** lists the next 12 hours of playback with start and end times. If the server has stopped reporting for over a minute, it shows a grey “Wall off or server down since …” line with the last screen count; grey squares show each screen's last seen time. The coloured squares are green when on, orange when on with a power or sync warning, and grey when off or the server is stale.

Use **Upload** in the Files block to add a photo or video to the TV and wall folder. It should appear in the list within a minute.

- **Identify all** shows each screen's code in big letters (10 s); **Test pattern** shows the alignment grid across the wall (60 s). Tap a screen square to do either on that screen only.
- Tap a screen square and choose **Restart client** to restart its player, or **Reboot Pi** to restart that computer. **Reboot all (30 s apart)** asks for confirmation, then reboots screens one at a time.
- **Blackout** turns every screen black; press again to turn it off. **Stop** shows the logo (or black) until **Play**.
- **Show now…** plays one thing immediately, above the playlist: Videowall (one file over all screens) or Mosaic (one file per screen, ticked files or all), with Fit (whole picture), Fill (cover, edges cut) or Center. **Back to schedule** returns to the playlist.
- **Emergency message…** displays typed text on every screen over a black background. It stays up until **Back to schedule**.
- **Preset buttons** under the controls show playlist entries marked “Show as a preset button”. Tap one to show that entry immediately; each playlist row also has a play button, and **Show now** begins 3 seconds ahead so the screens start together.
- **The playlist** works like the TV slides: order, dates, times of day, takeover, announcements ("show every … seconds") and "play during a schedule event". The same event linked on the TV and the wall starts on both in the same second. A videowall entry can draw a title, credits, the logo and a black frame (matte) across the screens. Mark an entry as a preset in its editor to add its one-tap button.
- Files come from the TV folder (`smb://192.168.1.131/tv`). A new video needs rendering first (about 3 × its length); the entry shows "rendering n%" and the wall shows its first frame meanwhile.

## The TV and the public site

- **Public schedule:** https://berlogabob.github.io/openlabtwin/. Every filter takes several values (two professors, two rooms). Bookings are blue and events green. A red line marks the current time in the list, day and week views.
- **Lab TV (showcase):** `http://192.168.1.131/tv/?room=<room>&room=<room>`, on the lab network, or from anywhere over Tailscale as `http://techlab-01/tv/…` (served by the edge node). A top line shows the day (left) and the room names (right); the left third shows the rooms stacked for today, as compact cards (finished items dimmed, the current one outlined, a red line at the current time); the right two thirds play the slides. Room names are the full IADE names from the schedule's Room filter, with spaces as `%20`.
- **Public TV:** `https://berlogabob.github.io/openlabtwin/tv/` (rooms as above) works on any network and shows the same as the lab TV, about 15 minutes behind. Everything you put on the TV is therefore public on the internet. Very long videos (every copy over 95 MB) play only in the lab.

## The TV slides

- **Files:** copy videos and photos into the shared folder `smb://192.168.1.131/tv` (Finder: Go → Connect to Server; Windows: `\\192.168.1.131\tv`), user `TechLAB` with its Samba password, from the lab network. Within a minute they appear in the office. The TV plays MP4 or WebM (H.264, VP8, VP9 or AV1) and JPG, PNG or WebP. The node also makes lighter copies of every video (480p, 720p, 1080p), which takes a few minutes after you add one; iPhone `.mov` and HEVC videos become playable once their copies exist. The TV picks the copy its computer plays smoothly: it starts from the device's memory and processor, steps down when it drops frames and back up after 5 smooth plays. Its footer shows the level in use ("video 720p").
- **The office:** the TV icon in the top bar opens the list of every page the TV plays, in order; the TV loops through it. **Add page** makes:
  - **Video or photo:** a file from the folder, with an optional caption. The frame takes the file's shape (portrait phone photos and videos included). Videos play muted and, by default, to the end (**Play the whole video**); switch that off to cut one after a number of seconds.
  - **Bio:** a name, role and short bio, with an optional photo.
  - **QR code:** a link and a caption; the node draws the code.
  - **Text:** a title and text.
  - **Upcoming events (automatic):** each approved event of the next 14 days, one page each, at this place in the loop.
  - **3 random student ideas (automatic):** a new random pick each loop, in the AI's version, with no names.
  - **Event mode**, on any page: **times** (for example 17:00–20:00, on top of the dates), **Full screen** (the page fills the TV and the schedule hides while it plays) and **Takeover** (during its dates and times the TV plays only takeover pages, in a loop, and switches back by itself afterwards; it switches at the exact minute, by the TV's own clock). The list marks in red a takeover whose dates and times overlap another takeover, and two pages that use the same file. A takeover must have an end ("Until" date or time, or a linked event), otherwise it would hold the TV for good.
  - **Announcement**, on any page: fill in **Show every … seconds** (for example 30, with the page's seconds at 10). The page leaves the loop and interrupts the TV every 30 seconds for 10 seconds, only within its dates and times; with **Full screen** it covers the schedule too, without it only the pages area. Empty the field to put it back in the loop. For a picture, drop it in the TV folder and add a Media page for it.

  **Play during a schedule event:** link a page to an approved event (or booking) and it plays exactly in that event's time slot, taking the dates and times from the schedule. If the event is moved, the page follows; if it is cancelled or deleted, the page stops. Typical use: put the event in the schedule (so it shows in the day's column and on the site), then link its video page, with Full screen and Takeover on.

  Each slide has its seconds on screen (default 10), optional start and end dates, and an on/off switch. Drag to reorder. If a page's file is missing from the folder (renamed or deleted), the page keeps its file name, the list says FILE MISSING, and the TV skips it until the file is back.
- **Starting pages:** the Book me QR code, the Idea hub QR code, Upcoming events and 3 random student ideas. Reorder, edit, hide or delete them like any other page.
- **Is the TV alive?** The top of the office TV screen shows the node's heartbeat: what plays now ("Takeover: PROTO26 until 20:00" or "Normal loop: 4 pages"), when the playlist was last built, and how many files. It turns red when the build is more than 5 minutes old or the last run failed (with the error). The TV's own footer also says so in red when its playlist is more than 5 minutes old.
- **Several screens:** every TV works out the current page from the clock, so all screens show the same page (and the same second of a video, the same three ideas) at the same moment. They need correct clocks.
- **Busy days:** the schedule column shrinks its text until every card fits.
- The TV reloads every minute. If the internet drops it keeps playing what it has; if the edge node is off, the showcase TV is dark and the public TV keeps playing its last version.
- **The TV computer:** see [edge-node.md → The TV computer](edge-node.md#the-tv-computer-raspberry-pi); its setup is the next [roadmap](ROADMAP.md) item.
- **Calendar:** `…/calendar/lab.ics` subscribes in Google Calendar, Apple Calendar or Outlook.
