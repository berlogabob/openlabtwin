// Run: flutter test (from apps/office)
import 'package:flutter_test/flutter_test.dart';
import 'package:office/logic.dart';

void main() {
  test('gone items have no stock and no loan', () {
    final stock = [{'item_id': 1, 'qty': 0}, {'item_id': 2, 'qty': 1}];
    final loans = [{'item_id': 1, 'qty': 1}];
    expect(isGone(1, stock, loans), isFalse);
    expect(isGone(2, stock, loans), isFalse);
    expect(isGone(3, stock, loans), isTrue);
  });

  test('archive person matching prefers student number, then trimmed case-insensitive name', () {
    final people = [
      {'id': 1, 'name': 'Ana Silva', 'student_number': 'A-1'},
      {'id': 2, 'name': 'João Costa', 'student_number': null},
    ];
    expect(personFor({'student_number': 'A-1', 'name': 'other'}, people), 1);
    expect(personFor({'name': '  JOÃO COSTA '}, people), 2);
    expect(personFor({'name': 'Nobody'}, people), isNull);
  });

  test('archive loan rows skip blanks, clamp quantity, and validate dates', () {
    expect(sheetLoans(personId: 4, course: ' Maths ', outOn: '2026-01-02', backOn: '2026-01-03', lines: [
      {'item_text': ' Arduino ', 'item_id': 8, 'qty': 0},
      {'item_text': ' ', 'item_id': 9, 'qty': 2},
    ]), [
      {'person_id': 4, 'course': 'Maths', 'item_id': 8, 'item_text': 'Arduino', 'qty': 1, 'out_on': '2026-01-02', 'back_on': '2026-01-03'},
    ]);
    expect(() => sheetLoans(personId: null, lines: [], outOn: '02/01/2026'), throwsArgumentError);
    expect(() => sheetLoans(personId: null, lines: [], outOn: '2026-01-03', backOn: '2026-01-02'), throwsArgumentError);
  });

  test('archive usage totals and buy list sort predictably', () {
    expect(topItems([
      {'name': 'A', 'source': 'archive', 'units': 2},
      {'name': 'A', 'source': 'live', 'units': 3},
      {'name': 'B', 'source': 'archive', 'units': 4},
    ]), [(name: 'A', units: 5, archive: 2, live: 3), (name: 'B', units: 4, archive: 4, live: 0)]);
    expect([for (final r in buyList([
      {'name': 'B', 'peak': 5, 'owned': 2},
      {'name': 'A', 'peak': 4, 'owned': 1},
      {'name': 'C', 'peak': 1, 'owned': 2},
    ])) r['name']], ['A', 'B']);
  });

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
        {
          'kind': 'receive', 'item_id': 1, 'qty': 10, 'from_place': null, 'to_place': 2, 'person_id': null, 'activity_id': null, 'by_staff': null,
          'asset_id': null, 'note': null,
        });
    expect(movementRow(kind: 'issue', itemId: 1, qty: 1, from: 2, personId: 7, assetId: 40)['asset_id'], 40);
    expect(() => movementRow(kind: 'receive', itemId: 1, qty: 2, to: 2, assetId: 40), throwsArgumentError);
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

  test('the student link from "Book me" is read, never written back by staff saves', () {
    final a = Activity.fromRow({
      'id': 9, 'title': 'Consultation', 'layer': 'booking', 'kind': 'consultation', 'place_ids': [1],
      'starts_at': '2026-10-06T13:00:00Z', 'ends_at': '2026-10-06T13:30:00Z', 'status': 'requested',
      'contact_link': 'https://github.com/ana', 'purpose': 'Robot arm',
    });
    expect(a.contactLink, 'https://github.com/ana');
    expect(a.toRow().containsKey('contact_link'), isFalse);
    expect(a.toRow().containsKey('status_token'), isFalse);
  });

  test('an announcement shows longer apart than it stays', () {
    expect(TvSlide(kind: 'text', title: 'Notice', seconds: 10, every: 30).problem(), isNull);
    expect(TvSlide(kind: 'text', title: 'Notice', seconds: 10, every: 10).problem(), contains('Show every'));
    expect(TvSlide(kind: 'text', title: 'Notice', every: 30).toRow()['every_seconds'], 30);
  });

  test('TV warnings: overlapping takeovers and the same file twice', () {
    final a = TvSlide(id: 1, kind: 'media', title: 'PROTO26', mediaName: 'proto.mp4', startsOn: DateTime(2026, 9, 25),
        endsOn: DateTime(2026, 9, 25), fromTime: '17:00', toTime: '20:00', takeover: true);
    final b = TvSlide(id: 2, kind: 'media', title: 'PROTO26 copy', mediaName: 'proto.mp4', takeover: true); // no window: always
    final c = TvSlide(id: 3, kind: 'text', title: 'Late', fromTime: '20:00', toTime: '22:00', takeover: true);
    final d = TvSlide(id: 4, kind: 'text', title: 'Off', takeover: true, active: false);
    final e = TvSlide(id: 5, kind: 'text', title: 'Tomorrow', startsOn: DateTime(2026, 9, 26), endsOn: DateTime(2026, 9, 26), takeover: true);
    final w = tvWarnings([a, b, c, d]);
    expect(w[1], 'overlaps takeover "PROTO26 copy"; same file as "PROTO26 copy"');
    expect(w[2], 'overlaps takeover "PROTO26"; overlaps takeover "Late"; same file as "PROTO26"');
    expect(w[3], 'overlaps takeover "PROTO26 copy"', reason: '20:00 end and 20:00 start do not overlap');
    expect(w.containsKey(4), isFalse, reason: 'a page that is off is ignored');
    expect(tvWarnings([a, e]), isEmpty, reason: 'different days');
    expect(tvWarnings([a]), isEmpty);
  });

  test('TV status line from the node heartbeat', () {
    final now = DateTime.parse('2026-09-25T14:03:00Z');
    final good = {'built_at': '2026-09-25T14:02:00Z', 'pages': 1, 'media': 2, 'takeover': true, 'error': null, 'error_at': null,
      'playing': 'Takeover: PROTO26 until 20:00'};
    expect(tvStatusLine(good, now).ok, isTrue);
    expect(tvStatusLine(good, now).text, startsWith('Takeover: PROTO26 until 20:00 · built '));
    expect(tvStatusLine(good, DateTime.parse('2026-09-25T14:10:00Z')).ok, isFalse, reason: 'stale after 5 minutes');
    final failing = {...good, 'error': 'OSError: disk full', 'error_at': '2026-09-25T14:02:30Z'};
    expect(tvStatusLine(failing, now).text, contains('disk full'));
    expect(tvStatusLine(failing, now).ok, isFalse);
    expect(tvStatusLine(null, now).ok, isFalse);
  });

  test('TV slide: row round trip, date window, problems', () {
    final s = TvSlide.fromRow({
      'id': 3, 'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
      'from_time': '17:00:00', 'to_time': '20:00:00', 'fullscreen': true, 'takeover': true,
    });
    expect(s.toRow(), {
      'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
      'from_time': '17:00', 'to_time': '20:00', 'fullscreen': true, 'takeover': true, 'every_seconds': null, 'activity_id': null,
    });
    expect(TvSlide(kind: 'text', title: 'x', fromTime: '20:00', toTime: '17:00').problem(), contains('end time'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true).problem(), contains('needs an end'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true, toTime: '20:00').problem(), isNull);
    expect(TvSlide(kind: 'text', title: 'x', takeover: true, activityId: 56).problem(), isNull, reason: 'the event gives the end');
    expect(TvSlide.fromRow({'id': 1, 'kind': 'text', 'activity_id': 56}).toRow()['activity_id'], 56);
    expect(s.showsOn(DateTime(2026, 10, 1)), isTrue);
    expect(s.showsOn(DateTime(2026, 11, 1)), isFalse);
    expect((s..active = false).showsOn(DateTime(2026, 10, 5)), isFalse);
    expect(s.problem(), isNull);
    expect(TvSlide(kind: 'qr', title: 'x', url: 'instagram.com').problem(), contains('http'));
    expect(TvSlide(kind: 'media').problem(), contains('file'));
    expect(TvSlide(kind: 'text', title: 'x', seconds: 0).problem(), contains('Seconds'));
    final whole = TvSlide.fromRow({'id': 4, 'kind': 'media', 'media_name': 'reel.m4v', 'seconds': null});
    expect(whole.seconds, isNull, reason: 'empty seconds: the whole video');
    expect(whole.toRow()['seconds'], isNull);
    expect(whole.problem(), isNull);
    expect(TvSlide(kind: 'bio').problem(), contains('name'));
    expect(TvSlide(kind: 'text', title: 'x', startsOn: DateTime(2026, 10, 2), endsOn: DateTime(2026, 10, 1)).problem(),
        contains('end date'));
  });

  test('place codes follow the database rule', () {
    for (final ok in ['R15', 'R15-L-S3', 'B2-R1-S4', 'CUP1']) {
      expect(validCode(ok), isTrue, reason: ok);
    }
    for (final bad in ['r15', 'R15 L', 'R15--L', '-R15', 'R15-', '']) {
      expect(validCode(bad), isFalse, reason: bad);
    }
  });

  test('place tree: parents first with depth, siblings by code, orphans and loops kept', () {
    final places = [
      {'id': 3, 'code': 'R15-L-S1', 'name': 'Shelf 1', 'parent_id': 2},
      {'id': 2, 'code': 'R15-L', 'name': 'Left', 'parent_id': 1},
      {'id': 1, 'code': 'R15', 'name': 'Room 15', 'parent_id': null},
      {'id': 4, 'code': 'B2', 'name': '-2 floor', 'parent_id': null},
      {'id': 5, 'code': null, 'name': 'Orphan', 'parent_id': 99},
      {'id': 6, 'code': 'X', 'name': 'Loop a', 'parent_id': 7},
      {'id': 7, 'code': 'Y', 'name': 'Loop b', 'parent_id': 6},
    ];
    expect([for (final (p, d) in placeTree(places)) '${p['id']}:$d'], ['4:0', '1:0', '2:1', '3:2', '5:0', '6:0', '7:0']);
  });

  test('stocktake: adjust rows for the differences only, marked as stocktake', () {
    final rows = countAdjustments({1: 10, 2: 4}, {1: 8, 2: 4, 3: 1}, 9, byStaff: 5);
    expect([for (final r in rows) '${r['item_id']}:${r['qty']}'], ['1:-2', '3:1']);
    expect(rows.first['kind'], 'adjust');
    expect(rows.first['to_place'], 9);
    expect(rows.first['note'], 'stocktake');
    expect(rows.first['by_staff'], 5);
  });

  test('tagging: an untagged unit here becomes the tag; nothing untagged here means a new unit', () {
    expect([for (final r in tagRows(1, 40, 9, 3)) '${r['kind']}:${r['qty']}:${r['asset_id']}'], ['receive:1:40', 'adjust:-1:null']);
    expect([for (final r in tagRows(1, 40, 9, 0)) r['kind']], ['receive']);
  });

  test('kit: tagged units on the shelf go first, untagged make up the rest; a return brings back the held tags', () {
    final assets = [
      {'id': 1, 'item_id': 7, 'tag': 'TL-0001'},
      {'id': 2, 'item_id': 7, 'tag': 'TL-0002'},
      {'id': 3, 'item_id': 7, 'tag': 'TL-0003'},
      {'id': 4, 'item_id': 7, 'tag': 'TL-0004'},
    ];
    final where = [
      {'asset_id': 1, 'place_id': 9, 'person_id': null},
      {'asset_id': 2, 'place_id': 9, 'person_id': null},
      {'asset_id': 3, 'place_id': 9, 'person_id': null},
      {'asset_id': 4, 'place_id': 5, 'person_id': null}, // on another shelf: not picked
    ];
    final (rows, tags) = kitRows('issue', [{'item_id': 7, 'qty': 5}], 9, 20, assets, where, activityId: 3);
    expect(tags, ['TL-0001', 'TL-0002', 'TL-0003']);
    expect([for (final r in rows) '${r['qty']}:${r['asset_id']}:${r['from_place']}'], ['1:1:9', '1:2:9', '1:3:9', '2:null:9']);
    expect(rows.every((r) => r['activity_id'] == 3 && r['person_id'] == 20), isTrue);

    final held = [
      {'asset_id': 2, 'place_id': null, 'person_id': 20},
    ];
    final (back, backTags) = kitRows('return', [{'item_id': 7, 'qty': 2}], 9, 20, assets, held);
    expect(backTags, ['TL-0002']);
    expect([for (final r in back) '${r['kind']}:${r['qty']}:${r['asset_id']}:${r['to_place']}'], ['return:1:2:9', 'return:1:null:9']);
  });

  test('found here: moved from its shelf, returned from a person, received from nowhere, nothing when already here', () {
    final a = {'id': 40, 'item_id': 7};
    String kind(Map<String, dynamic>? w) => foundRows(a, w, 9).map((r) => '${r['kind']}:${r['from_place']}:${r['person_id']}').join();
    expect(kind({'place_id': 5, 'person_id': null}), 'move:5:null');
    expect(kind({'place_id': null, 'person_id': 20}), 'return:null:20');
    expect(kind(null), 'receive:null:null');
    expect(kind({'place_id': 9, 'person_id': null}), '');
    expect(foundRows(a, null, 9).single['note'], 'stocktake');
  });

  test('demand: overlapping approved kits that ask for more than the lab owns', () {
    final a = Activity(id: 1, title: 'Workshop', start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12));
    final club = Activity(id: 2, title: 'Club', start: DateTime(2026, 10, 20, 11), end: DateTime(2026, 10, 20, 13));
    final later = Activity(id: 3, title: 'Evening', start: DateTime(2026, 10, 20, 18), end: DateTime(2026, 10, 20, 19));
    final others = [
      (club, {7: 4}),
      (later, {7: 20}),
    ];
    expect(demandWarnings(a, {7: 10}, others, {7: 12}, {7: 'ESP32'}),
        ['2026-10-20 10:00: ESP32 needed 14 (this 10, Club 4), the lab has 12']);
    expect(demandWarnings(a, {7: 8}, others, {7: 12}, {7: 'ESP32'}), isEmpty, reason: '8 + 4 fits in 12');
    expect(demandWarnings(a, {7: 30}, [], {7: 12}, {7: 'ESP32'}), isEmpty, reason: 'alone it is the shortage check at issue time');
  });

  test('Wall slide: row round trip and problems', () {
    final s = WallSlide.fromRow({
      'id': 4, 'mode': 'videowall', 'title': 'PROTO26', 'media_names': ['proto.mp4'], 'seconds': null, 'cycle_seconds': 9,
      'fit': 'fill', 'show_title': true, 'credits': ' Lab ', 'logo': true, 'matte': 40, 'position': 1, 'active': true,
      'starts_on': '2026-10-01', 'ends_on': null, 'from_time': '17:00:00', 'to_time': '20:00:00', 'takeover': true,
      'every_seconds': null, 'activity_id': null,
    });
    expect(s.toRow(), {
      'mode': 'videowall', 'title': 'PROTO26', 'media_names': ['proto.mp4'], 'seconds': null, 'cycle_seconds': null,
      'fit': 'fill', 'show_title': true, 'credits': 'Lab', 'logo': true, 'matte': 40, 'position': 1, 'active': true,
      'starts_on': '2026-10-01', 'ends_on': null, 'from_time': '17:00', 'to_time': '20:00', 'takeover': true,
      'every_seconds': null, 'activity_id': null,
    });
    expect(s.problem(), isNull);
    expect(WallSlide(mode: 'videowall').problem(), contains('one file'));
    expect(WallSlide(mode: 'mosaic').problem(), isNull, reason: 'no files ticked = every file');
    expect(WallSlide(mode: 'mosaic', takeover: true).problem(), contains('needs an end'));
    expect(WallSlide(mode: 'mosaic', takeover: true, activityId: 3).problem(), isNull);
    expect(WallSlide(mode: 'mosaic', seconds: 20, every: 10).problem(), contains('gap'));
    expect(WallSlide(mode: 'mosaic', fromTime: '20:00', toTime: '17:00').problem(), contains('end time'));
    expect(WallSlide(mode: 'mosaic', matte: 500).problem(), contains('Matte'));
  });

  test('Wall status line and grid', () {
    final now = DateTime.parse('2026-10-01T10:00:30Z');
    final good = {'seen_at': '2026-10-01T10:00:20Z', 'playing': 'Videowall: proto.mp4',
      'screens': {'a1': {'on': true}, 'b1': {'on': false}}, 'error': null, 'error_at': null};
    expect(wallStatusLine(good, now).text, 'Videowall: proto.mp4 · 1/2 screens on');
    expect(wallStatusLine(good, now).ok, isTrue);
    expect(wallStatusLine(good, DateTime.parse('2026-10-01T10:01:25Z')).ok, isFalse, reason: 'stale after 60 s');
    final failing = {...good, 'error': 'URLError: offline', 'error_at': '2026-10-01T10:00:20Z'};
    expect(wallStatusLine(failing, now).text, contains('offline'));
    expect(wallStatusLine(failing, now).ok, isFalse);
    expect(wallStatusLine(null, now).ok, isFalse);
    expect(wallStaleLine(good, now), isNull);
    final ten = {...good, 'screens': {for (var i = 0; i < 10; i++) 'a${i + 1}': {'on': true}}};
    expect(wallStaleLine(ten, now.add(const Duration(seconds: 61))),
        'Wall off or server down since 11:00 · last 10/10 screens on');
    expect(wallStaleLine(null, now), 'Wall server has not reported yet');
    expect(wallGrid(['b2', 'a1', 'e1', 'a2', 'c1', 'b1']), [['a1', 'b1', 'c1', 'e1'], ['a2', 'b2']]);
  });

  test('Pi power flags', () {
    expect(piPower('0x0'), isNull);
    expect(piPower(null), isNull);
    expect(piPower('0x50000'), 'under-voltage since boot');
    expect(piPower('0x50005'), 'under-voltage now, throttled now');
    expect(piPower('0x80000'), 'hit heat limit since boot');
    expect(piPower('0x80008'), 'too hot now');
  });
}
