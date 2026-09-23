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
