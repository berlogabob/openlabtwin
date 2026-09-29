// OpenLabTwin links sheet, 2026-09-29. Build: typst compile docs/reports/2026-09-29-status.typ
#import "lib.typ": *

#show: report.with((
  title: "OpenLabTwin: links",
  footer: "OpenLabTwin · IADE Tech Lab · 2026-09-29",
))

#let u(url, label: none) = link(url, text(font: mono-font, size: 7.5pt)[#if label == none { url } else { label }])
#let m(t) = text(font: mono-font, size: 7.5pt)[#t]

#title-block(
  "OpenLabTwin: links",
  subtitle: "Where to open each part of the lab system",
  meta-line: "29 September 2026 · IADE Tech Lab",
  standfirst: [Everything below is live (checked 29 September 2026).],
)

= Anywhere

#data-table(
  ("Part", "Link"),
  (
    ("Schedule", u("https://berlogabob.github.io/openlabtwin/")),
    ("TV (a copy of the lab TV)", u("https://berlogabob.github.io/openlabtwin/tv/")),
    ("Book a consultation", u("https://berlogabob.github.io/openlabtwin/book/")),
    ("Share an idea", u("https://berlogabob.github.io/openlabtwin/ideas/")),
    ("Ask for equipment", u("https://berlogabob.github.io/openlabtwin/kit/")),
    ("Calendar feed", u("https://berlogabob.github.io/openlabtwin/calendar/lab.ics")),
    ("Staff office", u("https://berlogabob.github.io/openlabtwin/office/")),
  ),
  widths: (30%, 1fr),
  right-from: none,
)

= Lab network only

#data-table(
  ("Part", "Link"),
  (
    ("Showcase TV (videos, ideas, announcements)", u("http://192.168.1.131/tv/")),
    ("TV media folder", m("smb://192.168.1.131/tv")),
    ("Loan sheet photos", m("smb://192.168.1.131/archive")),
    ("AI (Unsloth Studio)", u("http://192.168.1.42:8888/")),
  ),
  widths: (30%, 1fr),
  right-from: none,
)

#callout(title: "Not done yet", tone: "info")[
  + TV on/off from the Pi (HDMI-CEC): switch Anynet+ on in the Samsung, then test.
  + Retire the old site (iade-lab-schedule).
  + Count the store: Room 15, the Vitrine, the -2 floor racks.
  + First old loan sheets into the archive share.
]
