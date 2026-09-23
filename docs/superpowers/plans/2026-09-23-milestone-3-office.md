# Milestone 3: Back Office Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Code files are delegated to local pi (`ornith-1.5:9b`) as "create file = block"; the controller runs every shell step and checks each file byte for byte against this plan.

**Goal:** Staff sign in with an email link and log bookings and events: who asked, what for, which room, when, and repeats. They attach the equipment to prepare, see clash warnings, and approve. Approved rows reach the public site within about 15 minutes.

**Architecture:**
- **App:** Flutter web in `apps/office`, served at `/openlabtwin/office/` from the same Pages deploy.
- **Data:** it talks to Supabase directly with the publishable (anon) key plus the signed-in staff member's session. The row-level security from milestone 1 is the only gate.
- **Publishing:** the sync workflow gains a 10-minute export-only schedule. It deploys only when the exported data changed.

**Tech Stack:** Flutter 3.47 (web), supabase_flutter ^2.16.0, http; Supabase Auth (email magic link, sign-ups disabled); GitHub Actions + Pages.

**Spec:** `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md` (section "Back office").

## Decisions (user, 2026-09-23)

- **Publishing:** an export every 10 minutes instead of a database webhook. No GitHub token is stored in Supabase. Changes are live in about 10–15 minutes, longer when GitHub's scheduler is busy.
- **TechClub calendar:** not imported (its only event was a test). The Google feed is retired.
- **Office URL:** the same site, `https://berlogabob.github.io/openlabtwin/office/`.

## Ponytail

- **Four `lib` files:** `logic.dart` (pure, tested), `data.dart` (every query), `main.dart` (start-up and sign-in), `bookings.dart` (list and form). No router and no state library.
- **Staff accounts:** created by an admin through the Auth admin API and linked in `people.auth_user_id`. There's no claim function and no sign-up.
- **Clash check** runs after every save: lessons in the same rooms plus other approved bookings. Stationary-equipment double-booking waits for milestone 4 inventory.
- **Time zone:** the browser's local wall clock. Staff and the lab are in Lisbon. Times are stored in UTC.

## Already done by the controller (live project `openlabtwin`)

- **Auth config** (Management API): `site_url` is the office URL; `uri_allow_list` holds the office URL plus `http://127.0.0.1:8765/**` for local tests; `disable_signup` is true.
- **Staff account** `andre.berloga@gmail.com` was created (`POST /auth/v1/admin/users`, `email_confirm: true`) and linked to people id 4.
- **End-to-end check** (Playwright on system Chrome, test build with `--dart-define=E2E=true`):
  - sign in with an admin-generated magic link;
  - New booking → title → Tech Lab → Approve → saved, with 4 clash warnings;
  - the row is in the database (owner 4, 10:00 Lisbon stored as 09:00 UTC);
  - the export puts it in `all.json` (layer booking) and `lab.ics`;
  - the test rows were deleted.

---

### Task 1: Office app

- [ ] **Step 1 (controller, shell)**

```bash
cd apps && flutter create --platforms web --project-name office --org pt.iade.lab --empty office && cd office
flutter pub add supabase_flutter:^2.16.0 http && rm -f README.md office.iml && mkdir -p test
```

- [ ] **Step 2 (pi): `apps/office/pubspec.yaml` description line becomes**

```yaml
description: "Lab office: staff log, approve and equip lab bookings"
```

- [ ] **Step 3 (pi): create `apps/office/lib/logic.dart`**

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
```

- [ ] **Step 4 (pi): create `apps/office/test/logic_test.dart`**

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
}
```

- [ ] **Step 5 (pi): create `apps/office/lib/data.dart`**

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

/// Reference lists the form needs, loaded once per page.
class Refs {
  Refs(this.rooms, this.people, this.orgs, this.items, this.me);
  final List<Rec> rooms, people, orgs, items;
  final int? me; // the signed-in staff member's people.id
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select('id,name,iade_name').eq('kind', 'room').order('name'),
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
  if (a.placeIds.isEmpty) return [];
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
  return clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]);
}

Future<List<Rec>> equipment(int activityId) =>
    db.from('activity_items').select('item_id,qty,prepared,items(name)').eq('activity_id', activityId).order('item_id');

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
```

- [ ] **Step 6 (pi): replace `apps/office/lib/main.dart`**

```dart
// Lab office: staff sign in with an email link, then log, approve and equip bookings.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookings.dart';
import 'data.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY'); // public by design: anon has no grants, RLS decides

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // browser tests read the semantics tree; build with --dart-define=E2E=true (off in production)
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey, httpClient: TimeoutClient());
  } catch (e) {
    // a bad key or no network at boot must not leave a blank white page (lesson from UNIDCOM RIMS)
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Could not start the office: $e')))));
    return;
  }
  runApp(const OfficeApp());
}

class OfficeApp extends StatelessWidget {
  const OfficeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lab office',
        theme: ThemeData(colorSchemeSeed: const Color(0xFFB3261E)),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (context, _) => db.auth.currentSession == null ? const LoginPage() : const BookingsPage(),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  String? message;

