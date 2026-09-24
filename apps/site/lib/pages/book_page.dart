// "Book me" form (/book/): free slots of the next 7 days, name, email, one line, then the private status link.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../calendar.dart';

String _time(DateTime d) => '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

@client
class BookPage extends StatefulComponent {
  const BookPage({super.key});

  @override
  State<BookPage> createState() => BookPageState();
}

class BookPageState extends State<BookPage> {
  List<Slot>? slots;
  Slot? picked;
  String name = '', email = '', need = '', website = '';
  String? error, token;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final p = Uri.parse(web.window.location.href).queryParameters['project'] ?? ''; // from "Book a consultation about this idea"
    need = p.length > 300 ? p.substring(0, 300) : p;
    _load();
  }

  Future<void> _load() async {
    final today = iso(DateTime.now());
    try {
      final s = await freeSlots(today, shift('day', today, 6));
      setState(() => slots = s);
    } catch (e) {
      setState(() => error = 'Could not load free times: $e');
    }
  }

  Future<void> _send() async {
    final problem = picked == null
        ? 'Pick a time first.'
        : formProblem(name: name, email: email, need: need);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('request_consultation', {
        'p_name': name, 'p_email': email, 'p_project': need, 'p_link': '', 'p_starts_at': picked!.iso,
        'p_student_number': '', 'p_website': website,
      });
      setState(() => token = t as String);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
      _load(); // the slot may have gone; show what is free now
    } finally {
      setState(() => sending = false);
    }
  }

  Component _field(String caption, String value, void Function(String) set, {InputType type = InputType.text}) =>
      label([
        .text(caption),
        input<String>(type: type, value: value, onInput: (v) => set(v)),
      ]);

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    return div(classes: 'book', [
      header([
        h1([a(href: './', [.text('Book time in the lab')])]),
        nav([a(href: './', [.text('Schedule')])]),
      ]),
      main_([
        if (token != null)
          section(classes: 'done', [
            h2([.text('Request sent')]),
            p([.text('Bookmark this private link to see when it is approved:')]),
            p([a(href: link, [.text(link)])]),
          ])
        else ...[
          p([.text('Book time with Andrey in the Tech Lab. Pick a free slot.')]),
          if (slots == null && error == null) p(classes: 'empty', [.text('Loading free times…')]),
          if (slots != null && slots!.isEmpty) p(classes: 'empty', [.text('No free times this week. Please check again later.')]),
          if (slots != null)
            for (final e in byDay(slots!).entries)
              section([
                h2([.text(dayName(e.key))]),
                div(classes: 'slots', [
                  for (final s in e.value)
                    button(
                      type: ButtonType.button,
                      classes: picked?.iso == s.iso ? 'slot on' : 'slot',
                      onClick: () => setState(() => picked = s),
                      [.text('${_time(s.start)}–${_time(s.end)}')],
                    ),
                ]),
              ]),
          div(classes: 'form', [
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field('What do you need?', need, (v) => need = v),
            // honeypot: hidden from people, bots fill it in
            label(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
              .text('Website'),
              input<String>(type: InputType.text, value: website, attributes: {'tabindex': '-1', 'autocomplete': 'off'}, onInput: (v) => website = v),
            ]),
            button(type: ButtonType.button, disabled: sending, onClick: _send, [.text(sending ? 'Sending…' : 'Send request')]),
            if (error != null) p(classes: 'error', [.text(error!)]),
            p(classes: 'note', [.text('Your request is saved in your lab history, visible to lab staff only.')]),
          ]),
        ],
      ]),
    ]);
  }
}
