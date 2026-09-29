// OpenLabTwin status and links, 2026-09-29. Build: typst compile docs/reports/2026-09-29-status.typ
// Every status below was checked on 2026-09-29 around 15:10 (HTTP codes, database counts, DB tests, CI, git, node and Pi over SSH).
#import "lib.typ": *

#show: report.with((
  title: "OpenLabTwin: status and links",
  footer: "OpenLabTwin · IADE Tech Lab · status 2026-09-29",
))

#let u(url, label: none) = link(url, text(font: mono-font, size: 7.5pt)[#if label == none { url } else { label }])
#let m(t) = text(font: mono-font, size: 7.5pt)[#t]
#let room = "?room=Lab.+e+Estudo+de+Jogos+-+Tech+Lab+(Oriente)"

#title-block(
  "OpenLabTwin: status and links",
  subtitle: "Every part of the lab system, and where to open it",
  meta-line: "29 September 2026 · Andrey Dyakov, IADE Tech Lab · repo github.com/berlogabob/openlabtwin",
  standfirst: [Everything is live and nothing waits to be pushed. Since 26 September: smart storage and the spreadsheet import went live, students can request equipment (`/kit/`), the loan sheet reader and the database mirror run on the node, and *the showcase TV now runs on its own Raspberry Pi* with timed announcements. Open work is on the floor, not in code: counting the store, the first archive sheets, and testing the TV's power switching.],
)

#kpi-row((
  ("10 603", "lessons", "to 5 Feb 2027"),
  ("140", "items", "83 tagged"),
  ("51", "ideas", "idea hub"),
  ("7", "TV pages", "heartbeat 15:08"),
  ("11 / 11", "DB tests", "all green"),
))

= Public (GitHub Pages)

