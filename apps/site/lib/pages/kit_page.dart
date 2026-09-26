// Equipment request form (/kit/): who, what for (class, lab work, take home), when, and a checklist from the lab's
// catalogue. Optional everywhere else: a booking never needs one. Ends with the private status link, as Book me does.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../book.dart';
import '../calendar.dart';
import '../kit.dart';

@client
class KitPage extends StatefulComponent {
  const KitPage({super.key});

  @override
  State<KitPage> createState() => KitPageState();
}

class KitPageState extends State<KitPage> {
  List<Item>? items;
  final picked = <int, int>{};
  String name = '', email = '', number = '', use = 'class', course = '', other = '', website = '', q = '';
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
  }

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

  Component _item(Item i) {
    final n = picked[i.id];
    return div(classes: 'kit-item', [
      button(
        type: ButtonType.button,
        classes: n == null ? 'slot' : 'slot on',
        onClick: () => setState(() => n == null ? picked[i.id] = 1 : picked.remove(i.id)),
        [.text(i.name)],
      ),
      if (n != null)
        label([
          .text('How many'),
          input<String>(
            type: InputType.text,
            value: '$n',
            attributes: {'inputmode': 'numeric', 'size': '3'},
            onInput: (v) => setState(() => picked[i.id] = int.tryParse(v.trim()) ?? 0),
          ),
        ]),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    final shown = items == null ? const <Item>[] : search(items!, q);
    return div(classes: 'book', [
      header([
        h1([a(href: './', [.text('Ask for equipment')])]),
        nav([a(href: '../', [.text('Schedule')])]),
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
            _field(use == 'class' ? 'Class or course' : 'Course or project (optional)', course, (v) => course = v),
          ]),
          h2([.text('What you need')]),
          if (items == null && error == null) p(classes: 'empty', [.text('Loading the equipment list…')]),
          if (items != null) ...[
            div(classes: 'form', [_field('Search', q, (v) => q = v)]),
            div(classes: 'kit-list', [for (final i in shown) _item(i)]),
            if (shown.isEmpty) p(classes: 'empty', [.text('Nothing by that name. Describe it below.')]),
          ],
          div(classes: 'form', [
            label([.text('Something else, or details (optional)'), textarea(rows: 3, onInput: (v) => other = v, [.text(other)])]),
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field('Student number (optional)', number, (v) => number = v),
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
