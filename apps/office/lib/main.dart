// Lab office: staff sign in with an email link, then log, approve and equip bookings.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookings.dart';
import 'data.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY'); // public by design: anon has no grants, RLS decides

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // browser tests read the semantics tree; build with --dart-define=E2E=true (off in production)
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey, httpClient: TimeoutClient());
  } catch (e) {
    // a bad key or no network at boot must not leave a blank white page (lesson from UNIDCOM RIMS)
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Could not start the office: $e')))));
    return;
  }
  runApp(const OfficeApp());
}

class OfficeApp extends StatelessWidget {
  const OfficeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lab office',
        theme: ThemeData(colorSchemeSeed: const Color(0xFFB3261E)),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (context, _) => db.auth.currentSession == null ? const LoginPage() : const BookingsPage(),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  String? message;

  Future<void> _send() async {
    setState(() => message = 'Sending…');
    try {
      await db.auth.signInWithOtp(
        email: email.text.trim().toLowerCase(),
        shouldCreateUser: false, // staff accounts are created by an admin; nobody signs up here
        emailRedirectTo: Uri.base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'[?#]+$'), ''),
      );
      setState(() => message = 'Check your inbox: the link signs you in on this browser.');
    } on AuthException catch (e) {
      setState(() => message = e.message.contains('not allowed') || e.statusCode == '422'
          ? 'This email is not a lab staff account.'
          : e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Lab office', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Staff email'),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _send, child: const Text('Send sign-in link')),
              if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!)),
            ]),
          ),
        ),
      );
}
