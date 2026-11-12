// Run: flutter test (from apps/office)
import 'package:flutter_test/flutter_test.dart';
import 'package:office/report_logic.dart';

void main() {
  final people = [
    {'id': 1, 'name': 'Ana Silva', 'email': 'ana@school.edu'},
    {'id': 2, 'name': 'João Costa', 'email': ''},
  ];

  final itemNames = {10: 'Laser cutter', 11: 'Oscilloscope'};

  // An equipment booking inside the window, requested by a known person.
  // An equipment booking outside the window (filtered out).
  // A non-equipment booking inside the window (filtered out).
  final activities = [
    {
      'id': 2,
      'title': 'In window',
      'kind': 'equipment',
      'status': 'approved',
      'starts_at': '2026-03-15T09:00:00Z',
      'requester_id': 1,
      'requester_display': null,
    },
    {
      'id': 4,
      'title': 'Too early',
      'kind': 'equipment',
      'status': 'approved',
      'starts_at': '2026-01-05T09:00:00Z',
      'requester_id': 2,
      'requester_display': null,
    },
    {
      'id': 5,
      'title': 'Not kit',
      'kind': 'club',
      'status': 'approved',
      'starts_at': '2026-03-20T09:00:00Z',
      'requester_id': 1,
      'requester_display': null,
    },
  ];

  test('filter keeps only equipment bookings inside the period, sorted', () {
    final rows = bookingReport(
      activities: activities,
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-06',
      to: '2026-12-31',
    );
    expect([for (final r in rows) r['id']], [2]);

    final rows2 = bookingReport(
      activities: activities,
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-06',
      to: '2026-03-14',
    );
    expect(rows2, isEmpty, reason: 'the window excludes everything');

    final rows3 = bookingReport(
      activities: activities,
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-03-15',
      to: '2026-03-15',
    );
    expect(
      [for (final r in rows3) r['id']],
      [2],
      reason: 'bounds are inclusive',
    );
  });

  test('issued, returned, outstanding and the three states', () {
    final acts = [
      {
        'id': 1,
        'title': 'All issued',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': null,
        'requester_display': 'Walk-in',
      },
      {
        'id': 2,
        'title': 'Fully returned',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-02T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
      {
        'id': 3,
        'title': 'Still out',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-03T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
    ];
    final moves = [
      {'activity_id': 2, 'kind': 'issue', 'qty': 2},
      {'activity_id': 2, 'kind': 'return', 'qty': 2},
      {'activity_id': 3, 'kind': 'issue', 'qty': 4},
      {'activity_id': 3, 'kind': 'return', 'qty': 1},
      // an unrelated movement kind that must be ignored
      {'activity_id': 3, 'kind': 'receive', 'qty': 99},
    ];
    final rows = bookingReport(
      activities: acts,
      lines: [],
      movements: moves,
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    final byId = {for (final r in rows) r['id']: r};
    expect(
      [
        byId[1]!['issued'],
        byId[1]!['returned'],
        byId[1]!['outstanding'],
        byId[1]!['state'],
      ],
      [0, 0, 0, 'not issued'],
    );
    expect(
      [
        byId[2]!['issued'],
        byId[2]!['returned'],
        byId[2]!['outstanding'],
        byId[2]!['state'],
      ],
      [2, 2, 0, 'returned'],
    );
    expect(
      [
        byId[3]!['issued'],
        byId[3]!['returned'],
        byId[3]!['outstanding'],
        byId[3]!['state'],
      ],
      [4, 1, 3, 'outstanding'],
    );
  });

  test('outstanding never goes below zero', () {
    final acts = [
      {
        'id': 1,
        'title': 'Over returned',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
    ];
    final moves = [
      {'activity_id': 1, 'kind': 'issue', 'qty': 1},
      {'activity_id': 1, 'kind': 'return', 'qty': 5},
    ];
    final rows = bookingReport(
      activities: acts,
      lines: [],
      movements: moves,
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    expect(rows[0]['outstanding'], 0);
    expect(rows[0]['state'], 'returned');
  });

  test('requester falls back to the display name when no person link', () {
    final acts = [
      {
        'id': 1,
        'title': 'Linked',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': 1,
        'requester_display': 'Ignore me',
      },
      {
        'id': 2,
        'title': 'Display',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-02T09:00:00Z',
        'requester_id': null,
        'requester_display': 'Walk-in Guest',
      },
      {
        'id': 3,
        'title': 'Blank',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-03T09:00:00Z',
        'requester_id': 2,
        'requester_display': null,
      },
    ];
    final rows = bookingReport(
      activities: acts,
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    final byId = {for (final r in rows) r['id']: r};
    expect(byId[1]!['requester'], 'Ana Silva');
    expect(byId[1]!['email'], 'ana@school.edu');
    expect(byId[2]!['requester'], 'Walk-in Guest');
    expect(byId[2]!['email'], '');
    expect(byId[3]!['requester'], 'João Costa');
    expect(byId[3]!['email'], '');
  });

  test('items text joins names and quantities in item id order', () {
    final acts = [
      {
        'id': 1,
        'title': 'Kit',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
    ];
    final lines = [
      {'activity_id': 1, 'item_id': 11, 'qty': 2.0},
      {'activity_id': 1, 'item_id': 10, 'qty': 1},
      {'activity_id': 1, 'item_id': 99, 'qty': 3.5}, // no name: item 99
    ];
    final rows = bookingReport(
      activities: acts,
      lines: lines,
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    expect(rows[0]['items'], 'Laser cutter x1; Oscilloscope x2; item 99 x3.5');
  });

  test('csv quotes fields with a comma and a quote, doubles the quotes', () {
    final rows = bookingReport(
      activities: [
        {
          'id': 1,
          'title': 'Work, Shop "A"',
          'kind': 'equipment',
          'status': 'approved',
          'starts_at': '2026-03-01T09:00:00Z',
          'requester_id': null,
          'requester_display': null,
        },
      ],
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    final csv = reportCsv(rows);
    final lines_ = csv.split('\n');
    expect(lines_.first, reportColumns.join(','));
    expect(
      lines_[1],
      '1,2026-03-01,"Work, Shop ""A""",,,approved,,0,0,0,not issued',
    );
    // header then one data line
    expect(lines_.length, 3);
    expect(
      lines_.last,
      isEmpty,
      reason: 'trailing newline leaves an empty final segment',
    );
    expect(
      reportCsv([
        {'title': 'a\rb\nc'},
      ]),
      contains('"a\rb\nc"'),
    );
  });

  test('rows sort by start time then id', () {
    final acts = [
      {
        'id': 9,
        'title': 'Later',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-10T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
      {
        'id': 1,
        'title': 'Earlier',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
      {
        'id': 2,
        'title': 'Same time higher id',
        'kind': 'equipment',
        'status': 'approved',
        'starts_at': '2026-03-01T09:00:00Z',
        'requester_id': null,
        'requester_display': null,
      },
    ];
    final rows = bookingReport(
      activities: acts,
      lines: [],
      movements: [],
      people: people,
      itemNames: itemNames,
      from: '2026-01-01',
      to: '2026-12-31',
    );
    expect([for (final r in rows) r['id']], [1, 2, 9]);
  });

  test('whole numbers print without a trailing .0', () {
    final csv = reportCsv([
      {
        'id': 1,
        'date': '2026-03-01',
        'title': 'x',
        'requester': '',
        'email': '',
        'status': 'approved',
        'items': '',
        'issued': 2,
        'returned': 1,
        'outstanding': 1,
        'state': 'outstanding',
      },
    ]);
    expect(csv.contains('2,1,1'), isTrue);
    expect(csv.contains('2.0'), isFalse);
  });
}
