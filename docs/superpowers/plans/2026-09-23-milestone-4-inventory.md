# Milestone 4: Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Files are delegated to local pi (`ornith-1.5:9b`) as "create or replace file = block"; the controller runs every shell step and checks each file byte for byte against this plan.

**Goal:** Staff record stock movements (receive, move, issue, return, consume, adjust) across the two storage tiers and the rooms. They see stock per place and who holds what, can issue or return a booking's whole equipment list at once, and get a warning when a stationary machine is booked twice. This is thesis L1: every movement is kept as history.

**Architecture:**
- **Database:** the append-only `movements` table and the `stock` view come from milestone 1. This milestone adds one view, `on_loan` (issued minus returned per item and person), under the same staff-only rules.
- **Office:** it gains `inventory.dart`, pure helpers in `logic.dart` (movement rows that mirror the database shape rule, shortages, stationary clashes), and kit buttons on the booking form.

**Spec:** `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md` (sections "Data model", "Back office").

## Ponytail

- **Low stock:** no stock check in the database. Issuing more than a place holds shows a warning with "Issue anyway". Stock may go negative until a receive or move corrects it.
- **Corrections** are `adjust` rows. Staff still can't update or delete movements (milestone 1 grants).
- **One page** for all of inventory: a list of items with per-place stock and loans, and a single "Record movement" form.
- **Deferred:** serial-numbered assets and RFID/QR tagging (spec "Out of scope").

---

### Task 1: `on_loan` view

- [ ] **Step 1 (pi): create `supabase/tests/database/03_inventory.test.sql`**

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into items (name, kind) values ('Loan ESP32', 'portable');
insert into places (name, kind, tier) values ('Loan shelf', 'storage', 'fast');
insert into people (name, kind) values ('Loan student', 'student');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 10, p.id, 'receive' from items i, places p where i.name = 'Loan ESP32' and p.name = 'Loan shelf';
insert into movements (item_id, qty, from_place, person_id, kind)
  select i.id, 5, p.id, s.id, 'issue' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';
insert into movements (item_id, qty, to_place, person_id, kind)
  select i.id, 2, p.id, s.id, 'return' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';

select is((select l.qty from on_loan l join people s on s.id = l.person_id where s.name = 'Loan student'),
          3::numeric, 'issued 5, returned 2: 3 on loan');
select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Loan shelf'),
          7::numeric, 'the shelf holds 10 - 5 + 2');
insert into movements (item_id, qty, to_place, person_id, kind)
  select i.id, 3, p.id, s.id, 'return' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';
select is_empty($$select 1 from on_loan l join people s on s.id = l.person_id where s.name = 'Loan student'$$,
                'everything back: nothing on loan');
select throws_ok($$insert into movements (item_id, qty, from_place, kind) select id, 1, null, 'issue' from items where name = 'Loan ESP32'$$,
                 '23514', null, 'an issue needs a place and a person');
set local role anon;
select throws_ok('select * from on_loan', '42501', null, 'anon cannot read on_loan');
reset role;

select * from finish();
rollback;
```

- [ ] **Step 2 (controller):** `uv run python scripts/sqltest.py` → `03_inventory` fails with `relation "on_loan" does not exist`.

- [ ] **Step 3 (pi): create `supabase/migrations/20260923170000_on_loan.sql`**

```sql
-- Who holds what right now: issued minus returned, per item and person. Like stock, never stored.
create view on_loan with (security_invoker = true) as
  select item_id, person_id, sum(case kind when 'issue' then qty else -qty end) as qty
  from movements
  where kind in ('issue', 'return') and person_id is not null
  group by item_id, person_id
  having sum(case kind when 'issue' then qty else -qty end) <> 0;

revoke all on on_loan from anon;
```

- [ ] **Step 4 (controller):** `uv run python scripts/sqltest.py`. Expected output: `applied 20260923170000_on_loan.sql`, then `✓` for 01 (4), 02 (8) and 03 (5).

- [ ] **Commit**

```bash
git add supabase
git commit -m "Inventory: on_loan view (issued minus returned per item and person)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 2: Office inventory

Files (pi, create or replace the whole file): `apps/office/lib/logic.dart`, `apps/office/test/logic_test.dart`, `apps/office/lib/data.dart`, `apps/office/lib/inventory.dart`, `apps/office/lib/bookings.dart`.

- [ ] **Step 1 (pi): `apps/office/lib/logic.dart`**

