// Main page: loads data/all.json in the browser, filters it, keeps filters and the view in the URL.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../calendar.dart';
import '../schedule.dart';

const maxList = 300; // ponytail: render cap, add paging if people need to scroll past it
const maxGrid = 150; // ponytail: a whole campus week is unreadable as a grid
const maxFavs = 5;

String today() => iso(DateTime.now()); // ponytail: the viewer's local date; the lab and its TV are in Lisbon

// Per-browser conveniences; the page works the same if storage is blocked.
String? load(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void save(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

@client
class SchedulePage extends StatefulComponent {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => SchedulePageState();
}

class SchedulePageState extends State<SchedulePage> {
  List<Lesson>? lessons;
  String? error;
  Map<String, Set<String>> known = {};
  Filters f = Filters();
  final drafts = <String, String>{}; // text typed but not yet picked, per field
  bool open = true;
  List<Map<String, dynamic>> favs = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('data/all.json'), headers: {'Cache-Control': 'no-cache'});
      final all = parseLessons(utf8.decode(r.bodyBytes));
      final q = web.window.location.search;
      setState(() {
        lessons = all;
        known = knownValues(all);
        f = q.isEmpty ? Filters(values: {'room': [defaultRoom]}, from: today()) : Filters.parse(q);
        if (f.date.isEmpty) f.date = today();
        open = load('filtersOpen') != 'false';
        favs = [for (final x in jsonDecode(load('favs') ?? '[]') as List) x as Map<String, dynamic>];
      });
    } catch (_) {
      setState(() => error = 'Could not load the timetable data.');
    }
  }

  void _update(void Function() change) {
    setState(change);
    web.window.history.replaceState(null, '', '?${f.toQuery()}');
  }

  Map<String, List<String>> get _wanted => {
        for (final k in fields.keys)
          k: [...?f.values[k], if ((drafts[k] ?? '').isNotEmpty) drafts[k]!]
      };

  void _pick(String field, String value) => _update(() {
        final vs = f.values.putIfAbsent(field, () => []);
        if (value.isNotEmpty && !vs.contains(value)) vs.add(value);
        drafts.remove(field);
      });

  (String, String) _range(String name) => switch (name) {
        'today' => (today(), today()),
        'week' => (today(), sundayOf(today())),
        _ => ('', ''),
      };

  String _describe(Filters g) => [
        for (final k in fields.keys) ...?g.values[k],
        if (g.from.isNotEmpty) 'from ${g.from}',
        if (g.to.isNotEmpty) 'to ${g.to}',
      ].join(' · ');

  void _saveFav() {
    final g = f.copy()..date = '';
    if (g.from == today()) g.from = ''; // "from today" should stay today, not freeze the date
    final query = g.toQuery();
    if (favs.length >= maxFavs || favs.any((x) => x['query'] == query)) return;
    final name = web.window.prompt('Name this favourite', _describe(g).isEmpty ? 'Everything' : _describe(g));
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    setState(() => favs.add({'name': trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed, 'query': query}));
    save('favs', jsonEncode(favs));
  }

  void _openFav(String query) => _update(() {
        f = Filters.parse(query);
        if (f.date.isEmpty) f.date = today();
        if (f.from.isEmpty && !query.contains('from=') && f.view == 'list' && f.to.isEmpty) f.from = today();
        drafts.clear();
      });

  @override
  Component build(BuildContext context) {
    final all = lessons;
    return div([
      header([
        h1([a(href: './', [.text('IADE Schedule')])]),
        if (all != null) _nav(),
      ]),
      if (all != null) _filters(all),
      main_([
        if (error != null)
          p(classes: 'empty', [.text(error!)])
        else if (all == null)
          p(classes: 'empty', [.text('Loading…')])
        else
          ..._results(all),
      ]),
      footer([
        p([
          .text('Lab: '),
          a(href: 'tv/', [.text('TV screen')]),
          .text(' · '),
          a(href: 'book/', [.text('book a consultation')]),
          .text(' · '),
          a(href: 'calendar/lab.ics', [.text('calendar (.ics)')]),
          .text(' · '),
          a(href: 'https://horariosturmas.europeia.pt/UE_IADE/HorariosTurmas/', [.text('official IADE timetable')]),
        ]),
        p([.text('Unofficial timetable view. Always verify critical scheduling information with the official IADE timetable.')]),
      ]),
    ]);
  }

  Component _nav() {
    Component btn(String label, bool on, void Function() tap) =>
        button(type: ButtonType.button, classes: on ? 'on' : null, onClick: tap, [.text(label)]);
    return nav([
      span(id: 'views', [
        for (final v in const ['list', 'day', 'week', 'month'])
          btn(v[0].toUpperCase() + v.substring(1), f.view == v, () => _update(() {
                if (f.view == 'list' && v != 'list' && f.from.isNotEmpty) f.date = f.from;
                f.view = v;
              })),
      ]),
      if (f.view == 'list')
        span(id: 'ranges', [
          for (final (name, label) in const [('today', 'Today'), ('week', 'This week'), ('all', 'All dates')])
            btn(label, (f.from, f.to) == _range(name), () => _update(() {
                  final r = _range(name);
                  f.from = r.$1;
                  f.to = r.$2;
                })),
        ])
      else
        span(id: 'period', [
          btn('‹', false, () => _update(() => f.date = shift(f.view, f.date, -1))),
          btn('Today', false, () => _update(() => f.date = today())),
          btn('›', false, () => _update(() => f.date = shift(f.view, f.date, 1))),
          span(id: 'period-label', [.text(periodLabel(f.view, f.date))]),
        ]),
    ]);
  }

  Component _filters(List<Lesson> all) {
    final (from, to) = f.view == 'list' ? (f.from, f.to) : periodRange(f.view, f.date);
    final options = run(all, _wanted, known, from, to).options;
    final desc = _describe(f);
    return details(
      id: 'filters-box',
      open: open,
      events: {
        'toggle': (e) {
          open = (e.target as web.HTMLDetailsElement).open;
          save('filtersOpen', '$open');
        },
      },
      [
        summary([
          span(id: 'summary-text', [.text(desc.isEmpty ? 'Filters' : 'Filters: $desc')]),
          span(id: 'favs', [
            for (final fav in favs)
              span(classes: '?${fav['query']}' == '?${f.toQuery()}' ? 'fav on' : 'fav', [
                button(type: ButtonType.button, onClick: () => _openFav(fav['query'] as String), [.text(fav['name'] as String)]),
                button(
                  type: ButtonType.button,
                  classes: 'fav-x',
                  attributes: {'aria-label': 'Remove favourite ${fav['name']}'},
                  onClick: () {
                    setState(() => favs.remove(fav));
                    save('favs', jsonEncode(favs));
                  },
                  [.text('×')],
                ),
              ]),
            button(
              type: ButtonType.button,
              id: 'fav-save',
              disabled: favs.length >= maxFavs,
              attributes: {'title': favs.length >= maxFavs ? 'Up to $maxFavs favourites. Remove one first.' : 'Save the current filters'},
              onClick: _saveFav,
              [.text('☆ Save as favourite')],
            ),
          ]),
        ]),
        div(id: 'filters', [
          for (final k in fields.keys)
            label([
              .text(labels[k]!),
              span(classes: 'chips', [
                for (final v in f.values[k] ?? const <String>[])
                  span(classes: 'chip', [
                    .text(v),
                    button(
                      type: ButtonType.button,
                      attributes: {'aria-label': 'Remove $v'},
                      onClick: () => _update(() => f.values[k]!.remove(v)),
                      [.text('×')],
                    ),
                  ]),
                input<String>(
                  type: InputType.text,
                  value: drafts[k] ?? '',
                  attributes: {'list': '$k-list', 'placeholder': (f.values[k] ?? const []).isEmpty ? 'any' : 'or…', 'autocomplete': 'off'},
                  onInput: (v) => known[k]!.contains(v) ? _pick(k, v) : setState(() => drafts[k] = v),
                  onChange: (v) => _pick(k, v.trim()),
                ),
              ]),
              datalist(id: '$k-list', [for (final v in options[k]!) option(value: v, [])]),
            ]),
          if (f.view == 'list') ...[
            label(classes: 'date-field', [
              .text('From'),
              input<String>(type: InputType.date, value: f.from, onInput: (v) => _update(() => f.from = v)),
            ]),
            label(classes: 'date-field', [
              .text('To'),
              input<String>(type: InputType.date, value: f.to, onInput: (v) => _update(() => f.to = v)),
            ]),
          ],
        ]),
      ],
    );
  }

  List<Component> _results(List<Lesson> all) {
    final (from, to) = f.view == 'list' ? (f.from, f.to) : periodRange(f.view, f.date);
    final hits = run(all, _wanted, known, from, to).hits;
    return switch (f.view) {
      'list' => _list(hits),
      'month' => [_month(hits)],
      _ => _grid(hits, f.view == 'day' ? [f.date] : datesOf(from, to)),
    };
  }

  String _meta(Lesson l) => [l.rooms.join(', '), l.teachers.join(', ')].where((x) => x.isNotEmpty).join(' · ');

  String _details(Lesson l) => [l.course, l.rooms.join(', '), l.teachers.join(', '), l.groups.join(', '), l.type, l.note]
      .where((x) => x.isNotEmpty)
      .join(' · ');

  List<Component> _list(List<Lesson> hits) {
    if (hits.isEmpty) return [p(classes: 'empty', [.text('No lessons match these filters.')])];
    final sections = <Component>[];
    for (final date in {for (final l in hits.take(maxList)) l.date}) {
      sections.add(section([
        h2([.text(dayName(date))]),
        for (final l in hits.take(maxList).where((l) => l.date == date))
          article(classes: l.layer == 'lesson' ? null : l.layer, [
            p(classes: 'time', [.text('${l.start}–${l.end}')]),
            p(classes: 'course', [.text(l.course)]),
            for (final m in [l.rooms.join(', '), l.teachers.join(', '), l.groups.join(', '), l.type, l.note])
              if (m.isNotEmpty) p([.text(m)]),
          ]),
      ]));
    }
    if (hits.length > maxList) {
      sections.add(p(classes: 'empty', [.text('Showing the first $maxList of ${hits.length} lessons. Narrow the filters to see more.')]));
    }
    return sections;
  }

  // Day and week: hour rows down the side, one column per day, overlapping lessons side by side.
  List<Component> _grid(List<Lesson> hits, List<String> dates) {
    var first = 8 * 60, last = 20 * 60;
    for (final l in hits) {
      if (minutes(l.start) < first) first = minutes(l.start);
      if (minutes(l.end) > last) last = minutes(l.end);
    }
    first = first ~/ 60 * 60;
    last = (last + 59) ~/ 60 * 60;
    final now = today();
    return [
      if (hits.length > maxGrid) p(classes: 'empty', [.text('${hits.length} lessons in this period. Narrow the filters to read the grid.')]),
      div(classes: 'cal', attributes: {'style': '--days:${dates.length};--rows:${(last - first) ~/ 60}'}, [
        div(classes: 'cal-head', [
          div(classes: 'cal-corner', []),
          for (final d in dates)
            div(classes: d == now ? 'cal-day on' : 'cal-day', [.text('${weekday(d).substring(0, 3)} ${int.parse(d.substring(8))}')]),
        ]),
        div(classes: 'cal-body', [
          div(classes: 'cal-gutter', [
            for (var h = first ~/ 60; h < last ~/ 60; h++) div(classes: 'cal-hour', [.text('${'$h'.padLeft(2, '0')}:00')]),
          ]),
          for (final d in dates)
            div(classes: d == now ? 'cal-col on' : 'cal-col', [
              for (final x in layout(hits.where((l) => l.date == d).toList(), first, last))
                div(
                  classes: x.lesson.layer == 'lesson' ? 'ev' : 'ev ${x.lesson.layer}',
                  attributes: {
                    'style': 'top:${x.top}%;height:${x.height}%;left:${x.left}%;width:${x.width}%',
                    'title': _details(x.lesson),
                  },
                  [
                    span(classes: 'ev-time', [.text('${x.lesson.start}–${x.lesson.end}')]),
                    span(classes: 'ev-course', [.text(x.lesson.course)]),
                    span(classes: 'ev-meta', [.text(_meta(x.lesson))]),
                  ],
                ),
            ]),
        ]),
      ]),
    ];
  }

  Component _month(List<Lesson> hits) {
    final (from, to) = periodRange('month', f.date);
    final now = today();
    return div(classes: 'month', [
      for (final name in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) div(classes: 'month-head', [.text(name)]),
      for (final d in monthCells(f.date))
        div(
          classes: [
            'month-cell',
            if (d.compareTo(from) < 0 || d.compareTo(to) > 0) 'other',
            if (d == now) 'on',
          ].join(' '),
          events: {
            'click': (_) => _update(() {
                  f.view = 'day';
                  f.date = d;
                }),
          },
          [
            div(classes: 'month-num', [.text('${int.parse(d.substring(8))}')]),
            for (final l in hits.where((l) => l.date == d).take(3))
              div(
                classes: l.layer == 'lesson' ? 'month-ev' : 'month-ev ${l.layer}',
                attributes: {'title': _details(l)},
                [span(classes: 'ev-time', [.text(l.start)]), span(classes: 'ev-course', [.text(l.course)])],
              ),
            if (hits.where((l) => l.date == d).length > 3)
              div(classes: 'month-more', [.text('+${hits.where((l) => l.date == d).length - 3} more')]),
          ],
        ),
    ]);
  }
}