  Future<void> _send() async {
    setState(() => message = 'Sending…');
    try {
      await db.auth.signInWithOtp(
        email: email.text.trim().toLowerCase(),
        shouldCreateUser: false, // staff accounts are created by an admin; nobody signs up here
        emailRedirectTo: Uri.base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'[?#]+$'), ''),
      );
      setState(() => message = 'Check your inbox: the link signs you in on this browser.');
    } on AuthException catch (e) {
      setState(() => message = e.message.contains('not allowed') || e.statusCode == '422'
          ? 'This email is not a lab staff account.'
          : e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Lab office', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Staff email'),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _send, child: const Text('Send sign-in link')),
              if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!)),
            ]),
          ),
        ),
      );
}
```

- [ ] **Step 7 (pi): create `apps/office/lib/bookings.dart`**

```dart
// Bookings list and the booking form (requester, rooms, repeat, equipment, clash warnings, approval).
import 'package:flutter/material.dart';

import 'data.dart';
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
        if (a.id != null) TextButton.icon(onPressed: _addKit, icon: const Icon(Icons.add), label: const Text('Add equipment')),
      ]),
    );
  }
}
```

- [ ] **Step 8 (controller): verify**

Run: `cd apps/office && flutter analyze && flutter test && flutter build web --release --base-href /openlabtwin/office/ --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`
Expected: `No issues found!`, `+4: All tests passed!`, `✓ Built build/web`.

- [ ] **Commit**

```bash
git add apps/office
git commit -m "Office: staff sign-in, bookings list and form with repeats, equipment, clash warnings, approval

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 2: Publish every 10 minutes, deploy the office, CI

- [ ] **Step 1 (pi): replace `.github/workflows/sync.yml`**

```yaml
name: Sync and deploy

on:
  workflow_dispatch:
  push:
    branches: [main]
  schedule:
    - cron: "15 */6 * * *" # scrape the IADE timetable
    - cron: "*/10 * * * *" # publish approved bookings (export only; deploys only when data changed)

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
    outputs:
      deploy: ${{ steps.commit.outputs.deploy }}
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
      QUICK: ${{ github.event.schedule == '*/10 * * * *' }}
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      # both scripts exit non-zero before writing if something looks wrong; the last good site stays published
      - if: env.QUICK != 'true'
        run: uv run python scripts/timetable.py
      - run: uv run python scripts/export.py
      - name: Commit data if changed
        id: commit
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add apps/site/web/data apps/site/web/calendar
          if git diff --cached --quiet; then
            echo "No changes"
            [ "$QUICK" = "true" ] || echo "deploy=true" >> "$GITHUB_OUTPUT"
          else
            git commit -m "Sync schedule"
            git push
            echo "deploy=true" >> "$GITHUB_OUTPUT"
          fi

  deploy:
    needs: sync
    if: needs.sync.outputs.deploy == 'true'
    runs-on: ubuntu-latest
    environment: github-pages
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main # includes the data commit the sync job just pushed
      - uses: dart-lang/setup-dart@v1
      - name: Build site
        working-directory: apps/site
        run: |
          dart pub get
          dart pub global activate jaspr_cli 0.23.4
          dart pub global run jaspr_cli:jaspr build --dart-define=BASE=/openlabtwin/
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Build office
        working-directory: apps/office
        run: |
          flutter pub get
          flutter build web --release --base-href /openlabtwin/office/ \
            --dart-define=SUPABASE_URL=${{ vars.SUPABASE_URL }} --dart-define=SUPABASE_ANON_KEY=${{ vars.SUPABASE_ANON_KEY }}
          cp -R build/web ../site/build/jaspr/office
      - uses: actions/upload-pages-artifact@v3
        with:
          path: apps/site/build/jaspr
      - uses: actions/deploy-pages@v4
```

- [ ] **Step 2 (pi): replace `.github/workflows/test.yml`**

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

  office:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/office
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 3 (controller): repository variables (public values; the anon key has no grants)**

```bash
gh variable set SUPABASE_URL -b https://huqecytswaswkswofrqd.supabase.co
gh variable set SUPABASE_ANON_KEY -b "$(supabase projects api-keys --project-ref huqecytswaswkswofrqd -o json | jq -r '.[] | select(.name=="anon") | .api_key')"
```

- [ ] **Step 4 (controller): README**

- A "Back office" section: the URL; that sign-in is by email link, staff only; and how to add a staff member:
  1. `POST /auth/v1/admin/users` with the service key;
  2. insert or update the `people` row with `is_staff = true` and `auth_user_id`.
- The Google Calendar feed is retired.
- Publishing happens within about 15 minutes of approval.

- [ ] **Step 5 (controller): deploy and check live**

`git push`, watch "Sync and deploy" and "Test", then rerun the end-to-end script against `https://berlogabob.github.io/openlabtwin/office/` (production build, no E2E semantics). Check that the sign-in page loads, then sign in through an admin-generated link. The page check can only confirm that the page renders without errors, because production builds don't expose the accessibility tree.

- [ ] **Commit**

```bash
git add .github README.md
git commit -m "Publish approved bookings every 10 minutes; build and deploy the office; CI for the office

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

