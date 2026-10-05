import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/shared/home_app_bar.dart';

void main() {
  tearDown(() => language.english = false);
  testWidgets(
    'Driver actions remain reachable at 280px with enlarged Arabic text',
    (tester) async {
      language.english = false;
      tester.view.physicalSize = const Size(280, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var switches = 0;
      var notifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(280, 700),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              appBar: HomeAppBar(
                driverAccount: true,
                passengerMode: false,
                busy: false,
                unreadCount: 120,
                onSwitchMode: () => switches++,
                onNotifications: () => notifications++,
                onLanguage: () {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('الإشعارات'));
      expect(notifications, 1);
      await tester.tap(find.byTooltip('خيارات الحساب'));
      await tester.pumpAndSettle();
      expect(find.text('وضع السائق'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('حجز رحلة كراكب'));
      await tester.pumpAndSettle();
      expect(switches, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Riders have no driver switch and refresh is disabled while loading',
    (tester) async {
      language.english = true;
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: HomeAppBar(
              driverAccount: false,
              passengerMode: true,
              busy: true,
              unreadCount: 0,
              onSwitchMode: () => fail('Rider cannot switch to driving'),
              onNotifications: () {},
              onLanguage: () {},
              onRefresh: () => refreshes++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Account options'));
      await tester.pumpAndSettle();
      expect(find.text('Passenger mode'), findsOneWidget);
      expect(find.text('Switch to driving'), findsNothing);
      final refresh = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Refresh data'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(refresh.enabled, isFalse);
      await tester.tap(find.text('Refresh data'));
      await tester.pumpAndSettle();
      expect(refreshes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
