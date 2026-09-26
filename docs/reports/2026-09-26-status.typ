// OpenLabTwin status and links, 2026-09-26. Build: typst compile docs/reports/2026-09-26-status.typ
// Every status below was checked on 2026-09-26 (HTTP codes, database counts, git, the node over SSH).
#import "lib.typ": *

#show: report.with((
  title: "OpenLabTwin: status and links",
  footer: "OpenLabTwin · IADE Tech Lab · status 2026-09-26",
))

#let u(url, label: none) = link(url, text(font: mono-font, size: 7.5pt)[#if label == none { url } else { label }])
#let m(t) = text(font: mono-font, size: 7.5pt)[#t]
#let room = "?room=Lab.+e+Estudo+de+Jogos+-+Tech+Lab+(Oriente)"

#title-block(
  "OpenLabTwin: status and links",
  subtitle: "Every part of the lab system, and where to open it",
  meta-line: "26 September 2026 · Andrey Dyakov, IADE Tech Lab · repo github.com/berlogabob/openlabtwin",
  standfirst: [The public site, the booking and idea forms, the staff office, the lab TV and the edge node are live. *Smart storage is built and tested, but not deployed yet:* 11 commits wait on the Mac (and `main` is one node commit behind GitHub, so rebase before pushing). The spreadsheet import is waiting for review.],
)

#kpi-row((
  ("10 653", "lessons", "to 5 Feb 2027"),
  ("51", "ideas", "idea hub"),
  ("6", "TV pages", "heartbeat 22:01"),
  ("8 / 8", "DB tests", "all green"),
  ("11", "to push", "commits"),
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
    ("QR codes to print", [#u("https://berlogabob.github.io/openlabtwin/qr/book.svg", label: "qr/book.svg") · #u("https://berlogabob.github.io/openlabtwin/qr/ideas.svg", label: "qr/ideas.svg")], pill("200 live", tone: "ok")),
    ("Staff office", u("https://berlogabob.github.io/openlabtwin/office/"), pill("200, old build", tone: "warn")),
    ("A storage place (QR label)", u("https://berlogabob.github.io/openlabtwin/office/?place=R15-L-S3", label: "…/office/?place=R15-L-S3"), pill("after push", tone: "neutral")),
    ("Schedule data", u("https://berlogabob.github.io/openlabtwin/data/all.json", label: "…/openlabtwin/data/all.json"), pill("200 live", tone: "ok")),
    ("Old site (until TV switch)", u("https://berlogabob.github.io/iade-lab-schedule/"), pill("200 still up", tone: "info")),
  ),
  widths: (32%, 1fr, auto),
  right-from: 2,
)

= In the lab (local network and Tailscale)

#data-table(
  ("Part", "Link", "Checked"),
  (
    ("Showcase TV, lab network", u("http://192.168.1.131/tv/" + room, label: "http://192.168.1.131/tv/?room=…"), pill("off network", tone: "neutral")),
    ("Showcase TV, Tailscale", u("http://techlab-01/tv/" + room, label: "http://techlab-01/tv/?room=…"), pill("200 live", tone: "ok")),
    ("TV media folder (Samba)", m("smb://192.168.1.131/tv"), pill("lab only", tone: "neutral")),
    ("Edge node TechLAB-01 (SSH)", m("ssh -i ~/.ssh/techlab TechLAB@techlab-01"), pill("SSH ok", tone: "ok")),
    ("Node logs and backups", m("~/publish.log, ~/tv.log, ~/openlabtwin-backups/"), pill("backup 26 Sep", tone: "ok")),
    ("Database mirror (after step 10)", m("psql openlabtwin   (on the node)"), pill("not installed", tone: "neutral")),
    ("Unsloth Studio (AI, big PC)", [#u("http://192.168.1.42:8888/", label: "http://192.168.1.42:8888") · #u("http://desktop-vdsrh2e:8888/", label: "desktop-vdsrh2e:8888")], pill("200 Tailscale", tone: "ok")),
    ("TV computer (Pi)", m("192.168.1.194"), pill("waiting SSH", tone: "warn")),
    ("Repo on the Mac", m("~/Documents/GitHub/openlabtwin"), pill("11 ahead, 1 behind", tone: "warn")),
    ("QR labels (made on the Mac)", m("scripts/labels.py → ~/Downloads/labels.html"), pill("tested", tone: "ok")),
  ),
  widths: (32%, 1fr, auto),
  right-from: 2,
)

= Parts and their state

#scorecard((
  ("Schedule, filters, calendar feed (M1–2)", "Live", "ok", "scraped every 6 h"),
  ("Office: bookings, approval, equipment (M3)", "Live", "ok", "1 staff account"),
  ("Inventory: movements, stock, loans (M4)", "Live", "ok", "no items until import"),
  ("Book me", "Live", "ok", "no hours set yet"),
  ("Idea hub", "Live", "ok", "51 ideas"),
  ("Edge node TechLAB-01", "Live", "ok", "publishes every 10 min"),
  ("TV showcase", "Live", "ok", "4 pages playing"),
  ("Smart storage: codes, tags, stocktake", "Built, not deployed", "warn", "DB live, office on push"),
  ("Spreadsheet import", "Pending review", "warn", "141 items, 83 tagged"),
  ("Read-only mirror on the node", "Built, not installed", "warn", "edge-setup step 10"),
  ("TV computer (Raspberry Pi)", "Blocked", "bad", "no SSH access yet"),
  ("Video wall", "Own repo", "info", "github.com/berlogabob/videowall"),
  ("M5: demand forecast, Godot twin", "Not started", "neutral", "place codes ready"),
))

= Code and documents

#data-table(
  ("What", "Link"),
  (
    ("OpenLabTwin repo", u("https://github.com/berlogabob/openlabtwin")),
    ("Docs (storage parts after push)", u("https://github.com/berlogabob/openlabtwin/tree/main/docs")),
    ("Smart storage design and plan", m("docs/superpowers/{specs,plans}/2026-09-26-smart-storage*")),
    ("Actions (sync and deploy)", u("https://github.com/berlogabob/openlabtwin/actions")),
    ("Old schedule repo", u("https://github.com/berlogabob/iade-lab-schedule")),
  ),
  widths: (32%, 1fr),
  right-from: none,
)

#callout(title: "Next, in order", tone: "info")[
  + Review the import dry run and the 13 rows it leaves out (student PlayStation loans), then `--apply`.
  + `git pull --rebase`, then push: the office with Places and the stocktake goes live.
  + On the node: `git pull` and `scripts/edge-setup.sh` (step 10 installs the mirror).
  + Print labels, count Room 15 and the Vitrine, add the -2 floor racks, set the cupboard rooms.
  + The TV Pi, once SSH access is there.
]
