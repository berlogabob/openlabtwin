import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/book_page.dart';
import 'pages/idea_status_page.dart';
import 'pages/ideas_page.dart';
import 'pages/schedule_page.dart';
import 'pages/status_page.dart';
import 'pages/tv_page.dart';

// Built only on the server during the static build; each page is a @client component mounted in the browser.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) => Router(routes: [
        Route(path: '/', title: 'IADE Schedule', builder: (context, state) => const SchedulePage()),
        Route(path: '/tv', title: 'Lab TV · IADE Schedule', builder: (context, state) => const TvPage()),
        Route(path: '/book', title: 'Book a consultation · IADE Lab', builder: (context, state) => const BookPage()),
        Route(path: '/book/status', title: 'Your consultation · IADE Lab', builder: (context, state) => const StatusPage()),
        Route(path: '/ideas', title: 'Share an idea · IADE Lab', builder: (context, state) => const IdeasPage()),
        Route(path: '/ideas/status', title: 'Your idea · IADE Lab', builder: (context, state) => const IdeaStatusPage()),
      ]);
}
