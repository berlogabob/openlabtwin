# Milestone 2: Public Site + TV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Code files are delegated to local pi (`ornith-1.5:9b`) as "create file = block"; the controller runs every shell step and checks each file byte for byte against this plan.

**Goal:** Replace the old site with a Jaspr static site under `apps/site`. It adds multi-select filters on every field, a lab TV page (rooms side by side, reloads itself), bookings and events as coloured layers, and `lab.ics` from the export. It is built and deployed to GitHub Pages by the sync workflow.

**Architecture:**
- **Static build:** Jaspr in static mode, two routes: `/` (schedule) and `/tv`. Both are `@client` components that fetch `data/all.json` in the browser, so new data needs no rebuild logic of its own.
- **Logic:** pure Dart in `lib/schedule.dart` and `lib/calendar.dart`, tested with `dart test`. The calendar maths is a line-for-line port of the old `calendar.js` and its tests.
- **Export:** `export.py` now writes into `apps/site/web/` (`data/all.json` and `calendar/lab.ics`). The sync workflow scrapes, exports, commits the data, then builds and deploys Pages.

**Tech Stack:** Jaspr 0.23.4 (static mode), jaspr_router, `http`, `universal_web`; Python stdlib + python-dateutil; GitHub Actions + Pages.

**Spec:** `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md` (section "Public site and TV").

## Global Constraints

- Ponytail: no new dependency beyond what Jaspr already pulls in (`http` and `universal_web` are its own dependencies).
- `build_web_compilers: ^4.8.5`. 4.8.6+ needs analyzer 13, and `jaspr_builder` 0.23.4 pins analyzer 12.
- Base path: `/` locally; the Pages build passes `--dart-define=BASE=/openlabtwin/`. Every in-page URL is relative (`data/all.json`, `tv/`, `style.css`) and resolves against `<base>`.
- URL keys stay compatible with the old site (`degree, programme, room, teacher, group, course, type, from, to, view, date`). Several values use repeated keys (`?teacher=A&teacher=B`). `room=` with an empty value means any room.
- Within one field, values are ORed; across fields, filters are ANDed. A value picked from the list matches exactly; typed text matches as a substring, ignoring case and Portuguese accents.
- Colours: timetable red `--accent`, bookings blue `--booking` (#1e5cb3 / #82b1ff), events green `--event` (#1eb350 / #80ffaa).
- Commits end with the two attribution lines used in milestone 1.

## Decisions (ponytail)

- **Kept:** list, day, week and month views, URL filters, 5 favourites, the collapsible filter block, smart lists, and `lab.ics`.
- **Dropped:** the no-JavaScript Today / This week / All lab pages. The TV page and the main page's Today / This week presets cover them. Add them back as server-rendered routes if a no-JS screen appears.
- **Deferred:** a Dart `packages/core` package. The logic lives in `apps/site/lib` until the Flutter office (milestone 3) needs to share it; then it moves.
- **TV rooms** come from the URL (`tv/?room=A&room=B`, default the Tech Lab), so no `places.json` is needed.

---

### Task 1: Export writes into the site, plus lab.ics

**Files:**
- Create: `scripts/ics.py` (generated from the old `fetch.py`)
- Modify: `scripts/export.py`
- Modify: `tests/test_export.py`
- Move: `apps/site/data/all.json` → `apps/site/web/data/all.json`

- [ ] **Step 1 (controller, shell): generate `scripts/ics.py` and move the data file**

```bash
uv run python - <<'EOF'
import ast, pathlib
src = (pathlib.Path.home() / "Documents/GitHub/IADE_Schedule/scripts/fetch.py").read_text(encoding="utf-8")
keep = ["CAL_TITLE", "VTIMEZONE", "key", "ics_text", "fold", "render_ics"]
found = {}
for node in ast.parse(src).body:
    name = getattr(node, "name", None) or (node.targets[0].id if isinstance(node, ast.Assign) else None)
    if name in keep:
        found[name] = ast.get_source_segment(src, node)
assert not set(keep) - set(found), set(keep) - set(found)
header = '"""lab.ics rendering, ported verbatim from iade-lab-schedule/scripts/fetch.py."""\nimport hashlib\n'
pathlib.Path("scripts/ics.py").write_text(header + "\n\n" + "\n\n\n".join(found[k] for k in keep) + "\n", encoding="utf-8")
EOF
mkdir -p apps/site/web/data && git mv apps/site/data/all.json apps/site/web/data/all.json
```

- [ ] **Step 2 (pi): edit `scripts/export.py`**

a) Replace the line `from db import connect, select` with:

```python
from db import connect, select
from ics import render_ics
```

b) Replace the line `WINDOW_DAYS = 180  # how far ahead repeating activities are expanded` with:

```python
WINDOW_DAYS = 180  # how far ahead repeating activities are expanded
ICS_STAMP = "20260921T000000Z"  # ponytail: fixed DTSTAMP keeps lab.ics unchanged unless events change; UIDs + times carry updates
```

c) Insert this function directly above `def main():`:

```python
def lab_items(records, lab_rooms):
    """One entry per lab room a record uses, in the shape render_ics() expects."""
    return [r | {"room": room, "source_url": ""} for r in records for room in r["rooms"] if room in lab_rooms]


```

d) Replace the line `    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "apps/site/data"` with:

```python
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "apps/site/web"
```

e) Replace these three lines:

```python
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "all.json").write_text(render(records), encoding="utf-8")
    print(f"Exported {len(records)} records "
          f"({sum(r['layer'] == 'lesson' for r in records)} lessons) to {out_dir / 'all.json'}")
```

with:

```python
    lab_rooms = {p["iade_name"] or p["name"] for p in places if p["public"]}
    (out_dir / "data").mkdir(parents=True, exist_ok=True)
    (out_dir / "calendar").mkdir(parents=True, exist_ok=True)
    (out_dir / "data/all.json").write_text(render(records), encoding="utf-8")
    (out_dir / "calendar/lab.ics").write_text(render_ics(lab_items(records, lab_rooms), ICS_STAMP), encoding="utf-8",
                                              newline="")
    print(f"Exported {len(records)} records "
          f"({sum(r['layer'] == 'lesson' for r in records)} lessons) to {out_dir / 'data/all.json'} and lab.ics")
```

- [ ] **Step 3 (pi): add to `tests/test_export.py`, directly above its last line `print("ok")`:**

```python
# lab.ics: only the lab room's occurrences, CRLF, with the public fields
ics = export.render_ics(export.lab_items(out, {"Lab. e Estudo de Jogos - Tech Lab (Oriente)"}), export.ICS_STAMP)
assert ics.count("BEGIN:VEVENT") == 2 and "SUMMARY:Club meeting" in ics, ics
assert "Game Frameworks" not in ics and "Open day" not in ics, "only lab-room records"
assert ics.startswith("BEGIN:VCALENDAR\r\n") and "\n" not in ics.replace("\r\n", "")
```

- [ ] **Step 4 (controller): verify**

Run: `for t in tests/test_*.py; do uv run python "$t"; done && set -a && . ./.env && set +a && uv run python scripts/export.py && git diff --quiet apps/site/web/data/all.json && echo same`
Expected: three `ok` lines, `Exported 10621 records … and lab.ics`, and `same`. `apps/site/web/calendar/lab.ics` now exists.

