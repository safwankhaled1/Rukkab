import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/repository.dart';
import 'core/app_theme.dart';
import 'core/translations.dart';
import 'core/notification_service.dart';
import 'core/rider_social_auth.dart';
import 'core/error_messages.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';

const configured =
    String.fromEnvironment('SUPABASE_URL') != '' &&
    String.fromEnvironment('SUPABASE_ANON_KEY') != '';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (configured) {
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      postgrestOptions: const PostgrestClientOptions(
        requestTimeout: Duration(seconds: 15),
        retryCount: 1,
      ),
      authOptions: FlutterAuthClientOptions(localStorage: sessionStorage),
    );
    await NotificationService.initialize();
  }
  runApp(const RukkabApp());
}

class RukkabApp extends StatelessWidget {
  const RukkabApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: language,
    builder: (context, _) => MaterialApp(
      title: 'ركاب | Rukkab',
      debugShowCheckedModeBanner: false,
      locale: language.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: configured ? const SessionGate() : const SetupScreen(),
    ),
  );
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      if (Supabase.instance.client.auth.currentSession == null) {
        return const AuthScreen();
      }
      if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
        return const AuthScreen(recovery: true);
      }
      if (isSocialSession(
        Supabase.instance.client.auth.currentSession!.accessToken,
      )) {
        return RiderSocialSessionGate(
          key: ValueKey(
            Supabase.instance.client.auth.currentSession!.accessToken,
          ),
        );
      }
      return HomeScreen(
        key: ValueKey(Supabase.instance.client.auth.currentUser!.id),
        repository: RideRepository(Supabase.instance.client),
      );
    },
  );
}

class RiderSocialSessionGate extends StatefulWidget {
  const RiderSocialSessionGate({super.key});
  @override
  State<RiderSocialSessionGate> createState() => _RiderSocialSessionGateState();
}

class _RiderSocialSessionGateState extends State<RiderSocialSessionGate> {
  late final repository = RideRepository(Supabase.instance.client);
  late Future<Record> profile = repository.profile();
  @override
  Widget build(BuildContext context) => FutureBuilder<Record>(
    future: profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError || snapshot.data?['role'] != 'rider') {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? errorMessage(snapshot.error!)
                        : errorMessage(
                            const AppFailure('SOCIAL_SIGNIN_RIDERS_ONLY'),
                          ),
                  ),
                  if (snapshot.hasError)
                    TextButton(
                      onPressed: () =>
                          setState(() => profile = repository.profile()),
                      child: Text(language.text('إعادة المحاولة', 'Retry')),
                    ),
                  FilledButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(
                      scope: SignOutScope.local,
                    ),
                    child: Text(
                      language.text(
                        'العودة لتسجيل الدخول بالبريد',
                        'Back to email sign-in',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return HomeScreen(repository: repository);
    },
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ركاب'),
      actions: [
        IconButton(
          onPressed: language.toggle,
          icon: const Icon(Icons.language),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route, size: 72, color: Color(0xffb94e0e)),
            const SizedBox(height: 20),
            Text(
              language.text('الطريق بيجمعنا', 'Every road connects us'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              language.text(
                'التطبيق جاهز للربط. أضف إعدادات Supabase عند التشغيل لتفعيل الحسابات والرحلات الحقيقية.',
                'Connect Supabase using build-time settings to enable accounts and real trips.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const SelectableText(
              'SUPABASE_URL\nSUPABASE_ANON_KEY',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
