// Lab TV (GitHub Pages): the same layout as the edge node's showcase TV. Day and rooms on a top line, today's rooms
// stacked in the left third, and on the right the Book me and Idea hub QR codes and upcoming events in turn. Rooms come from the URL
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
  int slide = DateTime.now().millisecondsSinceEpoch ~/ 10000; // from the clock: every screen shows the same slide

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final picked = Filters.parse(web.window.location.search).values['room'] ?? const [];
    if (picked.isNotEmpty) rooms = picked;
    // Timer starts after the first load: checks the clock each second (a new slide every 10 s, the same on every
    // screen), data reloads every 5 minutes.
    _load().whenComplete(() => timer = Timer.periodic(const Duration(seconds: 1), (t) {
          final n = DateTime.now().millisecondsSinceEpoch ~/ 10000;
          if (n != slide) {
            setState(() {
              now = DateTime.now();
              slide = n;
            });
            _fitSchedule();
          }
          if (t.tick % 300 == 0) _load();
        }));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// A busy day: shrink the schedule column's text until every card fits, down to 55%.
  void _fitSchedule() => Timer(const Duration(milliseconds: 50), () {
        final aside = web.document.querySelector('.tv-schedule') as web.HTMLElement?;
        if (aside == null) return;
        for (var size = 100; size >= 55; size -= 5) {
          aside.style.fontSize = '$size%';
          if (aside.scrollHeight <= aside.clientHeight) return;
        }
      });

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('data/all.json'), headers: {'Cache-Control': 'no-cache'});
      final all = parseLessons(utf8.decode(r.bodyBytes));
      setState(() {
        lessons = all;
        loaded = DateTime.now();
      });
      _fitSchedule();
    } catch (_) {} // keep showing the last good data; the footer shows how old it is
  }

  @override
  Component build(BuildContext context) {
    final day = iso(now);
    final clock = '${'${now.hour}'.padLeft(2, '0')}:${'${now.minute}'.padLeft(2, '0')}';
    String short(String room) => room.replaceFirst(RegExp(r' \(Oriente\)$'), '');
    final slides = <({String? src, String when, String title, String body})>[
      (src: 'qr/book.svg', when: '', title: 'Book time in the lab', body: ''),
      (src: 'qr/ideas.svg', when: '', title: 'Share a project idea', body: ''),
      for (final e in lessons.where((l) => l.layer == 'event' && l.date.compareTo(day) >= 0 && l.date.compareTo(shift('day', day, 14)) <= 0))
        (src: null, when: '${dayName(e.date)} · ${e.start}–${e.end}', title: e.course,
         body: [e.rooms.join(', '), e.note].where((x) => x.isNotEmpty).join(' · ')),
    ];
    final s = slides[slide % slides.length];
    return div(classes: 'tv', [
      header([
        span(classes: 'tv-day', [.text(dayName(day))]),
        span(classes: 'tv-room-names', [.text(rooms.map(short).join(' · '))]),
      ]),
      div(classes: 'tv-schedule', [
        for (final room in rooms)
          section([
            if (rooms.length > 1) h2([.text(short(room))]), // one room: its name is already on the top line
            ..._today(room, day, clock),
          ]),
      ]),
      div(classes: 'tv-stage', [
        div(classes: 'tv-frame', [
          if (s.src != null) img(src: s.src!, alt: s.title),
          div(classes: 'text', [
            if (s.when.isNotEmpty) p(classes: 'when', [.text(s.when)]),
            h1([.text(s.title)]),
            if (s.body.isNotEmpty) p(classes: 'body', [.text(s.body)]),
          ]),
        ]),
      ]),
      footer([
        p([.text(loaded == null ? 'Loading…' : 'updated ${'${loaded!.hour}'.padLeft(2, '0')}:${'${loaded!.minute}'.padLeft(2, '0')}')]),
      ]),
    ]);
  }

  List<Component> _today(String room, String day, String clock) {
    final items = lessons.where((l) => l.date == day && l.rooms.contains(room)).toList()
      ..sort((x, y) => x.start.compareTo(y.start));
    if (items.isEmpty) return [p(classes: 'empty', [.text('Free all day')])];
    final line = nowIndex(items, clock);
    return [
      for (final (i, l) in items.indexed) ...[
        if (i == line) div(classes: 'now-line', [span([.text(clock)])]),
        article(
          classes: [
            if (l.layer != 'lesson') l.layer,
            if (l.end.compareTo(clock) <= 0) 'past',
            if (l.start.compareTo(clock) <= 0 && l.end.compareTo(clock) > 0) 'now',
          ].join(' '),
          [
            p(classes: 'course', [span(classes: 'time', [.text('${l.start}–${l.end}')]), .text(l.course)]),
            if (l.teachers.isNotEmpty || l.groups.isNotEmpty)
              p(classes: 'who', [.text([l.teachers.join(', '), l.groups.join(', ')].where((x) => x.isNotEmpty).join(' · '))]),
          ],
        ),
      ],
      if (line == items.length) div(classes: 'now-line', [span([.text(clock)])]),
    ];
  }
}
