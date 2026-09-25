// Run: dart test (from apps/site). Calendar asserts are ported 1:1 from iade-lab-schedule/tests/test_calendar.mjs.
import 'package:site/book.dart';
import 'package:site/calendar.dart';
import 'package:site/ideas.dart';
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

  test('book me: slots grouped by local day in time order', () {
    Slot at(String iso) => (iso: iso, start: DateTime.parse(iso), end: DateTime.parse(iso).add(const Duration(minutes: 30)));
    final g = byDay([at('2026-10-02T15:00:00'), at('2026-10-01T14:30:00'), at('2026-10-01T14:00:00')]);
    expect(g.keys, ['2026-10-01', '2026-10-02']);
    expect([for (final s in g['2026-10-01']!) s.iso], ['2026-10-01T14:00:00', '2026-10-01T14:30:00']);
  });

  test('book me: form checks mirror request_consultation()', () {
    String? check({String name = 'Ana', String email = 'ana@example.com', String need = 'Help with a 3D print'}) =>
        formProblem(name: name, email: email, need: need);
    expect(check(), isNull);
    expect(check(need: 'LED'), isNull);
    expect(check(name: 'A'), contains('name'));
    expect(check(email: 'ana@'), contains('email'));
    expect(check(need: 'hi'), contains('3–300'));
    expect(check(need: 'x' * 301), contains('3–300'));
  });

  test('ideas: form checks mirror submit_idea()', () {
    String? check({String body = 'A plant game with real sensors', String canBring = '', String link = ''}) =>
        ideaProblem(name: 'Ana', email: 'ana@example.com', body: body, canBring: canBring, link: link);
    expect(check(), isNull);
    expect(check(body: 'short'), contains('10–4000'));
    expect(check(canBring: 'x' * 501), contains('500'));
    expect(check(link: 'nope'), contains('http'));
  });

  test('ideas: status view hides contact until both connect', () {
    final v = IdeaView.fromJson({
      'idea': {'body': 'b', 'status': 'approved', 'processed': true, 'title': 'T', 'summary': 'S', 'keywords': ['k']},
      'matches': [
        {'other': 2, 'kind': 'complementary', 'reason': 'r', 'title': 'Robot', 'first_name': 'Ben', 'i_connected': true, 'they_connected': false, 'contact': null},
        {'other': 3, 'kind': 'similar', 'reason': 'r', 'title': 'Game', 'first_name': 'Cat', 'i_connected': true, 'they_connected': true,
         'contact': {'email': 'cat@example.com', 'link': null}},
      ],
    });
    expect(v.matches.first.email, isNull);
    expect(v.matches.last.email, 'cat@example.com');
    expect(v.stage, contains('Your matches'));
    expect(IdeaView.fromJson({'idea': {'body': 'b', 'status': 'new', 'processed': false}, 'matches': []}).stage, contains('AI'));
  });

  test('now line: before the first item that has not started', () {
    Lesson at(String start, String end) => Lesson(date: '2026-09-25', start: start, end: end, course: 'x');
    final day = [at('09:00', '11:00'), at('11:00', '13:30'), at('14:00', '17:00')];
    expect(nowIndex(day, '08:00'), 0);
    expect(nowIndex(day, '12:10'), 2, reason: 'after the lesson in progress');
    expect(nowIndex(day, '14:00'), 3, reason: 'a lesson starting now has started');
    expect(nowIndex([], '12:00'), 0);
  });
}
