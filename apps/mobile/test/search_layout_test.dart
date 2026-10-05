import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/rider/search_screen.dart';

void main() {
  late SupabaseClient client;
  setUpAll(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  for (final english in [false, true]) {
    testWidgets('Empty route search fits narrow screen: English=$english', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      language.english = english;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: language.locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: SearchScreen(
              repository: RideRepository(client),
              routes: const [],
              stops: const [],
              onBooked: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(
          english ? 'Routes are awaiting approval' : 'الخطوط قيد الاعتماد',
        ),
        200,
      );
      expect(
        find.text(
          english ? 'Routes are awaiting approval' : 'الخطوط قيد الاعتماد',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      language.english = false;
    });
  }
}
