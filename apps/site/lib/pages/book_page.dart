// "Book me" form (/book/): free slots, the request form, then the private status link.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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
  String name = '', email = '', project = '', link = '', number = '', website = '';
  String? error, token;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    final today = iso(DateTime.now());
    try {
      final s = await freeSlots(today, shift('day', today, 14));
      setState(() => slots = s);
    } catch (e) {
      setState(() => error = 'Could not load free times: $e');
    }
  }

  Future<void> _send() async {
    final problem = picked == null
        ? 'Pick a time first.'
        : formProblem(name: name, email: email, project: project, link: link, number: number);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('request_consultation', {
        'p_name': name, 'p_email': email, 'p_project': project, 'p_link': link, 'p_starts_at': picked!.iso,
        'p_student_number': number, 'p_website': website,
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
        h1([a(href: './', [.text('Book a consultation')])]),
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
          p([.text('Time with Andrey, the lab technician, for help with your project. Pick a free slot, then tell us about it.')]),
          if (slots == null && error == null) p(classes: 'empty', [.text('Loading free times…')]),
          if (slots != null && slots!.isEmpty) p(classes: 'empty', [.text('No free times in the next two weeks. Please check again later.')]),
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
            label([
              .text('Your project, and what you need help with'),
              textarea(rows: 4, onInput: (v) => project = v, [.text(project)]),
            ]),
            _field('Link (optional: example, repository, social)', link, (v) => this.link = v, type: InputType.url),
            _field('Student number (optional)', number, (v) => number = v),
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