- [ ] **Commit**

```bash
git add scripts tests apps/site/web
git commit -m "Export writes the site's data/all.json and calendar/lab.ics

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 2: Site scaffold and schedule logic

**Files:**
- Create (controller, shell): `apps/site` via `jaspr create`, then delete the template demo files
- Create (pi): `apps/site/pubspec.yaml`, `apps/site/lib/schedule.dart`, `apps/site/lib/calendar.dart`, `apps/site/test/logic_test.dart`

- [ ] **Step 1 (controller, shell)**

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"; dart pub global activate jaspr_cli 0.23.4
cd apps && jaspr create -m static -r multi-page -f none --no-pub-get site_tmp && cp -Rn site_tmp/. site/ && rm -rf site_tmp && cd site
rm -rf lib/components lib/constants lib/pages/about.dart lib/pages/home.dart web/images README.md lib/main.client.options.dart lib/main.server.options.dart
mkdir -p test
```

- [ ] **Step 2 (pi): create `apps/site/pubspec.yaml`:**

```yaml
name: site
description: OpenLabTwin public schedule and lab TV
publish_to: none
version: 0.0.1

environment:
  sdk: ^3.10.0

dependencies:
  http: ^1.6.0
  jaspr: ^0.23.4
  jaspr_router: ^0.9.0
  universal_web: ^1.1.1

dev_dependencies:
  build_runner: ^2.10.0
  build_web_compilers: ^4.8.5 # 4.8.6+ needs analyzer 13; jaspr_builder 0.23.4 still pins analyzer 12
  jaspr_builder: ^0.23.4
  lints: ^5.0.0
  test: ^1.25.0

jaspr:
  mode: static
```

- [ ] **Step 3 (pi): create `apps/site/lib/schedule.dart`:**

```dart
// Lessons, filters and matching. Pure Dart (no DOM), so `dart test` covers it.
import 'dart:convert';

const defaultRoom = 'Lab. e Estudo de Jogos - Tech Lab (Oriente)';

class Lesson {
  const Lesson({
    required this.date,
    required this.start,
    required this.end,
    required this.course,
    this.groups = const [],
    this.teachers = const [],
    this.type = '',
    this.rooms = const [],
    this.programmes = const [],
    this.degrees = const [],
    this.layer = 'lesson',
    this.note = '',
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        date: j['date'] as String,
        start: j['start'] as String,
        end: j['end'] as String,
        course: j['course'] as String,
        groups: _strings(j['groups']),
        teachers: _strings(j['teachers']),
        type: j['type'] as String? ?? '',
        rooms: _strings(j['rooms']),
        programmes: _strings(j['programmes']),
        degrees: _strings(j['degrees']),
        layer: j['layer'] as String? ?? 'lesson',
        note: j['note'] as String? ?? '',
      );

  final String date, start, end, course, type, layer, note;
  final List<String> groups, teachers, rooms, programmes, degrees;
}

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) x as String];

List<Lesson> parseLessons(String json) =>
    [for (final j in jsonDecode(json) as List) Lesson.fromJson(j as Map<String, dynamic>)];

/// Filter fields in display order: URL key -> values of a lesson.
final fields = <String, List<String> Function(Lesson)>{
  'degree': (l) => l.degrees,
  'programme': (l) => l.programmes,
  'room': (l) => l.rooms,
  'teacher': (l) => l.teachers,
  'group': (l) => l.groups,
  'course': (l) => [l.course],
  'type': (l) => [l.type],
};

const labels = {
  'degree': 'Degree',
  'programme': 'Programme',
  'room': 'Room / lab',
  'teacher': 'Professor / staff',
  'group': 'Group',
  'course': 'Course',
  'type': 'Type',
};

/// Every value each field has anywhere, to tell a picked value (exact match) from typed text (substring).
Map<String, Set<String>> knownValues(List<Lesson> lessons) => {
      for (final e in fields.entries) e.key: {for (final l in lessons) ...e.value(l).where((v) => v.isNotEmpty)}
    };

// ponytail: Latin accents only (enough for Portuguese); Dart core has no NFD, add a normalizer if other scripts appear
const _fold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i',
  'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// "computacao" finds "Computação".
String plain(String s) => s.toLowerCase().split('').map((c) => _fold[c] ?? c).join();

/// Values within one field are ORed. A known value matches exactly; typed text matches anywhere, ignoring accents.
bool matchesField(List<String> have, List<String> wanted, Set<String> known) =>
    wanted.isEmpty ||
    wanted.any((w) => known.contains(w) ? have.contains(w) : have.any((v) => plain(v).contains(plain(w))));

class Filters {
  Filters({Map<String, List<String>>? values, this.from = '', this.to = '', this.view = 'list', this.date = ''})
      : values = values ?? {};

  /// field -> chosen values. A present-but-empty 'room' means "any room" (absent means the default lab).
  final Map<String, List<String>> values;
  String from, to, view, date;

  factory Filters.parse(String query) {
    final all = Uri(query: query.startsWith('?') ? query.substring(1) : query).queryParametersAll;
    String one(String k) => (all[k] ?? const ['']).first;
    final view = one('view');
    return Filters(
      values: {
        for (final k in fields.keys)
          if (all.containsKey(k)) k: [for (final v in all[k]!) if (v.isNotEmpty) v]
      },
      from: one('from'),
      to: one('to'),
      view: const ['day', 'week', 'month'].contains(view) ? view : 'list',
      date: RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(one('date')) ? one('date') : '',
    );
  }

  /// Repeated keys for several values: ?teacher=A&teacher=B.
  String toQuery() {
    final parts = <String>[];
    void add(String k, String v) => parts.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
    for (final k in fields.keys) {
      final vs = values[k];
      if (vs == null) continue;
      if (vs.isEmpty && k == 'room') add(k, '');
      for (final v in vs) {
        add(k, v);
      }
    }
    if (from.isNotEmpty) add('from', from);
    if (to.isNotEmpty) add('to', to);
    if (view != 'list') {
      add('view', view);
      add('date', date);
    }
    return parts.join('&');
  }

  Filters copy() => Filters(
      values: {for (final e in values.entries) e.key: [...e.value]}, from: from, to: to, view: view, date: date);
}

class Result {
  const Result(this.hits, this.options);
  final List<Lesson> hits;

  /// Smart lists: per field, only the values that still have lessons under all the *other* filters.
  final Map<String, List<String>> options;
}

Result run(List<Lesson> lessons, Map<String, List<String>> wanted, Map<String, Set<String>> known, String from,
    String to) {
  final names = fields.keys.toList();
  final hits = <Lesson>[];
  final opts = {for (final n in names) n: <String>{}};
  for (final l in lessons) {
    final pass = [for (final n in names) matchesField(fields[n]!(l), wanted[n] ?? const [], known[n]!)];
    final inDates = (from.isEmpty || l.date.compareTo(from) >= 0) && (to.isEmpty || l.date.compareTo(to) <= 0);
    final fails = pass.where((p) => !p).length + (inDates ? 0 : 1);
    if (fails == 0) hits.add(l);
    if (fails > 1) continue;
    for (var j = 0; j < names.length; j++) {
      if (fails == 0 || !pass[j]) opts[names[j]]!.addAll(fields[names[j]]!(l).where((v) => v.isNotEmpty));
    }
  }
  return Result(hits, {
    for (final n in names) n: opts[n]!.toList()..sort((a, b) => plain(a).compareTo(plain(b)))
  });
}
```