```dart
// Booking logic with no Flutter in it, so `flutter test` covers it.
// Times are the browser's local wall clock. ponytail: staff and lab are in Lisbon; store UTC, show local.

const kinds = ['class', 'consultation', 'club', 'workshop', 'equipment', 'maintenance', 'external'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

/// Weekly repeat until a date (inclusive), in the local form the export's dateutil expects (no Z).
String? weeklyRrule(DateTime? until) =>
    until == null ? null : 'FREQ=WEEKLY;UNTIL=${isoDate(until).replaceAll('-', '')}T235959';

DateTime? untilOf(String? rrule) {
  final m = RegExp(r'UNTIL=(\d{4})(\d{2})(\d{2})').firstMatch(rrule ?? '');
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

class Activity {
  Activity({
    this.id,
    this.title = '',
    this.layer = 'booking',
    this.kind = 'class',
    List<int>? placeIds,
    this.locationText = '',
    required this.start,
    required this.end,
    this.repeatUntil,
    List<String>? exdates,
    this.status = 'requested',
    this.requesterId,
    this.requesterDisplay = '',
    this.ownerStaffId,
    this.organizationId,
    this.attendees,
    this.purpose = '',
    this.publicNote = '',
  })  : placeIds = placeIds ?? [],
        exdates = exdates ?? [];

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: r['id'] as int?,
        title: r['title'] as String,
        layer: r['layer'] as String,
        kind: r['kind'] as String,
        placeIds: [for (final p in r['place_ids'] as List) p as int],
        locationText: r['location_text'] as String? ?? '',
        start: DateTime.parse(r['starts_at'] as String).toLocal(),
        end: DateTime.parse(r['ends_at'] as String).toLocal(),
        repeatUntil: untilOf(r['rrule'] as String?),
        exdates: [for (final d in (r['exdates'] as List? ?? const [])) d as String],
        status: r['status'] as String,
        requesterId: r['requester_id'] as int?,
        requesterDisplay: r['requester_display'] as String? ?? '',
        ownerStaffId: r['owner_staff_id'] as int?,
        organizationId: r['organization_id'] as int?,
        attendees: r['attendees'] as int?,
        purpose: r['purpose'] as String? ?? '',
        publicNote: r['public_note'] as String? ?? '',
      );

  int? id, requesterId, ownerStaffId, organizationId, attendees;
  String title, layer, kind, locationText, status, requesterDisplay, purpose, publicNote;
  List<int> placeIds;
  List<String> exdates;
  DateTime start, end;
  DateTime? repeatUntil; // null = one-off

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'layer': layer,
        'kind': kind,
        'place_ids': placeIds,
        'location_text': _blank(locationText),
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
        'rrule': weeklyRrule(repeatUntil),
        'exdates': exdates,
        'status': status,
        'requester_id': requesterId,
        'requester_display': _blank(requesterDisplay),
        'owner_staff_id': ownerStaffId,
        'organization_id': organizationId,
        'attendees': attendees,
        'purpose': _blank(purpose),
        'public_note': _blank(publicNote),
      };

  /// Start of every occurrence: weekly until repeatUntil, minus the skipped dates.
  List<DateTime> occurrences() => repeatUntil == null
      ? [start]
      : [
          for (var d = start;
              !_day(d).isAfter(repeatUntil!);
              d = DateTime(d.year, d.month, d.day + 7, d.hour, d.minute))
            if (!exdates.contains(isoDate(d))) d
        ];

  String when() {
    final repeat = repeatUntil == null ? '' : ' · weekly until ${isoDate(repeatUntil!)}';
    return '${isoDate(start)} ${hhmm(start)}–${hhmm(end)}$repeat';
  }
}

int _min(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

/// Clash warnings for every occurrence of [a]: lessons in the same rooms (rows from `lessons`) and other
/// approved activities sharing a room. Warnings, not blocks: staff decide.
List<String> clashes(Activity a, Set<String> roomNames, List<Map<String, dynamic>> lessons, List<Activity> others) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final l in lessons) {
      final rooms = [for (final r in l['rooms'] as List) r as String].where(roomNames.contains);
      if (l['date'] == day && rooms.isNotEmpty && _min(l['start_time'] as String) < to && from < _min(l['end_time'] as String)) {
        out.add('$day ${(l['start_time'] as String).substring(0, 5)}–${(l['end_time'] as String).substring(0, 5)} '
            'lesson: ${l['course']} (${rooms.join(', ')})');
      }
    }
    for (final o in others) {
      if (o.id == a.id || !o.placeIds.any(a.placeIds.contains)) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} booking: ${o.title}');
        }
      }
    }
  }
  return out;
}

// ---------- inventory ----------

const movementKinds = ['receive', 'move', 'issue', 'return', 'consume', 'adjust'];

/// A `movements` row, checked against the same shape rule the database enforces (movement_shape).
/// Fields a kind doesn't use are sent as null, so the check constraint never trips on leftovers.
Map<String, dynamic> movementRow({
  required String kind,
  required int itemId,
  required num qty,
  int? from,
  int? to,
  int? personId,
  int? activityId,
  int? byStaff,
}) {
  var problem = switch (kind) {
    'receive' => to == null ? 'Pick where it goes.' : null,
    'move' => from == null || to == null ? 'Pick both places.' : (from == to ? 'From and to must differ.' : null),
    'issue' => from == null || personId == null ? 'Pick the place and the person.' : null,
    'return' => to == null || personId == null ? 'Pick the person and where it goes back.' : null,
    'consume' => from == null ? 'Pick where it was used from.' : null,
    'adjust' => to == null ? 'Pick the place to correct.' : null,
    _ => 'Unknown kind: $kind',
  };
  if (problem == null && kind == 'adjust' && qty == 0) problem = 'A correction of 0 changes nothing.';
  if (problem == null && kind != 'adjust' && qty <= 0) problem = 'Quantity must be more than 0.';
  if (problem != null) throw ArgumentError(problem);
  return {
    'kind': kind,
    'item_id': itemId,
    'qty': qty,
    'from_place': const {'move', 'issue', 'consume'}.contains(kind) ? from : null,
    'to_place': const {'receive', 'move', 'return', 'adjust'}.contains(kind) ? to : null,
    'person_id': const {'issue', 'return'}.contains(kind) ? personId : null,
    'activity_id': activityId,
    'by_staff': byStaff,
  };
}

/// Kit lines (item_id, qty) the place can't cover, as readable warnings. Stock rows: item_id, place_id, qty.
List<String> shortages(List<Map<String, dynamic>> kit, int placeId, List<Map<String, dynamic>> stock, Map<int, String> names) {
  num have(int item) => stock.where((s) => s['item_id'] == item && s['place_id'] == placeId).fold<num>(0, (t, s) => t + (s['qty'] as num));
  return [
    for (final k in kit)
      if (have(k['item_id'] as int) < (k['qty'] as num))
        '${names[k['item_id']] ?? 'item ${k['item_id']}'}: need ${k['qty']}, have ${have(k['item_id'] as int)}'
  ];
}

/// Stationary items (laser cutter, 3D printer…) that another approved activity has at an overlapping time.
List<String> equipmentClashes(Activity a, Set<int> mine, List<(Activity, Set<int>)> others, Map<int, String> names) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final (o, theirs) in others) {
      final shared = mine.intersection(theirs);
      if (o.id == a.id || shared.isEmpty) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} ${[for (final i in shared) names[i] ?? '$i'].join(', ')} '
              'also booked for ${o.title}');
        }
      }
    }
  }
  return out;
}
```

