import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/features/auth/auth_screen.dart';
import 'package:rukkab/features/rider/search_screen.dart';
import 'package:rukkab/shared/motion_entrance.dart';

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    final cairo = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await cairo.load();
    await icons.load();
    client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  testWidgets('Reduced motion leaves content directly mounted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MotionEntrance(child: Text('Ready')),
        ),
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });
  testWidgets(
    'Render actual Arabic auth and journey widgets with bundled typography',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      language.english = false;
      for (final preview in ['auth', 'journey']) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: RepaintBoundary(
              key: boundary,
              child: preview == 'auth'
                  ? const AuthScreen()
                  : Scaffold(
                      body: SearchScreen(
                        repository: RideRepository(client),
                        routes: const [],
                        stops: const [],
                        onBooked: () {},
                      ),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('../../work/screenshots').create(recursive: true);
          await File(
            '../../work/screenshots/mobile-$preview-arabic.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