- [ ] **Step 4 (pi): create `apps/site/lib/calendar.dart`:**

```dart
// Date maths and overlap layout for the calendar views, ported from iade-lab-schedule/docs/calendar.js.
// Dates are ISO strings; maths runs on UTC noon, so no DST edge can trip it.
import 'schedule.dart';

const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
  'December',
];

DateTime _d(String iso) => DateTime.parse('${iso}T12:00:00Z');
String iso(DateTime d) => d.toIso8601String().substring(0, 10);
DateTime _monday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
String weekday(String isoDate) => days[_d(isoDate).weekday % 7];

String dayName(String isoDate) {
  final a = _d(isoDate);
  return '${days[a.weekday % 7]}, ${a.day} ${months[a.month - 1]} ${a.year}';
}

(String, String) periodRange(String view, String anchor) {
  final a = _d(anchor);
  if (view == 'day') return (anchor, anchor);
  if (view == 'week') {
    final first = _monday(a);
    return (iso(first), iso(first.add(const Duration(days: 6))));
  }
  return (iso(DateTime.utc(a.year, a.month, 1, 12)), iso(DateTime.utc(a.year, a.month + 1, 0, 12)));
}

String shift(String view, String anchor, int step) {
  final a = _d(anchor);
  if (view == 'day') return iso(a.add(Duration(days: step)));
  if (view == 'week') return iso(a.add(Duration(days: 7 * step)));
  return iso(DateTime.utc(a.year, a.month + step, 1, 12));
}

String periodLabel(String view, String anchor) {
  final a = _d(anchor);
  if (view == 'day') return dayName(anchor);
  if (view == 'month') return '${months[a.month - 1]} ${a.year}';
  final (f, t) = periodRange('week', anchor);
  final from = _d(f), to = _d(t);
  final left = from.month == to.month ? '${from.day}' : '${from.day} ${months[from.month - 1]}';
  return '$left–${to.day} ${months[to.month - 1]} ${to.year}';
}

/// This week's Sunday, for the "This week" preset (Monday..Sunday; today counts).
String sundayOf(String isoDate) {
  final a = _d(isoDate);
  return iso(a.add(Duration(days: 7 - a.weekday)));
}

/// Every date from..to inclusive.
List<String> datesOf(String from, String to) =>
    [for (var d = _d(from); iso(d).compareTo(to) <= 0; d = d.add(const Duration(days: 1))) iso(d)];

/// Every date of the month grid: whole weeks, Monday first, including neighbouring days.
List<String> monthCells(String anchor) {
  final (from, to) = periodRange('month', anchor);
  final cells = <String>[];
  for (var day = _monday(_d(from)); iso(day).compareTo(to) <= 0 || cells.length % 7 != 0;
      day = day.add(const Duration(days: 1))) {
    cells.add(iso(day));
  }
  return cells;
}

int minutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

typedef Placed = ({Lesson lesson, double top, double height, double left, double width});

/// One day's lessons placed in percent of the day column: overlapping ones sit side by side.
List<Placed> layout(List<Lesson> dayLessons, int dayStart, int dayEnd) {
  final span = dayEnd - dayStart;
  final sorted = [...dayLessons]
    ..sort((a, b) {
      final s = minutes(a.start) - minutes(b.start);
      return s != 0 ? s : minutes(a.end) - minutes(b.end);
    });
  final out = <Placed>[];
  var cluster = <Lesson>[];
  var clusterEnd = -1;
  void place() {
    final columns = <List<Lesson>>[];
    final col = <Lesson, int>{};
    for (final l in cluster) {
      var c = columns.indexWhere((column) => minutes(column.last.end) <= minutes(l.start));
      if (c < 0) {
        columns.add([]);
        c = columns.length - 1;
      }
      columns[c].add(l);
      col[l] = c;
    }
    for (final l in cluster) {
      out.add((
        lesson: l,
        top: (minutes(l.start) - dayStart) / span * 100,
        height: (minutes(l.end) - minutes(l.start)).clamp(20, 1 << 30) / span * 100,
        left: col[l]! / columns.length * 100,
        width: 100 / columns.length,
      ));
    }
    cluster = [];
  }

  for (final l in sorted) {
    if (cluster.isNotEmpty && minutes(l.start) >= clusterEnd) place();
    cluster.add(l);
    if (minutes(l.end) > clusterEnd) clusterEnd = minutes(l.end);
  }
  if (cluster.isNotEmpty) place();
  return out;
}
```

- [ ] **Step 5 (pi): create `apps/site/test/logic_test.dart`:**