- [ ] **Step 2 (pi): `apps/office/test/logic_test.dart`**

```dart
// Run: flutter test (from apps/office)
import 'package:flutter_test/flutter_test.dart';
import 'package:office/logic.dart';

void main() {
  test('weekly rrule round-trips its until date in the local form the export reads', () {
    expect(weeklyRrule(null), isNull);
    expect(weeklyRrule(DateTime(2026, 12, 31)), 'FREQ=WEEKLY;UNTIL=20261231T235959');
    expect(untilOf('FREQ=WEEKLY;UNTIL=20261231T235959'), DateTime(2026, 12, 31));
    expect(untilOf(null), isNull);
  });

  test('occurrences: weekly until the date, minus skipped dates, wall clock kept across DST', () {
    final a = Activity(
      start: DateTime(2026, 10, 20, 17),
      end: DateTime(2026, 10, 20, 19),
      repeatUntil: DateTime(2026, 11, 3),
      exdates: ['2026-10-27'],
    );
    expect([for (final d in a.occurrences()) '${isoDate(d)} ${hhmm(d)}'], ['2026-10-20 17:00', '2026-11-03 17:00']);
    expect(Activity(start: DateTime(2026, 10, 20, 17), end: DateTime(2026, 10, 20, 18)).occurrences().length, 1);
  });

  test('row mapping: blanks become null, times go out as UTC, round trip keeps fields', () {
    final a = Activity(
      title: ' Club ',
      kind: 'club',
      placeIds: [1],
      start: DateTime(2026, 10, 20, 17),
      end: DateTime(2026, 10, 20, 19),
      repeatUntil: DateTime(2026, 12, 15),
      requesterDisplay: '  ',
      purpose: 'robots',
    );
    final row = a.toRow();
    expect(row['title'], 'Club');
    expect(row['requester_display'], isNull);
    expect(row['location_text'], isNull);
    expect((row['starts_at'] as String).endsWith('Z'), isTrue);
    final b = Activity.fromRow({...row, 'id': 5, 'exdates': <String>[]});
    expect([b.id, b.title, b.kind, b.placeIds, b.start, b.end, b.repeatUntil, b.purpose],
        [5, 'Club', 'club', [1], a.start, a.end, a.repeatUntil, 'robots']);
  });

  test('clashes: lessons in the same room and approved bookings sharing a room, only when times overlap', () {
    final a = Activity(id: 1, title: 'Class', placeIds: [1], start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12));
    final lessons = [
      {'date': '2026-10-20', 'start_time': '11:00:00', 'end_time': '13:00:00', 'course': 'Maths', 'rooms': ['Tech Lab']},
      {'date': '2026-10-20', 'start_time': '12:00:00', 'end_time': '13:00:00', 'course': 'Touching', 'rooms': ['Tech Lab']},
      {'date': '2026-10-20', 'start_time': '10:00:00', 'end_time': '11:00:00', 'course': 'Elsewhere', 'rooms': ['Sala 1']},
    ];
    final others = [
      Activity(id: 2, title: 'Club', placeIds: [1], start: DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 10, 30)),
      Activity(id: 3, title: 'Other room', placeIds: [2], start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12)),
    ];
    expect(clashes(a, {'Tech Lab'}, lessons, others), [
      '2026-10-20 11:00–13:00 lesson: Maths (Tech Lab)',
      '2026-10-20 09:00–10:30 booking: Club',
    ]);
  });

  test('movement rows follow the database shape rule and null the fields a kind does not use', () {
    expect(movementRow(kind: 'receive', itemId: 1, qty: 10, from: 3, to: 2),
        {'kind': 'receive', 'item_id': 1, 'qty': 10, 'from_place': null, 'to_place': 2, 'person_id': null, 'activity_id': null, 'by_staff': null});
    expect(movementRow(kind: 'issue', itemId: 1, qty: 2, from: 2, to: 9, personId: 7, activityId: 5)['to_place'], isNull);
    expect(movementRow(kind: 'adjust', itemId: 1, qty: -3, to: 2)['qty'], -3);
    for (final bad in [
      () => movementRow(kind: 'issue', itemId: 1, qty: 2, from: 2),
      () => movementRow(kind: 'move', itemId: 1, qty: 2, from: 2, to: 2),
      () => movementRow(kind: 'receive', itemId: 1, qty: 0, to: 2),
      () => movementRow(kind: 'adjust', itemId: 1, qty: 0, to: 2),
      () => movementRow(kind: 'teleport', itemId: 1, qty: 1, to: 2),
    ]) {
      expect(bad, throwsArgumentError);
    }
  });

  test('shortages: kit lines the chosen place cannot cover', () {
    final stock = [
      {'item_id': 1, 'place_id': 2, 'qty': 3},
      {'item_id': 1, 'place_id': 9, 'qty': 50},
      {'item_id': 4, 'place_id': 2, 'qty': 8},
    ];
    final kit = [
      {'item_id': 1, 'qty': 5},
      {'item_id': 4, 'qty': 8},
      {'item_id': 6, 'qty': 1},
    ];
    expect(shortages(kit, 2, stock, {1: 'ESP32', 4: 'Breadboard'}), ['ESP32: need 5, have 3', 'item 6: need 1, have 0']);
  });

  test('stationary equipment booked twice at overlapping times', () {
    final a = Activity(id: 1, title: 'Workshop', start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12));
    final others = [
      (Activity(id: 2, title: 'Club', start: DateTime(2026, 10, 20, 11), end: DateTime(2026, 10, 20, 13)), {7}),
      (Activity(id: 3, title: 'Later', start: DateTime(2026, 10, 20, 12), end: DateTime(2026, 10, 20, 13)), {7}),
      (Activity(id: 4, title: 'Other kit', start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12)), {8}),
    ];
    expect(equipmentClashes(a, {7}, others, {7: 'Laser cutter'}), ['2026-10-20 11:00–13:00 Laser cutter also booked for Club']);
  });
}
```

