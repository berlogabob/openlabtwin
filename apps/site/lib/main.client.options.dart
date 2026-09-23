// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:site/pages/schedule_page.dart' deferred as _schedule_page;
import 'package:site/pages/tv_page.dart' deferred as _tv_page;

/// Default [ClientOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.client.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultClientOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ClientOptions get defaultClientOptions => ClientOptions(
  clients: {
    'schedule_page': ClientLoader(
      (p) => _schedule_page.SchedulePage(),
      loader: _schedule_page.loadLibrary,
    ),
    'tv_page': ClientLoader(
      (p) => _tv_page.TvPage(),
      loader: _tv_page.loadLibrary,
    ),
  },
);