```dart
// Run: dart test (from apps/site). Calendar asserts are ported 1:1 from iade-lab-schedule/tests/test_calendar.mjs.
import 'package:site/calendar.dart';
import 'package:site/schedule.dart';
import 'package:test/test.dart';

Lesson at(String start, String end, String course) => Lesson(date: '2026-09-17', start: start, end: end, course: course);

void main() {
  test('periods', () {
    expect(periodRange('day', '2026-09-17'), ('2026-09-17', '2026-09-17'));
    expect(periodRange('week', '2026-09-17'), ('2026-09-14', '2026-09-20')); // Thursday -> Mon..Sun
    expect(periodRange('week', '2026-09-14'), ('2026-09-14', '2026-09-20'));
    expect(periodRange('week', '2026-09-20'), ('2026-09-14', '2026-09-20'));
    expect(periodRange('month', '2026-02-10'), ('2026-02-01', '2026-02-28'));
    expect(sundayOf('2026-09-17'), '2026-09-20');
    expect(sundayOf('2026-09-20'), '2026-09-20');
    expect(datesOf('2026-09-30', '2026-10-02'), ['2026-09-30', '2026-10-01', '2026-10-02']);
  });

  test('stepping', () {
    expect(shift('day', '2026-12-31', 1), '2027-01-01');
    expect(shift('week', '2026-09-17', -1), '2026-09-10');
    expect(shift('month', '2026-01-31', 1), '2026-02-01'); // no 31 February
    expect(shift('month', '2026-01-15', -1), '2025-12-01');
  });

  test('labels', () {
    expect(periodLabel('day', '2026-09-17'), 'Thursday, 17 September 2026');
    expect(periodLabel('week', '2026-09-17'), '14–20 September 2026');
    expect(periodLabel('week', '2026-09-30'), '28 September–4 October 2026');
    expect(periodLabel('month', '2026-09-17'), 'September 2026');
  });

  test('month grid', () {
    final cells = monthCells('2026-09-17');
    expect(cells.length % 7, 0);
    expect(cells.first, '2026-08-31');
    expect(cells.last, '2026-10-04');
    expect(cells, contains('2026-09-30'));
  });

  test('layout', () {
    final one = layout([at('08:00', '20:00', 'A')], 480, 1200).single;
    expect([one.top, one.height, one.left, one.width], [0, 100, 0, 100]);
    List<List<Object>> cols(List<Placed> p) => [for (final x in p) [x.lesson.course, x.left, x.width]];
    expect(cols(layout([at('09:00', '11:00', 'A'), at('10:00', '12:00', 'B')], 480, 1200)), [
      ['A', 0, 50],
      ['B', 50, 50]
    ]);
    expect(cols(layout([at('09:00', '10:00', 'A'), at('10:00', '11:00', 'B')], 480, 1200)), [
      ['A', 0, 100],
      ['B', 0, 100]
    ]);
    expect(cols(layout([at('09:00', '13:00', 'A'), at('10:00', '11:00', 'B'), at('11:00', '12:00', 'C')], 480, 1200)), [
      ['A', 0, 50],
      ['B', 50, 50],
      ['C', 50, 50]
    ]);
    final half = layout([at('09:00', '11:00', 'A')], 480, 1200).single;
    expect(half.top, (540 - 480) / 720 * 100);
    expect(half.height, 120 / 720 * 100);
  });

  test('query keeps several values per field and the any-room marker', () {
    final f = Filters.parse('?teacher=Jos%C3%A9+Gra%C3%A7a&teacher=Cl%C3%A1udia&room=&view=week&date=2026-09-17');
    expect(f.values['teacher'], ['José Graça', 'Cláudia']);
    expect(f.values['room'], isEmpty);
    expect(f.view, 'week');
    expect(Filters.parse(f.toQuery()).values, f.values);
    expect(f.toQuery(), contains('room=&'));
    expect(Filters.parse('view=bogus&date=nope').view, 'list');
    expect(Filters.parse('view=bogus&date=nope').date, '');
  });

  test('matching: OR within a field, AND across fields, exact vs typed, accents', () {
    final lessons = [
      Lesson(date: '2026-09-21', start: '09:00', end: '10:00', course: 'Computação', teachers: ['José Graça'], rooms: ['Lab A']),
      Lesson(date: '2026-09-21', start: '10:00', end: '11:00', course: 'Design', teachers: ['Cláudia'], rooms: ['Lab B']),
      Lesson(date: '2026-09-22', start: '10:00', end: '11:00', course: 'Robotics', teachers: ['Rui'], rooms: ['Lab A']),
    ];
    final known = knownValues(lessons);
    List<String> courses(Map<String, List<String>> w, [String from = '', String to = '']) =>
        [for (final l in run(lessons, w, known, from, to).hits) l.course];
    expect(courses({'teacher': ['José Graça', 'Cláudia']}), ['Computação', 'Design']);
    expect(courses({'teacher': ['José Graça', 'Cláudia'], 'room': ['Lab A']}), ['Computação']);
    expect(courses({'course': ['computacao']}), ['Computação'], reason: 'typed text ignores case and accents');
    expect(courses({'room': ['lab']}), ['Computação', 'Design', 'Robotics'], reason: 'typed text is a substring');
    expect(courses({}, '2026-09-22', '2026-09-22'), ['Robotics']);
    final opts = run(lessons, {'room': ['Lab A']}, known, '', '').options;
    expect(opts['teacher'], ['José Graça', 'Rui'], reason: 'smart list: only teachers with lessons in Lab A');
    expect(opts['room'], ['Lab A', 'Lab B'], reason: "a field's own filter doesn't narrow its list");
  });
}
```

- [ ] **Step 6 (controller): verify**

Run: `cd apps/site && dart pub get && dart test`
Expected: `+7: All tests passed!`

- [ ] **Commit**

```bash
git add apps/site
git commit -m "Site: Jaspr scaffold, schedule filters and calendar maths with tests

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 3: Pages, styles and build

**Files (pi, create or replace whole file):** `apps/site/lib/app.dart`, `apps/site/lib/main.server.dart`, `apps/site/lib/main.client.dart`, `apps/site/lib/pages/schedule_page.dart`, `apps/site/lib/pages/tv_page.dart`, `apps/site/web/style.css`

- [ ] **Step 1 (pi): `apps/site/lib/app.dart`**

```dart
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/schedule_page.dart';
import 'pages/tv_page.dart';

// Built only on the server during the static build; each page is a @client component mounted in the browser.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) => Router(routes: [
        Route(path: '/', title: 'IADE Schedule', builder: (context, state) => const SchedulePage()),
        Route(path: '/tv', title: 'Lab TV · IADE Schedule', builder: (context, state) => const TvPage()),
      ]);
}
```

- [ ] **Step 2 (pi): `apps/site/lib/main.server.dart`**

```dart
/// Server entrypoint: runs only during the static build (pre-rendering).
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

/// '/' locally; the GitHub Pages build passes --dart-define=BASE=/openlabtwin/.
const base = String.fromEnvironment('BASE', defaultValue: '/');

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);
  runApp(Document(
    title: 'IADE Schedule',
    lang: 'en',
    base: base,
    head: [link(rel: 'stylesheet', href: 'style.css')],
    body: const App(),
  ));
}
```

- [ ] **Step 3 (pi): `apps/site/lib/main.client.dart`**

```dart
/// Client entrypoint: mounts every @client component (the pages) in the browser.
library;

import 'package:jaspr/client.dart';

import 'main.client.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);
  runApp(const ClientApp());
}
```

- [ ] **Step 4 (pi): `apps/site/lib/pages/schedule_page.dart`**

```dart
// Main page: loads data/all.json in the browser, filters it, keeps filters and the view in the URL.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../calendar.dart';
import '../schedule.dart';

const maxList = 300; // ponytail: render cap, add paging if people need to scroll past it
const maxGrid = 150; // ponytail: a whole campus week is unreadable as a grid
const maxFavs = 5;

String today() => iso(DateTime.now()); // ponytail: the viewer's local date; the lab and its TV are in Lisbon