- [ ] **Step 3 (pi): `apps/office/lib/data.dart`**

```dart
// Every query the office makes. RLS lets only staff (people.is_staff, linked by auth_user_id) read or write.
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logic.dart';

SupabaseClient get db => Supabase.instance.client;

/// Gives up after 20 s instead of leaving a spinner forever (lesson from UNIDCOM RIMS).
class TimeoutClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 20));
}

typedef Rec = Map<String, dynamic>;

/// Reference lists the pages need, loaded once per page.
class Refs {
  Refs(this.places, this.people, this.orgs, this.items, this.me);
  final List<Rec> places, people, orgs, items;
  final int? me; // the signed-in staff member's people.id
  List<Rec> get rooms => [for (final p in places) if (p['kind'] == 'room') p];
  Map<int, String> get itemNames => {for (final i in items) i['id'] as int: i['name'] as String};
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select('id,name,iade_name,kind,tier').order('name'),
    db.from('people').select('id,name,kind,email').order('name'),
    db.from('organizations').select('id,name').order('name'),
    db.from('items').select('id,name,kind').order('name'),
    db.from('people').select('id').eq('auth_user_id', db.auth.currentUser!.id).maybeSingle(),
  ]);
  return Refs(r[0] as List<Rec>, r[1] as List<Rec>, r[2] as List<Rec>, r[3] as List<Rec>, (r[4] as Rec?)?['id'] as int?);
}

/// Upcoming activities, plus repeating ones that started earlier.
Future<List<Activity>> upcoming() async {
  final since = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
  final rows = await db.from('activities').select().or('ends_at.gte.$since,rrule.not.is.null').order('starts_at');
  return [for (final r in rows) Activity.fromRow(r)];
}

Future<int> saveActivity(Activity a) async {
  if (a.id != null) {
    await db.from('activities').update(a.toRow()).eq('id', a.id!);
    return a.id!;
  }
  return (await db.from('activities').insert(a.toRow()).select('id').single())['id'] as int;
}

Future<List<String>> clashWarnings(Activity a, Refs refs) async {
  if (a.placeIds.isEmpty) return _stationaryClashes(a, refs);
  final names = {
    for (final r in refs.rooms)
      if (a.placeIds.contains(r['id'])) (r['iade_name'] ?? r['name']) as String
  };
  final last = a.occurrences().last;
  final lessons = await db
      .from('lessons')
      .select('date,start_time,end_time,course,rooms')
      .gte('date', isoDate(a.start))
      .lte('date', isoDate(last))
      .overlaps('rooms', names.toList());
  final others = await db.from('activities').select().eq('status', 'approved').overlaps('place_ids', a.placeIds);
  return [...clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]), ...await _stationaryClashes(a, refs)];
}

/// The same laser cutter / printer booked by another approved activity at an overlapping time.
Future<List<String>> _stationaryClashes(Activity a, Refs refs) async {
  if (a.id == null) return [];
  final mine = {
    for (final k in await equipment(a.id!))
      if ((k['items'] as Rec)['kind'] == 'stationary') k['item_id'] as int
  };
  if (mine.isEmpty) return [];
  final rows = await db
      .from('activity_items')
      .select('item_id,activities!inner(*)')
      .inFilter('item_id', mine.toList())
      .eq('activities.status', 'approved')
      .neq('activity_id', a.id!);
  final byActivity = <int, (Activity, Set<int>)>{};
  for (final r in rows) {
    final o = Activity.fromRow(r['activities'] as Rec);
    byActivity.putIfAbsent(o.id!, () => (o, <int>{})).$2.add(r['item_id'] as int);
  }
  return equipmentClashes(a, mine, byActivity.values.toList(), refs.itemNames);
}

Future<List<Rec>> equipment(int activityId) =>
    db.from('activity_items').select('item_id,qty,prepared,items(name,kind)').eq('activity_id', activityId).order('item_id');

Future<void> setEquipment(int activityId, int itemId, num qty, bool prepared) => db
    .from('activity_items')
    .upsert({'activity_id': activityId, 'item_id': itemId, 'qty': qty, 'prepared': prepared});

Future<void> removeEquipment(int activityId, int itemId) =>
    db.from('activity_items').delete().eq('activity_id', activityId).eq('item_id', itemId);

Future<Rec> addPerson(String name, String kind, String email) => db
    .from('people')
    .insert({'name': name.trim(), 'kind': kind, 'email': email.trim().isEmpty ? null : email.trim().toLowerCase()})
    .select('id,name,kind,email')
    .single();

Future<Rec> addItem(String name, String kind) =>
    db.from('items').insert({'name': name.trim(), 'kind': kind}).select('id,name,kind').single();

// ---------- inventory ----------

Future<List<Rec>> stock() => db.from('stock').select('item_id,place_id,qty');

Future<List<Rec>> onLoan() => db.from('on_loan').select('item_id,person_id,qty');

/// Movements are append-only: a mistake is corrected with an 'adjust' row, never edited.
Future<void> addMovements(List<Rec> rows) => db.from('movements').insert(rows);
```

