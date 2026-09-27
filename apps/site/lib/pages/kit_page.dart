// Equipment request form (/kit/): who, what for (class, lab work, take home), when, and a checklist from the lab's
// catalogue. Optional everywhere else: a booking never needs one. Ends with the private status link, as Book me does.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../book.dart';
import '../calendar.dart';
import '../kit.dart';
import '../pick.dart';
import '../schedule.dart' show parseLessons;

@client
class KitPage extends StatefulComponent {
  const KitPage({super.key});

  @override
  State<KitPage> createState() => KitPageState();
}

class KitPageState extends State<KitPage> {
  List<Item>? items;
  List<String> courseList = [];
  final picked = <int, int>{}; // item id -> how many
  final coursesPicked = <String>[];
  String name = '', email = '', number = '', use = 'class', other = '', website = '', itemDraft = '', courseDraft = '';
  String day = iso(DateTime.now().add(const Duration(days: 1))), from = '10:00', to = '12:00', backDay = '', until = '';
  String? error, token;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await rpc('equipment_catalogue', {}) as List;
      setState(() => items = catalogue(rows));
    } catch (e) {
      setState(() => error = 'Could not load the equipment list: $e');
    }
    try {
      // the same timetable the schedule page reads (links resolve from the <base>, the site root): its courses are the list
      final r = await http.get(Uri.parse('data/all.json'), headers: {'Cache-Control': 'no-cache'});
      setState(() => courseList = courses(parseLessons(utf8.decode(r.bodyBytes))));
    } catch (_) {} // typing a course still works without the list
  }

  String get course => coursesPicked.join('; ');

  // a take-home loan is picked up and brought back on two days; a class or lab work is one time slot
  DateTime? get _start => use == 'home' ? localAt(day, '10:00') : localAt(day, from);
  DateTime? get _end => use == 'home' ? localAt(backDay, '18:00') : localAt(day, to);

  Future<void> _send() async {
    final problem = kitProblem(
        name: name, email: email, number: number, use: use, start: _start, end: _end,
        repeatUntil: use == 'class' ? until : '', picked: picked, other: other, course: course);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('request_equipment', requestArgs(
          name: name, email: email, number: number, use: use, course: course, start: _start!, end: _end!,
          repeatUntil: use == 'class' ? until : '', picked: picked, other: other, website: website));
      setState(() => token = t as String);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      setState(() => sending = false);
    }
  }

  Component _field(String caption, String value, void Function(String) set, {InputType type = InputType.text}) =>
      label([.text(caption), input<String>(type: type, value: value, onInput: (v) => setState(() => set(v)))]);

  /// The quantity inside an item's chip.
  Component _qty(String itemName) {
    final i = items!.firstWhere((it) => it.name == itemName);
    return input<String>(
      type: InputType.text,
      classes: 'qty',
      value: '${picked[i.id]}',
      attributes: {'inputmode': 'numeric', 'aria-label': 'How many $itemName'},
      onInput: (v) => setState(() => picked[i.id] = int.tryParse(v.trim()) ?? 0),
    );
  }

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    final names = {for (final i in items ?? const <Item>[]) i.id: i.name};
    return div(classes: 'book', [
      header([
        h1([a(href: 'kit/', [.text('Ask for equipment')])]),
        nav([a(href: './', [.text('Schedule')])]),
      ]),
      main_([
        if (token != null)
          section(classes: 'done', [
            h2([.text('Request sent')]),
            p([.text('The lab prepares it once approved. Bookmark this private link to follow it:')]),
            p([a(href: link, [.text(link)])]),
          ])
        else ...[
          p([.text('Tell the Tech Lab what you need for a class, for lab work, or to take home for a project.')]),
          div(classes: 'slots', [
            for (final e in uses.entries)
              button(type: ButtonType.button, classes: use == e.key ? 'slot on' : 'slot', onClick: () => setState(() => use = e.key),
                  [.text(e.value)]),
          ]),
          div(classes: 'form', [
            if (use == 'home') ...[
              _field('Pick up on', day, (v) => day = v, type: InputType.date),
              _field('Bring back on', backDay, (v) => backDay = v, type: InputType.date),
            ] else ...[
              _field('Day', day, (v) => day = v, type: InputType.date),
              _field('From', from, (v) => from = v, type: InputType.time),
              _field('To', to, (v) => to = v, type: InputType.time),
              if (use == 'class') _field('Every week until (optional)', until, (v) => until = v, type: InputType.date),
            ],
            ChipPicker(
              id: 'course',
              caption: use == 'class' ? 'Class or course' : 'Course or project (optional)',
              options: courseList,
              picked: coursesPicked,
              draft: courseDraft,
              placeholder: coursesPicked.isEmpty ? 'type to search the timetable' : 'or…',
              onDraft: (v) => setState(() => courseDraft = v),
              onAdd: (v) => setState(() {
                if (!coursesPicked.contains(v)) coursesPicked.add(v);
                courseDraft = '';
              }),
              onRemove: (v) => setState(() => coursesPicked.remove(v)),
            ),
          ]),
          h2([.text('What you need')]),
          if (items == null && error == null) p(classes: 'empty', [.text('Loading the equipment list…')]),
          if (items != null)
            div(classes: 'form', [
              ChipPicker(
                id: 'items',
                caption: 'Equipment',
                options: [for (final i in items!) i.name],
                picked: [for (final id in picked.keys) names[id]!],
                draft: itemDraft,
                free: false, // only the lab's items; anything else goes under "Something else" below
                placeholder: picked.isEmpty ? 'type to search the equipment list' : 'add more…',
                chipExtra: _qty,
                onDraft: (v) => setState(() => itemDraft = v),
                onAdd: (v) => setState(() {
                  picked.putIfAbsent(items!.firstWhere((it) => it.name == v).id, () => 1);
                  itemDraft = '';
                }),
                onRemove: (v) => setState(() => picked.remove(items!.firstWhere((it) => it.name == v).id)),
              ),
            ]),
          div(classes: 'form', [
            label([.text('Something else, or details (optional)'), textarea(rows: 3, onInput: (v) => other = v, [.text(other)])]),
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field(numberLabel, number, (v) => number = v),
            // honeypot: hidden from people, bots fill it in
            label(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
              .text('Website'),
              input<String>(type: InputType.text, value: website, attributes: {'tabindex': '-1', 'autocomplete': 'off'}, onInput: (v) => website = v),
            ]),
            p(classes: 'note', [.text('${picked.length} item${picked.length == 1 ? '' : 's'} picked.')]),
            button(type: ButtonType.button, disabled: sending, onClick: _send, [.text(sending ? 'Sending…' : 'Send request')]),
            if (error != null) p(classes: 'error', [.text(error!)]),
            p(classes: 'note', [.text('Your request is saved in your lab history, visible to lab staff only.')]),
          ]),
        ],
      ]),
    ]);
  }
}
