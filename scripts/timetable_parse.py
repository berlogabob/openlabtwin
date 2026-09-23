"""IADE timetable fetch + parse, ported verbatim from iade-lab-schedule/scripts/fetch.py."""
import html
import re
import time
import urllib.request
from datetime import date, datetime, timedelta
from html.parser import HTMLParser
from zoneinfo import ZoneInfo


BASE = "https://horariosturmas.europeia.pt/UE_IADE/HorariosTurmas/"


TZ = ZoneInfo("Europe/Lisbon")


DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


LINK_RE = re.compile(r'href="(turma_[^"?]+_\d*?(\d{8})\.html)')


TIME_RE = re.compile(r"^(\d{2}:\d{2})-(\d{2}:\d{2})$")


TREE_RE = re.compile(r"<li>IADE:\s*([^<]+?)\s*<ul>|<li>([A-Z0-9]+)<ul>")


DEGREES = [("Licenciatura", "Bachelor"), ("Mestrado", "Master"), ("Doutoramento", "PhD")]


def get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "iade-lab-schedule (+github pages)"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.read().decode("utf-8-sig", errors="replace")
        except OSError:
            if i == tries - 1:
                raise
            time.sleep(2 * (i + 1))


def group_programmes(index_html):
    """Index tree 'IADE: Mestrado em X' > Ano 1 > ... > 'MCIA001N01' -> {"MCIA001N01": "Mestrado em X"}."""
    out, programme = {}, None
    for heading, group in TREE_RE.findall(index_html):
        if heading:
            programme = heading
        elif programme:
            out[group] = programme
    return out


def degree(programme):
    return next((label for word, label in DEGREES if word in programme), "Other")


def find_pages(index_html, today):
    """Return filenames whose last week is the current week or later."""
    this_monday = today - timedelta(days=today.weekday())
    return sorted({name for name, last in LINK_RE.findall(index_html)
                   if datetime.strptime(last, "%Y%m%d").date() >= this_monday})


class _Cells(HTMLParser):
    """Collect table rows as lists of (text, rowspan, colspan)."""

    def __init__(self):
        super().__init__()
        self.rows, self.cell = [], None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "tr":
            self.rows.append([])
        elif tag == "td" and self.rows:
            self.cell = [[], int(a.get("rowspan") or 1), int(a.get("colspan") or 1)]
        elif tag == "br" and self.cell:
            self.cell[0].append("\n")

    def handle_endtag(self, tag):
        if tag == "td" and self.cell:
            text = "".join(self.cell[0]).replace("\xa0", " ")
            self.rows[-1].append((text, self.cell[1], self.cell[2]))
            self.cell = None

    def handle_data(self, data):
        if self.cell:
            self.cell[0].append(data)


def _brackets(line):
    """'[a; (b); c (x)]' -> ['a', 'b', 'c (x)']"""
    parts = [p.strip() for p in line.strip()[1:-1].split(";")]
    return [p[1:-1].strip() if p.startswith("(") and p.endswith(")") else p for p in parts if p]


def parse_cell(text):
    """Lesson cell -> dict. Lines: time, course, [groups], [(teachers)], [type], note."""
    lines = [re.sub(r"\s+", " ", l).strip() for l in text.split("\n")]
    lines = [l for l in lines if l]
    m = TIME_RE.match(lines[0]) if lines else None
    if not m:
        return None
    out = {"start": m[1], "end": m[2], "course": lines[1] if len(lines) > 1 else "",
           "groups": [], "teachers": [], "type": ""}
    for l in lines[2:]:
        if not (l.startswith("[") and l.endswith("]")):
            continue
        if l.startswith("[("):
            out["teachers"] = _brackets(l)
        elif not out["groups"]:
            out["groups"] = _brackets(l)
        else:
            out["type"] = ", ".join(_brackets(l))
    return out


def week_mondays(page_html):
    """'Semanas: 12/10/2026 - 14/12/2026' -> every Monday in that range (inclusive)."""
    found = re.search(r"Semanas:\s*([\d/]+)(?:\s*-\s*([\d/]+))?", page_html)
    first = datetime.strptime(found[1], "%d/%m/%Y").date()
    last = datetime.strptime(found[2], "%d/%m/%Y").date() if found[2] else first
    return [first + timedelta(weeks=i) for i in range((last - first).days // 7 + 1)]


def parse_page(page_html, source_url=""):
    """Weekly grid -> lessons. Handles rowspan, and days widened to 4+ columns by overlaps."""
    p = _Cells()
    p.feed(page_html)
    header = next((i for i, r in enumerate(p.rows) if r and r[0][0].strip() == "Horas"), None)
    if header is None:
        raise ValueError("timetable header row 'Horas' not found")
    day_of_col = [None]  # column 0 = time labels
    for day, (_, _, colspan) in enumerate(p.rows[header][1:]):
        day_of_col += [day] * colspan
    mondays = week_mondays(page_html)
    taken, lessons = set(), []
    for r, row in enumerate(p.rows[header + 1:]):
        col, pending = 0, None
        for text, rowspan, colspan in row:
            while (r, col) in taken:
                col += 1
            for dr in range(rowspan):
                for dc in range(colspan):
                    taken.add((r + dr, col + dc))
            if col > 0:
                if pending:  # the cell right after a lesson holds its rooms
                    rooms = _brackets(text) if text.strip().startswith("[") else [text.strip()]
                    day = day_of_col[pending.pop("_col")]
                    for monday in mondays:
                        lessons.append(pending | {"rooms": rooms, "source_url": source_url,
                                                  "date": (monday + timedelta(days=day)).isoformat()})
                    pending = None
                else:
                    pending = parse_cell(text)
                    if pending:
                        pending["_col"] = col
            col += colspan
    return lessons


def all_lessons_unique(all_lessons):
    """Every lesson once (for the filter page); a lesson in several rooms stays one entry."""
    seen = {}
    for l in all_lessons:
        k = (l["date"], l["start"], l["end"], l["course"], tuple(l["rooms"]))
        if k in seen:
            seen[k]["groups"] = sorted(set(seen[k]["groups"]) | set(l["groups"]))
        else:
            seen[k] = {k2: v for k2, v in l.items() if k2 != "source_url"}
    return sorted(seen.values(), key=lambda l: (l["date"], l["start"], l["course"]))


def monday_of(d):
    """Monday of d's week; the schedule always starts there, not at today."""
    return d - timedelta(days=d.weekday())