- [ ] **Step 4 (pi): `apps/office/lib/inventory.dart`**

```dart
// Inventory: stock per place (fast/long storage, rooms), who holds what, and one form for every movement.
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final refs = widget.refs;
  late Future<(List<Rec>, List<Rec>)> data = _load();

  Future<(List<Rec>, List<Rec>)> _load() async => (await stock(), await onLoan());

  String _place(int? id) => refs.places.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;
  String _person(int? id) => refs.people.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _movement() async {
    var kind = 'receive';
    int? itemId, from, to, personId;
    final qty = TextEditingController(text: '1');
    final newName = TextEditingController();
    var newKind = 'portable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, set) {
        DropdownButton<int?> placePick(String hint, int? value, void Function(int?) change) => DropdownButton<int?>(
              value: value,
              isExpanded: true,
              hint: Text(hint),
              items: [
                for (final p in refs.places)
                  DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}${p['tier'] == null ? '' : ' (${p['tier']})'}')),
              ],
              onChanged: (v) => set(() => change(v)),
            );
        return AlertDialog(
          title: const Text('Record movement'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                value: kind,
                isExpanded: true,
                items: [for (final k in movementKinds) DropdownMenuItem(value: k, child: Text(k))],
                onChanged: (v) => set(() => kind = v!),
              ),
              DropdownButton<int?>(
                value: itemId,
                isExpanded: true,
                hint: const Text('Item, or type a new one below'),
                items: [for (final i in refs.items) DropdownMenuItem(value: i['id'] as int, child: Text('${i['name']} (${i['kind']})'))],
                onChanged: (v) => set(() => itemId = v),
              ),
              if (itemId == null) ...[
                TextField(controller: newName, decoration: const InputDecoration(labelText: 'New item name')),
                DropdownButton<String>(
                  value: newKind,
                  isExpanded: true,
                  items: [for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => set(() => newKind = v!),
                ),
              ],
              TextField(
                controller: qty,
                decoration: InputDecoration(labelText: kind == 'adjust' ? 'Correction (+/-)' : 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              ),
              if (const {'move', 'issue', 'consume'}.contains(kind)) placePick('From', from, (v) => from = v),
              if (const {'receive', 'move', 'return', 'adjust'}.contains(kind)) placePick(kind == 'adjust' ? 'Place' : 'To', to, (v) => to = v),
              if (const {'issue', 'return'}.contains(kind))
                DropdownButton<int?>(
                  value: personId,
                  isExpanded: true,
                  hint: Text(kind == 'issue' ? 'Given to' : 'Returned by'),
                  items: [for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (${p['kind']})'))],
                  onChanged: (v) => set(() => personId = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      if (itemId == null) {
        if (newName.text.trim().isEmpty) return _say('Pick an item or type a new one.');
        final item = await addItem(newName.text, newKind);
        refs.items.add(item);
        itemId = item['id'] as int;
      }
      final row = movementRow(
          kind: kind, itemId: itemId!, qty: num.tryParse(qty.text.trim()) ?? 0, from: from, to: to, personId: personId, byStaff: refs.me);
      await addMovements([row]);
      _say('Recorded: $kind ${row['qty']} × ${refs.itemNames[itemId]}.');
      setState(() => data = _load());
    } on ArgumentError catch (e) {
      _say(e.message as String);
    } catch (e) {
      _say('Could not record: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Inventory'), actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load())),
        ]),
        floatingActionButton:
            FloatingActionButton.extended(onPressed: _movement, icon: const Icon(Icons.swap_horiz), label: const Text('Record movement')),
        body: FutureBuilder(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final loaded = snap.data;
            if (loaded == null) return const Center(child: CircularProgressIndicator());
            final (stockRows, loans) = loaded;
            if (refs.items.isEmpty) return const Center(child: Text('No items yet. Record a "receive" to add the first one.'));
            return ListView(children: [
              for (final i in refs.items)
                Builder(builder: (context) {
                  final here = [for (final s in stockRows) if (s['item_id'] == i['id'] && s['qty'] != 0) s];
                  final out = [for (final l in loans) if (l['item_id'] == i['id']) l];
                  final total = here.fold<num>(0, (t, s) => t + (s['qty'] as num));
                  return ListTile(
                    title: Text('${i['name']} (${i['kind']})'),
                    subtitle: Text([
                      for (final s in here) '${_place(s['place_id'] as int?)} ${s['qty']}',
                      for (final l in out) 'on loan: ${_person(l['person_id'] as int?)} ${l['qty']}',
                    ].join(' · ')),
                    trailing: Text('$total', style: Theme.of(context).textTheme.titleMedium),
                  );
                }),
            ]);
          },
        ),
      );
}
```