#data-table(
  ("Part", "Link", "Checked"),
  (
    ("Schedule", u("https://berlogabob.github.io/openlabtwin/"), pill("200 live", tone: "ok")),
    ("Lab TV (QR and events)", u("https://berlogabob.github.io/openlabtwin/tv/" + room, label: "…/openlabtwin/tv/?room=…Tech Lab (Oriente)"), pill("200 live", tone: "ok")),
    ("Calendar feed", u("https://berlogabob.github.io/openlabtwin/calendar/lab.ics", label: "…/openlabtwin/calendar/lab.ics"), pill("200 live", tone: "ok")),
    ("Book a consultation", u("https://berlogabob.github.io/openlabtwin/book/"), pill("200 live", tone: "ok")),
    ("Share an idea", u("https://berlogabob.github.io/openlabtwin/ideas/"), pill("200 live", tone: "ok")),
    ("Ask for equipment (new)", u("https://berlogabob.github.io/openlabtwin/kit/"), pill("200 live", tone: "ok")),
    ("QR codes to print", [#u("https://berlogabob.github.io/openlabtwin/qr/book.svg", label: "qr/book.svg") · #u("https://berlogabob.github.io/openlabtwin/qr/ideas.svg", label: "qr/ideas.svg")], pill("200 live", tone: "ok")),
    ("Staff office", u("https://berlogabob.github.io/openlabtwin/office/"), pill("200 live", tone: "ok")),
    ("A storage place (QR label)", u("https://berlogabob.github.io/openlabtwin/office/?place=R15-L-S3", label: "…/office/?place=R15-L-S3"), pill("200 live", tone: "ok")),
    ("Schedule data", u("https://berlogabob.github.io/openlabtwin/data/all.json", label: "…/openlabtwin/data/all.json"), pill("200 live", tone: "ok")),
    ("Old site (until retired)", u("https://berlogabob.github.io/iade-lab-schedule/"), pill("200 still up", tone: "info")),
  ),
  widths: (32%, 1fr, auto),
  right-from: 2,
)

= In the lab (local network and Tailscale)

#data-table(
  ("Part", "Link", "Checked"),
  (
    ("Showcase TV, lab network", u("http://192.168.1.131/tv/" + room, label: "http://192.168.1.131/tv/?room=…"), pill("200 live", tone: "ok")),
    ("Showcase TV, Tailscale", u("http://techlab-01/tv/" + room, label: "http://techlab-01/tv/?room=…"), pill("200 live", tone: "ok")),
    ("TV computer (Pi 3 B, kiosk)", m("ssh -i ~/.ssh/techlab tv@techlab-tv.local"), pill("on the TV", tone: "ok")),
    ("TV media folder (Samba)", m("smb://192.168.1.131/tv"), pill("lab only", tone: "neutral")),
    ("Loan sheet photos (Samba)", m("smb://192.168.1.131/archive"), pill("0 sheets yet", tone: "neutral")),
    ("Edge node TechLAB-01 (SSH)", m("ssh -i ~/.ssh/techlab TechLAB@techlab-01"), pill("SSH ok", tone: "ok")),
    ("Node logs and backups", m("~/publish.log, ~/tv.log, ~/openlabtwin-backups/"), pill("backup 29 Sep", tone: "ok")),
    ("Database mirror", m("psql openlabtwin   (on the node)"), pill("loaded 29 Sep", tone: "ok")),
    ("Unsloth Studio (AI, big PC)", [#u("http://192.168.1.42:8888/", label: "http://192.168.1.42:8888") · #u("http://desktop-vdsrh2e:8888/", label: "desktop-vdsrh2e:8888")], pill("200 live", tone: "ok")),
    ("Repo on the Mac", m("~/Documents/GitHub/openlabtwin"), pill("in sync", tone: "ok")),
  ),
  widths: (32%, 1fr, auto),
  right-from: 2,
)

= Parts and their state

#scorecard((
  ("Schedule, filters, calendar feed (M1–2)", "Live", "ok", "scraped every 6 h"),
  ("Office: bookings, approval, equipment (M3)", "Live", "ok", "one picker for long lists"),
  ("Inventory: movements, stock, loans (M4)", "Live", "ok", "210 movements"),
  ("Book me", "Live", "ok", "no hours set yet"),
  ("Idea hub", "Live", "ok", "51 ideas"),
  ("Equipment requests (/kit/)", "Live", "ok", "class, lab work, take home"),
  ("Smart storage: codes, tags, stocktake", "Live", "ok", "28 places, 38 to attend"),
  ("Spreadsheet import", "Applied 27 Sep", "ok", "140 items, 83 tagged"),
  ("Edge node TechLAB-01", "Live", "ok", "publishes every 10 min"),
  ("Read-only mirror on the node", "Live", "ok", "rebuilt nightly"),
  ("Loan sheet archive reader", "Live, unused", "info", "waits for first photos"),
  ("TV showcase", "Live", "ok", "5 pages in the loop"),
  ("TV announcements (every N s)", "Live", "ok", "announcement01.png, 10 s of 30"),
  ("TV computer (Raspberry Pi)", "Live", "ok", "boots into the TV page"),
  ("TV on/off over HDMI-CEC", "Pending", "warn", "set up, not tested on the Samsung"),
  ("Video wall", "Own repo", "info", "github.com/berlogabob/videowall"),
  ("M5: demand forecast, Godot twin", "Not started", "neutral", "place codes ready"),
))

#callout(title: "Next, in order", tone: "info")[
  + TV: switch Anynet+ on in the Samsung and test on/off; note which video quality the footer settles on.
  + Retire the old site: push the ready branch `retire-to-openlabtwin` in `iade-lab-schedule`.
  + Count Room 15 and the Vitrine; add the -2 floor racks; set the cupboard rooms; record the PlayStation loans.
  + Photograph 3–5 old loan sheets, drop them in the archive share, check them in the office.
]

= Code and documents

#data-table(
  ("What", "Link"),
  (
    ("OpenLabTwin repo", u("https://github.com/berlogabob/openlabtwin")),
    ("Docs", u("https://github.com/berlogabob/openlabtwin/tree/main/docs")),
    ("TV Pi setup", m("scripts/tv-pi-setup.sh · docs/edge-node.md → The TV computer")),
    ("Actions (sync and deploy, tests)", u("https://github.com/berlogabob/openlabtwin/actions")),
    ("Old schedule repo", u("https://github.com/berlogabob/iade-lab-schedule")),
  ),
  widths: (32%, 1fr),
  right-from: none,
)

