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
      'from_time': '17:00', 'to_time': '20:00', 'fullscreen': true, 'takeover': true,
    });
    expect(TvSlide(kind: 'text', title: 'x', fromTime: '20:00', toTime: '17:00').problem(), contains('end time'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true).problem(), contains('needs an end'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true, toTime: '20:00').problem(), isNull);
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
}