- [ ] **Step 5 (pi): `apps/office/lib/bookings.dart`**

```dart
// Bookings list and the booking form (requester, rooms, repeat, equipment, clash warnings, approval).
import 'package:flutter/material.dart';

import 'data.dart';
import 'inventory.dart';
import 'logic.dart';

const statusColors = {
  'requested': Colors.orange,
  'approved': Colors.green,
  'rejected': Colors.grey,
  'cancelled': Colors.grey,
  'done': Colors.blueGrey,
};

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  late Future<(Refs, List<Activity>)> data = _load();

  Future<(Refs, List<Activity>)> _load() async => (await loadRefs(), await upcoming());

  Future<void> _open(Refs refs, Activity? a) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 10);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingForm(
        refs: refs,
        activity: a ?? Activity(start: start, end: start.add(const Duration(hours: 2)), ownerStaffId: refs.me),
      ),
    ));
    setState(() => data = _load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: data,
        builder: (context, snap) {
          final loaded = snap.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Lab bookings'), actions: [
              if (loaded != null)
                IconButton(
                  tooltip: 'Inventory',
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InventoryPage(refs: loaded.$1))),
                ),
              IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load())),
              IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
            ]),
            floatingActionButton: loaded == null
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _open(loaded.$1, null), icon: const Icon(Icons.add), label: const Text('New booking')),
            body: snap.hasError
                ? Center(child: Text('Could not load: ${snap.error}'))
                : loaded == null
                    ? const Center(child: CircularProgressIndicator())
                    : loaded.$2.isEmpty
                        ? const Center(child: Text('No upcoming bookings.'))
                        : ListView(children: [
                            for (final a in loaded.$2)
                              ListTile(
                                title: Text(a.title),
                                subtitle: Text([
                                  a.when(),
                                  _rooms(loaded.$1, a),
                                  a.requesterDisplay,
                                ].where((s) => s.isNotEmpty).join(' · ')),
                                trailing: Chip(label: Text(a.status), backgroundColor: statusColors[a.status]?.withAlpha(60)),
                                onTap: () => _open(loaded.$1, a),
                              ),
                          ]),
          );
        },
      );
}

String _rooms(Refs refs, Activity a) => [
      for (final r in refs.rooms)
        if (a.placeIds.contains(r['id'])) r['name'] as String,
      if (a.locationText.isNotEmpty) a.locationText,
    ].join(', ');

class BookingForm extends StatefulWidget {
  const BookingForm({super.key, required this.refs, required this.activity});
  final Refs refs;
  final Activity activity;

  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  late final a = widget.activity;
  late final refs = widget.refs;
  late final title = TextEditingController(text: a.title);
  late final location = TextEditingController(text: a.locationText);
  late final display = TextEditingController(text: a.requesterDisplay);
  late final attendees = TextEditingController(text: a.attendees?.toString() ?? '');
  late final purpose = TextEditingController(text: a.purpose);
  late final note = TextEditingController(text: a.publicNote);
  late final skip = TextEditingController(text: a.exdates.join(', '));
  List<Rec> kit = [];
  List<String>? warnings;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (a.id != null) _loadKit();
  }

  Future<void> _loadKit() async {
    final rows = await equipment(a.id!);
    setState(() => kit = rows);
  }

  void _collect() {
    a
      ..title = title.text
      ..locationText = location.text
      ..requesterDisplay = display.text
      ..attendees = int.tryParse(attendees.text.trim())
      ..purpose = purpose.text
      ..publicNote = note.text
      ..exdates = [for (final s in skip.text.split(',')) if (s.trim().isNotEmpty) s.trim()];
  }

  Future<void> _save([String? status]) async {
    _collect();
    if (a.title.trim().isEmpty) return _say('Give the booking a title.');
    if (!a.end.isAfter(a.start)) return _say('The end time must be after the start.');
    if (a.placeIds.isEmpty && a.locationText.trim().isEmpty) return _say('Pick a room or type a location.');
    setState(() => busy = true);
    try {
      if (status != null) a.status = status;
      a.id = await saveActivity(a);
      final w = await clashWarnings(a, refs);
      setState(() => warnings = w);
      _say(a.status == 'approved'
          ? 'Saved and approved. The public site shows it within about 15 minutes.'
          : 'Saved (${a.status}).');
    } catch (e) {
      _say('Could not save: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: a.start, firstDate: DateTime(2025), lastDate: DateTime(2030));
    if (d == null) return;
    setState(() {
      a.start = DateTime(d.year, d.month, d.day, a.start.hour, a.start.minute);
      a.end = DateTime(d.year, d.month, d.day, a.end.hour, a.end.minute);
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(isStart ? a.start : a.end));
    if (t == null) return;
    setState(() {
      final base = a.start;
      final v = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (isStart) {
        final length = a.end.difference(a.start);
        a
          ..start = v
          ..end = v.add(length);
      } else {
        a.end = v;
      }
    });
  }

  Future<void> _pickUntil() async {
    final d = await showDatePicker(
        context: context, initialDate: a.repeatUntil ?? a.start.add(const Duration(days: 91)), firstDate: a.start, lastDate: DateTime(2030));
    if (d != null) setState(() => a.repeatUntil = d);
  }

  Future<void> _newPerson() async {
    final name = TextEditingController(), email = TextEditingController();
    var kind = 'professor';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('New person'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email (private)')),
            DropdownButton<String>(
              value: kind,
              isExpanded: true,
              items: [for (final k in const ['professor', 'student', 'staff', 'external']) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => set(() => kind = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final p = await addPerson(name.text, kind, email.text);
    setState(() {
      refs.people.add(p);
      _setRequester(p);
    });
  }

  void _setRequester(Rec p) {
    a.requesterId = p['id'] as int;
    if (display.text.trim().isEmpty) display.text = p['kind'] == 'professor' ? 'Prof. ${p['name']}' : p['name'] as String;
  }

  Future<void> _addKit() async {
    Rec? item;
    final qty = TextEditingController(text: '1');
    final newName = TextEditingController();
    var newKind = 'portable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Add equipment'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<Rec?>(
              value: item,
              isExpanded: true,
              hint: const Text('Existing item, or type a new one below'),
              items: [for (final i in refs.items) DropdownMenuItem(value: i, child: Text('${i['name']} (${i['kind']})'))],
              onChanged: (v) => set(() => item = v),
            ),
            TextField(controller: newName, decoration: const InputDecoration(labelText: 'New item name')),
            DropdownButton<String>(
              value: newKind,
              isExpanded: true,
              items: [for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => set(() => newKind = v!),
            ),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (item == null && newName.text.trim().isNotEmpty) {
      item = await addItem(newName.text, newKind);
      refs.items.add(item!);
    }
    if (item == null) return;
    await setEquipment(a.id!, item!['id'] as int, num.tryParse(qty.text) ?? 1, false);
    await _loadKit();
  }

  /// Issue or return the whole equipment list in one go, as movements linked to this booking.
  Future<void> _kit(String kind) async {
    int? placeId = [for (final p in refs.places) if (p['tier'] == 'fast') p['id'] as int].firstOrNull;
    int? personId = a.requesterId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(kind == 'issue' ? 'Issue kit' : 'Return kit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<int?>(
              value: placeId,
              isExpanded: true,
              hint: Text(kind == 'issue' ? 'From' : 'Back to'),
              items: [for (final p in refs.places) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
              onChanged: (v) => set(() => placeId = v),
            ),
            DropdownButton<int?>(
              value: personId,
              isExpanded: true,
              hint: Text(kind == 'issue' ? 'Given to' : 'Returned by'),
              items: [for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
              onChanged: (v) => set(() => personId = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(kind == 'issue' ? 'Issue' : 'Return')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final rows = [
        for (final k in kit)
          movementRow(
              kind: kind, itemId: k['item_id'] as int, qty: k['qty'] as num, from: placeId, to: placeId, personId: personId, activityId: a.id, byStaff: refs.me),
      ];
      if (kind == 'issue') {
        final short = shortages(kit, placeId!, await stock(), refs.itemNames);
        if (short.isNotEmpty && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Not enough in stock there'),
              content: Text('${short.join('\n')}\n\nIssue anyway? Stock will go negative until you record a receive or move.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Issue anyway')),
              ],
            ),
          );
          if (go != true) return;
        }
      }
      await addMovements(rows);
      _say('${kind == 'issue' ? 'Issued' : 'Returned'} ${rows.length} line(s).');
    } on ArgumentError catch (e) {
      _say(e.message as String);
    } catch (e) {
      _say('Could not record: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = a.start;
    return Scaffold(
      appBar: AppBar(title: Text(a.id == null ? 'New booking' : 'Booking'), actions: [
        if (busy) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator())),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          Chip(label: Text('Status: ${a.status}'), backgroundColor: statusColors[a.status]?.withAlpha(60)),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'booking', label: Text('Booking')), ButtonSegment(value: 'event', label: Text('Event'))],
            selected: {a.layer},
            onSelectionChanged: (v) => setState(() => a.layer = v.first),
          ),
        ]),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title (public)')),
        DropdownButtonFormField<String>(
          initialValue: a.kind,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => a.kind = v!,
        ),
        const SizedBox(height: 12),
        Text('Rooms', style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 8, children: [
          for (final r in refs.rooms)
            FilterChip(
              label: Text(r['name'] as String),
              selected: a.placeIds.contains(r['id']),
              onSelected: (on) => setState(() => on ? a.placeIds.add(r['id'] as int) : a.placeIds.remove(r['id'])),
            ),
        ]),
        TextField(controller: location, decoration: const InputDecoration(labelText: 'Or off-site location (events)')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(isoDate(s))),
          OutlinedButton(onPressed: () => _pickTime(true), child: Text('from ${hhmm(a.start)}')),
          OutlinedButton(onPressed: () => _pickTime(false), child: Text('to ${hhmm(a.end)}')),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeats weekly'),
          value: a.repeatUntil != null,
          onChanged: (on) => setState(() => a.repeatUntil = on ? s.add(const Duration(days: 91)) : null),
        ),
        if (a.repeatUntil != null) ...[
          OutlinedButton(onPressed: _pickUntil, child: Text('until ${isoDate(a.repeatUntil!)}')),
          TextField(controller: skip, decoration: const InputDecoration(labelText: 'Skip dates (YYYY-MM-DD, comma-separated)')),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: a.requesterId,
              decoration: const InputDecoration(labelText: 'Requested by'),
              items: [
                for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (${p['kind']})')),
              ],
              onChanged: (v) => setState(() => _setRequester(refs.people.firstWhere((p) => p['id'] == v))),
            ),
          ),
          IconButton(tooltip: 'New person', icon: const Icon(Icons.person_add), onPressed: _newPerson),
        ]),
        TextField(controller: display, decoration: const InputDecoration(labelText: 'Shown on the site as (e.g. Prof. Cláudia)')),
        DropdownButtonFormField<int?>(
          initialValue: a.organizationId,
          decoration: const InputDecoration(labelText: 'Club / course / project (optional)'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (final o in refs.orgs) DropdownMenuItem(value: o['id'] as int, child: Text(o['name'] as String)),
          ],
          onChanged: (v) => a.organizationId = v,
        ),
        TextField(controller: attendees, decoration: const InputDecoration(labelText: 'People attending'), keyboardType: TextInputType.number),
        TextField(controller: purpose, decoration: const InputDecoration(labelText: 'Purpose and notes (private)'), maxLines: 3),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Public note (shown on the site)')),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: busy ? null : () => _save(), child: const Text('Save')),
          if (a.status != 'approved')
            FilledButton.tonal(onPressed: busy ? null : () => _save('approved'), child: const Text('Approve')),
          if (a.status == 'requested') OutlinedButton(onPressed: busy ? null : () => _save('rejected'), child: const Text('Reject')),
          if (a.status == 'approved') OutlinedButton(onPressed: busy ? null : () => _save('cancelled'), child: const Text('Cancel booking')),
          if (a.status == 'approved') OutlinedButton(onPressed: busy ? null : () => _save('done'), child: const Text('Mark done')),
        ]),
        if (warnings != null) ...[
          const SizedBox(height: 16),
          Text(warnings!.isEmpty ? 'No clashes.' : 'Clashes (${warnings!.length}):', style: Theme.of(context).textTheme.titleSmall),
          for (final w in warnings!.take(20)) Text('• $w', style: const TextStyle(color: Colors.deepOrange)),
        ],
        const Divider(height: 32),
        Text('Equipment to prepare', style: Theme.of(context).textTheme.titleMedium),
        if (a.id == null) const Text('Save the booking first, then add equipment.'),
        for (final k in kit)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: k['prepared'] as bool,
            title: Text('${k['qty']} × ${(k['items'] as Rec)['name']}'),
            secondary: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await removeEquipment(a.id!, k['item_id'] as int);
                await _loadKit();
              },
            ),
            onChanged: (v) async {
              await setEquipment(a.id!, k['item_id'] as int, k['qty'] as num, v ?? false);
              await _loadKit();
            },
          ),
        if (a.id != null)
          Wrap(spacing: 8, children: [
            TextButton.icon(onPressed: _addKit, icon: const Icon(Icons.add), label: const Text('Add equipment')),
            if (kit.isNotEmpty) TextButton.icon(onPressed: () => _kit('issue'), icon: const Icon(Icons.outbox), label: const Text('Issue kit')),
            if (kit.isNotEmpty) TextButton.icon(onPressed: () => _kit('return'), icon: const Icon(Icons.move_to_inbox), label: const Text('Return kit')),
          ]),
      ]),
    );
  }
}
```

- [ ] **Step 6 (controller): verify**

- `cd apps/office && flutter analyze && flutter test` should report `No issues found!` and `+7: All tests passed!`.
- Then run the end-to-end check: an `E2E=true` build served locally, signed in by magic link, using the live database:
  1. Record a movement: receive a new item "E2E widget" × 10 into Fast storage. The Inventory list shows it with 10.
  2. Clean up with the service key: delete the test movements and the item. `movements` is append-only for staff, and the service key bypasses that.

- [ ] **Commit**

```bash
git add apps/office
git commit -m "Office inventory: stock per place, loans, movements, kit issue/return, stationary clashes

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 3: Deploy

- [ ] `git push`, then watch "Sync and deploy" and "Test". Live check: the production office signs in, and its REST calls, including `stock` and `on_loan`, return 200.
- [ ] README: add inventory to the back-office section (movements, loans, kit buttons, warnings rather than blocks).
