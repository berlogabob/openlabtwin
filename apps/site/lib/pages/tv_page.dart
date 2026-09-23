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