// Per-browser conveniences; the page works the same if storage is blocked.
String? load(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void save(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

@client
class SchedulePage extends StatefulComponent {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => SchedulePageState();
}

class SchedulePageState extends State<SchedulePage> {
  List<Lesson>? lessons;
  String? error;
  Map<String, Set<String>> known = {};
  Filters f = Filters();
  final drafts = <String, String>{}; // text typed but not yet picked, per field
  bool open = true;
  List<Map<String, dynamic>> favs = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('data/all.json'), headers: {'Cache-Control': 'no-cache'});
      final all = parseLessons(utf8.decode(r.bodyBytes));
      final q = web.window.location.search;
      setState(() {
        lessons = all;
        known = knownValues(all);
        f = q.isEmpty ? Filters(values: {'room': [defaultRoom]}, from: today()) : Filters.parse(q);
        if (f.date.isEmpty) f.date = today();
        open = load('filtersOpen') != 'false';
        favs = [for (final x in jsonDecode(load('favs') ?? '[]') as List) x as Map<String, dynamic>];
      });
    } catch (_) {
      setState(() => error = 'Could not load the timetable data.');
    }
  }

  void _update(void Function() change) {
    setState(change);
    web.window.history.replaceState(null, '', '?${f.toQuery()}');
  }

  Map<String, List<String>> get _wanted => {
        for (final k in fields.keys)
          k: [...?f.values[k], if ((drafts[k] ?? '').isNotEmpty) drafts[k]!]
      };

  void _pick(String field, String value) => _update(() {
        final vs = f.values.putIfAbsent(field, () => []);
        if (value.isNotEmpty && !vs.contains(value)) vs.add(value);
        drafts.remove(field);
      });

  (String, String) _range(String name) => switch (name) {
        'today' => (today(), today()),
        'week' => (today(), sundayOf(today())),
        _ => ('', ''),
      };

  String _describe(Filters g) => [
        for (final k in fields.keys) ...?g.values[k],
        if (g.from.isNotEmpty) 'from ${g.from}',
        if (g.to.isNotEmpty) 'to ${g.to}',
      ].join(' · ');

  void _saveFav() {
    final g = f.copy()..date = '';
    if (g.from == today()) g.from = ''; // "from today" should stay today, not freeze the date
    final query = g.toQuery();
    if (favs.length >= maxFavs || favs.any((x) => x['query'] == query)) return;
    final name = web.window.prompt('Name this favourite', _describe(g).isEmpty ? 'Everything' : _describe(g));
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    setState(() => favs.add({'name': trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed, 'query': query}));
    save('favs', jsonEncode(favs));
  }

  void _openFav(String query) => _update(() {
        f = Filters.parse(query);
        if (f.date.isEmpty) f.date = today();
        if (f.from.isEmpty && !query.contains('from=') && f.view == 'list' && f.to.isEmpty) f.from = today();
        drafts.clear();
      });

  @override
  Component build(BuildContext context) {
    final all = lessons;
    return div([
      header([
        h1([a(href: './', [.text('IADE Schedule')])]),
        if (all != null) _nav(),
      ]),
      if (all != null) _filters(all),
      main_([
        if (error != null)
          p(classes: 'empty', [.text(error!)])
        else if (all == null)
          p(classes: 'empty', [.text('Loading…')])
        else
          ..._results(all),
      ]),
      footer([
        p([
          .text('Lab: '),
          a(href: 'tv/', [.text('TV screen')]),
          .text(' · '),
          a(href: 'calendar/lab.ics', [.text('calendar (.ics)')]),
          .text(' · '),
          a(href: 'https://horariosturmas.europeia.pt/UE_IADE/HorariosTurmas/', [.text('official IADE timetable')]),
        ]),
        p([.text('Unofficial timetable view. Always verify critical scheduling information with the official IADE timetable.')]),
      ]),
    ]);
  }

  Component _nav() {
    Component btn(String label, bool on, void Function() tap) =>
        button(type: ButtonType.button, classes: on ? 'on' : null, onClick: tap, [.text(label)]);
    return nav([
      span(id: 'views', [
        for (final v in const ['list', 'day', 'week', 'month'])
          btn(v[0].toUpperCase() + v.substring(1), f.view == v, () => _update(() {
                if (f.view == 'list' && v != 'list' && f.from.isNotEmpty) f.date = f.from;
                f.view = v;
              })),
      ]),
      if (f.view == 'list')
        span(id: 'ranges', [
          for (final (name, label) in const [('today', 'Today'), ('week', 'This week'), ('all', 'All dates')])
            btn(label, (f.from, f.to) == _range(name), () => _update(() {
                  final r = _range(name);
                  f.from = r.$1;
                  f.to = r.$2;
                })),
        ])
      else
        span(id: 'period', [
          btn('‹', false, () => _update(() => f.date = shift(f.view, f.date, -1))),
          btn('Today', false, () => _update(() => f.date = today())),
          btn('›', false, () => _update(() => f.date = shift(f.view, f.date, 1))),
          span(id: 'period-label', [.text(periodLabel(f.view, f.date))]),
        ]),
    ]);
  }

  Component _filters(List<Lesson> all) {
    final (from, to) = f.view == 'list' ? (f.from, f.to) : periodRange(f.view, f.date);
    final options = run(all, _wanted, known, from, to).options;
    final desc = _describe(f);
    return details(
      id: 'filters-box',
      open: open,
      events: {
        'toggle': (e) {
          open = (e.target as web.HTMLDetailsElement).open;
          save('filtersOpen', '$open');
        },
      },
      [
        summary([
          span(id: 'summary-text', [.text(desc.isEmpty ? 'Filters' : 'Filters: $desc')]),
          span(id: 'favs', [
            for (final fav in favs)
              span(classes: '?${fav['query']}' == '?${f.toQuery()}' ? 'fav on' : 'fav', [
                button(type: ButtonType.button, onClick: () => _openFav(fav['query'] as String), [.text(fav['name'] as String)]),
                button(
                  type: ButtonType.button,
                  classes: 'fav-x',
                  attributes: {'aria-label': 'Remove favourite ${fav['name']}'},
                  onClick: () {
                    setState(() => favs.remove(fav));
                    save('favs', jsonEncode(favs));
                  },
                  [.text('×')],
                ),
              ]),
            button(
              type: ButtonType.button,
              id: 'fav-save',
              disabled: favs.length >= maxFavs,
              attributes: {'title': favs.length >= maxFavs ? 'Up to $maxFavs favourites. Remove one first.' : 'Save the current filters'},
              onClick: _saveFav,
              [.text('☆ Save as favourite')],
            ),
          ]),
        ]),
        div(id: 'filters', [
          for (final k in fields.keys)
            label([
              .text(labels[k]!),
              span(classes: 'chips', [
                for (final v in f.values[k] ?? const <String>[])
                  span(classes: 'chip', [
                    .text(v),
                    button(
                      type: ButtonType.button,
                      attributes: {'aria-label': 'Remove $v'},
                      onClick: () => _update(() => f.values[k]!.remove(v)),
                      [.text('×')],
                    ),
                  ]),
                input<String>(
                  type: InputType.text,
                  value: drafts[k] ?? '',
                  attributes: {'list': '$k-list', 'placeholder': (f.values[k] ?? const []).isEmpty ? 'any' : 'or…', 'autocomplete': 'off'},
                  onInput: (v) => known[k]!.contains(v) ? _pick(k, v) : setState(() => drafts[k] = v),
                  onChange: (v) => _pick(k, v.trim()),
                ),
              ]),
              datalist(id: '$k-list', [for (final v in options[k]!) option(value: v, [])]),
            ]),
          if (f.view == 'list') ...[
            label(classes: 'date-field', [
              .text('From'),
              input<String>(type: InputType.date, value: f.from, onInput: (v) => _update(() => f.from = v)),
            ]),
            label(classes: 'date-field', [
              .text('To'),
              input<String>(type: InputType.date, value: f.to, onInput: (v) => _update(() => f.to = v)),
            ]),
          ],
        ]),
      ],
    );
  }

  List<Component> _results(List<Lesson> all) {
    final (from, to) = f.view == 'list' ? (f.from, f.to) : periodRange(f.view, f.date);
    final hits = run(all, _wanted, known, from, to).hits;
    return switch (f.view) {
      'list' => _list(hits),
      'month' => [_month(hits)],
      _ => _grid(hits, f.view == 'day' ? [f.date] : datesOf(from, to)),
    };
  }

  String _meta(Lesson l) => [l.rooms.join(', '), l.teachers.join(', ')].where((x) => x.isNotEmpty).join(' · ');

  String _details(Lesson l) => [l.course, l.rooms.join(', '), l.teachers.join(', '), l.groups.join(', '), l.type, l.note]
      .where((x) => x.isNotEmpty)
      .join(' · ');

  List<Component> _list(List<Lesson> hits) {
    if (hits.isEmpty) return [p(classes: 'empty', [.text('No lessons match these filters.')])];
    final sections = <Component>[];
    for (final date in {for (final l in hits.take(maxList)) l.date}) {
      sections.add(section([
        h2([.text(dayName(date))]),
        for (final l in hits.take(maxList).where((l) => l.date == date))
          article(classes: l.layer == 'lesson' ? null : l.layer, [
            p(classes: 'time', [.text('${l.start}–${l.end}')]),
            p(classes: 'course', [.text(l.course)]),
            for (final m in [l.rooms.join(', '), l.teachers.join(', '), l.groups.join(', '), l.type, l.note])
              if (m.isNotEmpty) p([.text(m)]),
          ]),
      ]));
    }
    if (hits.length > maxList) {
      sections.add(p(classes: 'empty', [.text('Showing the first $maxList of ${hits.length} lessons. Narrow the filters to see more.')]));
    }
    return sections;
  }

  // Day and week: hour rows down the side, one column per day, overlapping lessons side by side.
  List<Component> _grid(List<Lesson> hits, List<String> dates) {
    var first = 8 * 60, last = 20 * 60;
    for (final l in hits) {
      if (minutes(l.start) < first) first = minutes(l.start);
      if (minutes(l.end) > last) last = minutes(l.end);
    }
    first = first ~/ 60 * 60;
    last = (last + 59) ~/ 60 * 60;
    final now = today();
    return [
      if (hits.length > maxGrid) p(classes: 'empty', [.text('${hits.length} lessons in this period. Narrow the filters to read the grid.')]),
      div(classes: 'cal', attributes: {'style': '--days:${dates.length};--rows:${(last - first) ~/ 60}'}, [
        div(classes: 'cal-head', [
          div(classes: 'cal-corner', []),
          for (final d in dates)
            div(classes: d == now ? 'cal-day on' : 'cal-day', [.text('${weekday(d).substring(0, 3)} ${int.parse(d.substring(8))}')]),
        ]),
        div(classes: 'cal-body', [
          div(classes: 'cal-gutter', [
            for (var h = first ~/ 60; h < last ~/ 60; h++) div(classes: 'cal-hour', [.text('${'$h'.padLeft(2, '0')}:00')]),
          ]),
          for (final d in dates)
            div(classes: d == now ? 'cal-col on' : 'cal-col', [
              for (final x in layout(hits.where((l) => l.date == d).toList(), first, last))
                div(
                  classes: x.lesson.layer == 'lesson' ? 'ev' : 'ev ${x.lesson.layer}',
                  attributes: {
                    'style': 'top:${x.top}%;height:${x.height}%;left:${x.left}%;width:${x.width}%',
                    'title': _details(x.lesson),
                  },
                  [
                    span(classes: 'ev-time', [.text('${x.lesson.start}–${x.lesson.end}')]),
                    span(classes: 'ev-course', [.text(x.lesson.course)]),
                    span(classes: 'ev-meta', [.text(_meta(x.lesson))]),
                  ],
                ),
            ]),
        ]),
      ]),
    ];
  }

  Component _month(List<Lesson> hits) {
    final (from, to) = periodRange('month', f.date);
    final now = today();
    return div(classes: 'month', [
      for (final name in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) div(classes: 'month-head', [.text(name)]),
      for (final d in monthCells(f.date))
        div(
          classes: [
            'month-cell',
            if (d.compareTo(from) < 0 || d.compareTo(to) > 0) 'other',
            if (d == now) 'on',
          ].join(' '),
          events: {
            'click': (_) => _update(() {
                  f.view = 'day';
                  f.date = d;
                }),
          },
          [
            div(classes: 'month-num', [.text('${int.parse(d.substring(8))}')]),
            for (final l in hits.where((l) => l.date == d).take(3))
              div(
                classes: l.layer == 'lesson' ? 'month-ev' : 'month-ev ${l.layer}',
                attributes: {'title': _details(l)},
                [span(classes: 'ev-time', [.text(l.start)]), span(classes: 'ev-course', [.text(l.course)])],
              ),
            if (hits.where((l) => l.date == d).length > 3)
              div(classes: 'month-more', [.text('+${hits.where((l) => l.date == d).length - 3} more')]),
          ],
        ),
    ]);
  }
}
```

- [ ] **Step 5 (pi): `apps/site/lib/pages/tv_page.dart`**

```dart
// Lab TV: the lab rooms side by side for today, plus upcoming events. Rooms come from the URL
// (?room=A&room=B), default the Tech Lab. Reloads the data every 5 minutes; keeps the last good copy on failure.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../calendar.dart';
import '../schedule.dart';

