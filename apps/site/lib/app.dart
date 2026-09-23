import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/schedule_page.dart';
import 'pages/tv_page.dart';

// Built only on the server during the static build; each page is a @client component mounted in the browser.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) => Router(routes: [
        Route(path: '/', title: 'IADE Schedule', builder: (context, state) => const SchedulePage()),
        Route(path: '/tv', title: 'Lab TV · IADE Schedule', builder: (context, state) => const TvPage()),
      ]);
}
