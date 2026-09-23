"""lab.ics rendering, ported verbatim from iade-lab-schedule/scripts/fetch.py."""
import hashlib


CAL_TITLE = "IADE Lab Schedule"


VTIMEZONE = """BEGIN:VTIMEZONE
TZID:Europe/Lisbon
BEGIN:STANDARD
DTSTART:19701025T020000
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
TZOFFSETFROM:+0100
TZOFFSETTO:+0000
TZNAME:WET
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:19700329T010000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
TZOFFSETFROM:+0000
TZOFFSETTO:+0100
TZNAME:WEST
END:DAYLIGHT
END:VTIMEZONE"""


def key(l):
    return (l["date"], l["start"], l["course"], l["room"])


def ics_text(s):
    return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def fold(line):
    raw, out = line.encode(), []
    while len(raw) > 75:
        cut = 75 if not out else 74
        while (raw[cut] & 0xC0) == 0x80:  # don't split a UTF-8 char
            cut -= 1
        out.append(raw[:cut].decode())
        raw = raw[cut:]
    out.append(raw.decode())
    return "\r\n ".join(out)


def render_ics(lessons, stamp):
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//iade-lab-schedule//EN", "CALSCALE:GREGORIAN",
             "METHOD:PUBLISH", f"X-WR-CALNAME:{CAL_TITLE}", "X-WR-TIMEZONE:Europe/Lisbon",
             *VTIMEZONE.split("\n")]
    for l in lessons:
        d = l["date"].replace("-", "")
        uid = hashlib.sha1("|".join(key(l)).encode()).hexdigest()
        desc = "\n".join(x for x in [", ".join(l["teachers"]), "Groups: " + ", ".join(l["groups"]),
                                     l["type"], l["source_url"]] if x)
        lines += ["BEGIN:VEVENT", f"UID:{uid}@iade-lab-schedule", f"DTSTAMP:{stamp}",
                  f"DTSTART;TZID=Europe/Lisbon:{d}T{l['start'].replace(':', '')}00",
                  f"DTEND;TZID=Europe/Lisbon:{d}T{l['end'].replace(':', '')}00",
                  f"SUMMARY:{ics_text(l['course'])}", f"LOCATION:{ics_text(l['room'])}",
                  f"DESCRIPTION:{ics_text(desc)}", "END:VEVENT"]
    lines.append("END:VCALENDAR")
    return "\r\n".join(fold(x) for x in lines) + "\r\n"