@client
class TvPage extends StatefulComponent {
  const TvPage({super.key});

  @override
  State<TvPage> createState() => TvPageState();
}

class TvPageState extends State<TvPage> {
  List<Lesson> lessons = [];
  List<String> rooms = [defaultRoom];
  DateTime now = DateTime.now();
  DateTime? loaded;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final picked = Filters.parse(web.window.location.search).values['room'] ?? const [];
    if (picked.isNotEmpty) rooms = picked;
    // Timer starts after the first load: the clock ticks every minute, data reloads every 5.
    _load().whenComplete(() => timer = Timer.periodic(const Duration(minutes: 1), (t) {
          setState(() => now = DateTime.now());
          if (t.tick % 5 == 0) _load();
        }));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('data/all.json'), headers: {'Cache-Control': 'no-cache'});
      final all = parseLessons(utf8.decode(r.bodyBytes));
      setState(() {
        lessons = all;
        loaded = DateTime.now();
      });
    } catch (_) {} // keep showing the last good data; the footer shows how old it is
  }

  @override
  Component build(BuildContext context) {
    final day = iso(now);
    final clock = '${'${now.hour}'.padLeft(2, '0')}:${'${now.minute}'.padLeft(2, '0')}';
    final events = lessons
        .where((l) => l.layer == 'event' && l.date.compareTo(day) >= 0 && l.date.compareTo(shift('day', day, 14)) <= 0)
        .take(6)
        .toList();
    return div(classes: 'tv', [
      header([
        h1([.text(dayName(day))]),
        span(classes: 'tv-clock', [.text(clock)]),
      ]),
      div(classes: 'tv-rooms', attributes: {'style': '--cols:${rooms.length}'}, [
        for (final room in rooms)
          section([
            h2([.text(room)]),
            ..._today(room, day, clock),
          ]),
      ]),
      if (events.isNotEmpty)
        section(classes: 'tv-events', [
          h2([.text('Upcoming events')]),
          for (final e in events)
            p(classes: 'event', [.text('${dayName(e.date)} · ${e.start}–${e.end} · ${e.course}${e.rooms.isEmpty ? '' : ' · ${e.rooms.join(', ')}'}')]),
        ]),
      footer([
        p([.text(loaded == null ? 'Loading…' : 'Updated ${iso(loaded!)} ${'${loaded!.hour}'.padLeft(2, '0')}:${'${loaded!.minute}'.padLeft(2, '0')}')]),
      ]),
    ]);
  }

  List<Component> _today(String room, String day, String clock) {
    final items = lessons.where((l) => l.date == day && l.rooms.contains(room)).toList()
      ..sort((x, y) => x.start.compareTo(y.start));
    if (items.isEmpty) return [p(classes: 'empty', [.text('Free all day')])];
    return [
      for (final l in items)
        article(
          classes: [
            if (l.layer != 'lesson') l.layer,
            if (l.end.compareTo(clock) <= 0) 'past',
            if (l.start.compareTo(clock) <= 0 && l.end.compareTo(clock) > 0) 'now',
          ].join(' '),
          [
            p(classes: 'time', [.text('${l.start}–${l.end}')]),
            p(classes: 'course', [.text(l.course)]),
            if (l.teachers.isNotEmpty || l.groups.isNotEmpty)
              p([.text([l.teachers.join(', '), l.groups.join(', ')].where((x) => x.isNotEmpty).join(' · '))]),
          ],
        ),
    ];
  }
}
```

- [ ] **Step 6 (pi): `apps/site/web/style.css`**

```css
:root { color-scheme: light dark; --fg: #1a1a1a; --muted: #666; --bg: #fafaf7; --card: #fff; --line: #e3e1da; --accent: #b3261e; --booking: #1e5cb3; --event: #1eb350; }
@media (prefers-color-scheme: dark) { :root { --fg: #eee; --muted: #aaa; --bg: #161616; --card: #202020; --line: #333; --accent: #ff8a80; --booking: #82b1ff; --event: #80ffaa; } }
* { box-sizing: border-box; }
/* 16:9 screens: full width, type scales with viewport width, days laid out as columns */
html { font-size: clamp(16px, 1.15vw, 44px); }
body { margin: 0; padding: 1rem 1.5rem; font: 1rem/1.35 system-ui, sans-serif; color: var(--fg); background: var(--bg); }
header { display: flex; flex-wrap: wrap; align-items: baseline; gap: .25rem 1.5rem; padding-bottom: .6rem; border-bottom: 1px solid var(--line); }
h1 { margin: 0; font-size: 1.6rem; }
h1 a { color: inherit; text-decoration: none; }
.rooms, footer, article p { color: var(--muted); }
.rooms { margin: 0; }
nav { display: flex; flex-wrap: wrap; align-items: center; gap: .1rem .6rem; margin-left: auto; }
nav [data-range], nav [data-view] { font: inherit; font-size: .9rem; color: var(--accent); background: none; border: 1px solid transparent; border-radius: 999px; padding: .25rem .7rem; cursor: pointer; }
nav [data-range]:hover, nav [data-view]:hover { border-color: var(--line); }
nav [data-range].on, nav [data-view].on { color: var(--fg); background: var(--card); border-color: var(--line); }
nav a, nav strong { display: inline-block; padding: .3rem .1rem; }
a { color: var(--accent); }
main { display: grid; grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); gap: 0 1rem; }
h2 { margin: 1rem 0 .5rem; font-size: .85rem; letter-spacing: .06em; text-transform: uppercase; }
article { margin: 0 0 .6rem; padding: .6rem .8rem; background: var(--card); border: 1px solid var(--line); border-radius: 8px; }
article p { margin: .1rem 0; font-size: .9rem; overflow-wrap: anywhere; }
article .time { color: var(--fg); font-weight: 600; font-variant-numeric: tabular-nums; }
article .course { color: var(--fg); font-size: 1.05rem; }
/* single day (Today): spread its lessons across the width */
main > section:only-child { grid-column: 1 / -1; display: grid; grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); gap: 0 1rem; align-items: start; }
main > section:only-child h2 { grid-column: 1 / -1; }
.empty { grid-column: 1 / -1; margin: 2rem 0; color: var(--muted); }
footer { margin-top: 2rem; font-size: .75rem; }
footer p { margin: .2rem 0; }
/* compact cards so a full day fits one screen height: room is already in the header, meta on one line */
article .room { display: none; }
article p:not(.time, .course, .room) { display: inline; }
article p:not(.time, .course, .room) + p:not(.room)::before { content: " · "; }
/* filter page */
#filters { display: flex; flex-wrap: wrap; gap: .5rem 1rem; padding: 0 0 .6rem; }
#filters label { display: flex; flex-direction: column; font-size: .75rem; color: var(--muted); }
#filters input, #filters select { min-width: 12rem; max-width: 20rem; font: inherit; font-size: .9rem; padding: .25rem .4rem; color: var(--fg); background: var(--card); border: 1px solid var(--line); border-radius: 6px; }
#filters input[type=date] { min-width: 0; }
#filters-box { border-bottom: 1px solid var(--line); }
#filters-box summary::-webkit-details-marker { display: none; }
#filters-box summary::before { content: "\25b8"; color: var(--muted); }
#filters-box[open] summary::before { content: "\25be"; }
#filters-box summary { list-style: none; display: flex; flex-wrap: wrap; align-items: center; gap: .3rem .8rem; padding: .5rem 0; font-size: .85rem; font-weight: 600; cursor: pointer; overflow-wrap: anywhere; }
#summary-text { margin-right: auto; }
#favs { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; font-weight: 400; }
#fav-list { display: contents; }
#favs button { font: inherit; font-size: .85rem; color: var(--fg); background: none; border: 0; padding: .3rem .5rem; cursor: pointer; }
.fav { display: inline-flex; align-items: center; background: var(--card); border: 1px solid var(--line); border-radius: 999px; }
.fav.on { border-color: var(--accent); }
.fav .fav-x { color: var(--muted); padding-left: 0; }
#fav-save { color: var(--accent) !important; }
#fav-save:disabled { color: var(--muted) !important; cursor: default; }
/* calendar views */
#views, #ranges, #period { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .1rem; }
#period-label { padding-left: .5rem; font-size: .9rem; font-weight: 600; }
#period button { font: inherit; font-size: .9rem; color: var(--accent); background: none; border: 1px solid transparent; border-radius: 999px; padding: .25rem .7rem; cursor: pointer; }
#period button:hover { border-color: var(--line); }
.cal { display: block; --hour: 3rem; }
.cal-head, .cal-body { display: grid; grid-template-columns: 3.2rem repeat(var(--days), minmax(0, 1fr)); gap: 0 .25rem; }
.cal-day { padding: .3rem .4rem; font-size: .8rem; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; border-bottom: 1px solid var(--line); }
.cal-day.on { color: var(--accent); }
.cal-body { height: clamp(18rem, calc(100vh - 13rem), calc(var(--rows) * var(--hour, 3rem))); }
.cal-gutter { display: grid; grid-auto-rows: 1fr; }
.cal-hour { font-size: .7rem; color: var(--muted); font-variant-numeric: tabular-nums; transform: translateY(-.35em); }
.cal-col { position: relative; border-left: 1px solid var(--line); background: repeating-linear-gradient(var(--line) 0 1px, transparent 1px calc(var(--hour, 3rem))); }
.cal-col.on { background-color: color-mix(in srgb, var(--accent) 5%, transparent); }
.ev { position: absolute; overflow: hidden; display: flex; flex-direction: column; padding: .15rem .3rem; font-size: .75rem; line-height: 1.15; background: var(--card); border: 1px solid var(--line); border-left: 3px solid var(--accent); border-radius: 5px; }
/* bookings (Google Calendar layer): blue, the palette twin of the red accent */
article.booking { border-left: 3px solid var(--booking); }
.ev.booking { border-left-color: var(--booking); background: color-mix(in srgb, var(--booking) 8%, var(--card)); }
.month-ev.booking .ev-time { color: var(--booking); }
.ev-time { font-weight: 600; font-variant-numeric: tabular-nums; }
.ev-course { overflow: hidden; }
.ev-meta { color: var(--muted); overflow: hidden; }
.month { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: .25rem; }
.month-head { padding: .3rem .2rem; font-size: .8rem; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: var(--muted); }
.month-cell { min-height: 7rem; padding: .3rem; background: var(--card); border: 1px solid var(--line); border-radius: 6px; cursor: pointer; overflow: hidden; }
.month-cell:hover { border-color: var(--accent); }
.month-cell.other { opacity: .45; }
.month-cell.on { border-color: var(--accent); }
.month-num { font-size: .8rem; font-weight: 600; font-variant-numeric: tabular-nums; }
.month-ev { display: flex; gap: .3rem; font-size: .7rem; line-height: 1.3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.month-ev .ev-course { text-overflow: ellipsis; }
.month-more { font-size: .7rem; color: var(--muted); }
[hidden] { display: none !important; }
main > .cal, main > .month { grid-column: 1 / -1; }
/* events: green, same saturation/lightness as the red accent and the booking blue */
article.event { border-left: 3px solid var(--event); }
.ev.event { border-left-color: var(--event); background: color-mix(in srgb, var(--event) 8%, var(--card)); }
.month-ev.event .ev-time { color: var(--event); }
/* multi-select: picked values as chips, then an input to add more */
#filters .chips { display: flex; flex-wrap: wrap; align-items: center; gap: .25rem; max-width: 24rem; }
#filters .chips input { min-width: 8rem; flex: 1; }
.chip { display: inline-flex; align-items: center; gap: .2rem; padding: .1rem .15rem .1rem .5rem; font-size: .85rem; color: var(--fg); background: var(--card); border: 1px solid var(--line); border-radius: 999px; }
.chip button { font: inherit; color: var(--muted); background: none; border: 0; padding: 0 .3rem; cursor: pointer; }
.chip button:hover { color: var(--fg); }
/* lab TV: rooms side by side, readable across the room */
.tv { font-size: 1.4rem; }
.tv header { justify-content: space-between; }
.tv-clock { font-size: 2.4rem; font-weight: 600; font-variant-numeric: tabular-nums; }
.tv-rooms { display: grid; grid-template-columns: repeat(var(--cols), minmax(0, 1fr)); gap: 1.5rem; }
.tv h2 { font-size: 1.1rem; }
.tv article.past { opacity: .45; }
.tv article.now { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent); }
.tv-events { margin-top: 1.5rem; }
.tv-events .event { margin: .3rem 0; padding-left: .6rem; border-left: 3px solid var(--event); }
```

- [ ] **Step 7 (controller): build and check in a real browser**

```bash
cd apps/site && export PATH="$PATH:$HOME/.pub-cache/bin" && jaspr build --dart-define=BASE=/openlabtwin/ && dart analyze
# serve under /openlabtwin/ and drive system Chrome with a throwaway Playwright script (uv run --with playwright):
#  - /openlabtwin/?teacher=André+Sabino&teacher=Fernando+Marson&room=&view=week&date=<this Monday> → 2 chips, grid events > 0
#  - /openlabtwin/ → Tech Lab chip, from today, articles > 0
#  - /openlabtwin/tv/?room=<Tech Lab>&room=Sala+04+(Oriente) → 2 room columns, articles, "Updated …"
```

Expected: the build generates routes `/` and `/tv`; `dart analyze` reports `No issues found!` (the build regenerates `lib/main.*.options.dart`, which are committed); every check above passes, and each page is ready in under 1 s.

Don't use headless `--dump-dom` or `--virtual-time-budget` for this check. Chrome's simulated clock ends before the 3 MB data file loads, so the page looks stuck on "Loading…" even though it works.

- [ ] **Commit**

```bash
git add apps/site
git commit -m "Site: schedule page with multi-select filters, lab TV page, event colours

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 4: CI, deploy to Pages, docs

**Files (pi, replace whole file):** `.github/workflows/sync.yml`, `.github/workflows/test.yml`

- [ ] **Step 1 (pi): `.github/workflows/sync.yml`**

```yaml
name: Sync and deploy

on:
  workflow_dispatch:
  push:
    branches: [main]
  schedule:
    - cron: "15 */6 * * *" # every 6 hours (UTC)

permissions:
  contents: write
  pages: write
  id-token: write

concurrency:
  group: sync
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    environment: github-pages
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      # both scripts exit non-zero before writing if something looks wrong; the last good site stays published
      - run: uv run python scripts/timetable.py
      - run: uv run python scripts/export.py
      - name: Commit data if changed
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add apps/site/web/data apps/site/web/calendar
          if git diff --cached --quiet; then
            echo "No changes"
          else
            git commit -m "Sync schedule"
            git push
          fi
      - uses: dart-lang/setup-dart@v1
      - name: Build site
        working-directory: apps/site
        run: |
          dart pub get
          dart pub global activate jaspr_cli 0.23.4
          dart pub global run jaspr_cli:jaspr build --dart-define=BASE=/openlabtwin/
      - uses: actions/upload-pages-artifact@v3
        with:
          path: apps/site/build/jaspr
      - uses: actions/deploy-pages@v4
```

- [ ] **Step 2 (pi): `.github/workflows/test.yml`**

```yaml
name: Test

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      - name: Python tests
        run: for t in tests/test_*.py; do uv run python "$t"; done
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - run: supabase db start
      - name: Database tests
        run: supabase test db

  site:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/site
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart analyze
      - run: dart test
```

- [ ] **Step 3 (controller): README**

Update `README.md`:
- "How it works": `export.py` writes `apps/site/web/data/all.json` and `apps/site/web/calendar/lab.ics`, and the sync workflow builds and deploys the site.
- A "Site" section: run it locally with `cd apps/site && jaspr serve`, the Pages URL, and the TV URL format `…/tv/?room=A&room=B`.

- [ ] **Step 4 (controller, outward-facing, user already approved deploying milestone 2): enable Pages and deploy**

```bash
gh api -X POST repos/berlogabob/openlabtwin/pages -f build_type=workflow
git push
gh run watch   # "Sync and deploy" and "Test"
```

Expected:
- Both workflows are green.
- `https://berlogabob.github.io/openlabtwin/` shows the schedule with the Tech Lab chip.
- `…/openlabtwin/tv/` shows the TV page.
- `…/openlabtwin/calendar/lab.ics` downloads.

- [ ] **Commit**

```bash
git add .github README.md
git commit -m "CI builds and deploys the site to GitHub Pages; README

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

## After this milestone (not in this plan)

- **Switch the TV:** the lab TV's browser opens `https://berlogabob.github.io/openlabtwin/tv/?room=…&room=…`.
- **Old site:** once nobody uses it, `iade-lab-schedule` gets a redirect page and is archived. `lab.ics` subscribers move to the new URL.
