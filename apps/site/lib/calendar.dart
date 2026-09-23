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
