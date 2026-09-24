// Idea hub form (/ideas/): a student drops an idea, gets a private link.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../book.dart';
import '../ideas.dart';

@client
class IdeasPage extends StatefulComponent {
  const IdeasPage({super.key});

  @override
  State<IdeasPage> createState() => IdeasPageState();
}

class IdeasPageState extends State<IdeasPage> {
  String name = '', email = '', number = '', body = '', link = '', canBring = '', lookingFor = '', website = '';
  String? error, token;
  bool sending = false;

  Future<void> _send() async {
    final problem = ideaProblem(
        name: name, email: email, body: body, link: link, canBring: canBring, lookingFor: lookingFor, number: number);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('submit_idea', {
        'p_name': name, 'p_email': email, 'p_body': body, 'p_link': link, 'p_can_bring': canBring,
        'p_looking_for': lookingFor, 'p_student_number': number, 'p_website': website,
      });
      setState(() => token = t as String);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      setState(() => sending = false);
    }
  }

  Component _field(String caption, String value, void Function(String) set, {InputType type = InputType.text}) =>
      label([.text(caption), input<String>(type: type, value: value, onInput: (v) => set(v))]);

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    return div(classes: 'book', [
      header([
        h1([a(href: 'ideas/', [.text('Share an idea')])]),
        nav([a(href: './', [.text('Schedule')]), .text(' · '), a(href: 'book/', [.text('Book a consultation')])]),
      ]),
      main_([
        if (token != null)
          section(classes: 'done', [
            h2([.text('Idea sent')]),
            p([.text('Bookmark this private link. It shows what the AI made of your idea and, once the lab approves it, '
                'students with similar or complementary ideas:')]),
            p([a(href: link, [.text(link)])]),
          ])
        else ...[
          p([.text('Have a project idea? Drop it here. A local AI in the lab tidies it up and finds students with similar '
              'ideas, or with the skills you are looking for.')]),
          div(classes: 'form', [
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field('Student number (optional)', number, (v) => number = v),
            label([.text('Your idea'), textarea(rows: 5, onInput: (v) => body = v, [.text(body)])]),
            _field('Link (optional: example, repository, social)', link, (v) => this.link = v, type: InputType.url),
            _field('I can bring (optional: e.g. Unity, 3D modelling)', canBring, (v) => canBring = v),
            _field('I\'m looking for (optional: e.g. electronics, a sound designer)', lookingFor, (v) => lookingFor = v),
            // honeypot: hidden from people, bots fill it in
            label(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
              .text('Website'),
              input<String>(type: InputType.text, value: website, attributes: {'tabindex': '-1', 'autocomplete': 'off'}, onInput: (v) => website = v),
            ]),
            button(type: ButtonType.button, disabled: sending, onClick: _send, [.text(sending ? 'Sending…' : 'Send idea')]),
            if (error != null) p(classes: 'error', [.text(error!)]),
            p(classes: 'note', [.text('Your idea is saved in your lab history, visible to lab staff only; '
                'matched students see its title and your first name.')]),
          ]),
        ],
      ]),
    ]);
  }
}
