import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/auth/auth_screen.dart';
import 'package:rukkab/features/auth/email_confirmation_screen.dart';

void main() {
  testWidgets(
    'Apple sign-in is available on iOS only and stays below email login',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      language.english = true;
      addTearDown(() => language.english = false);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const AuthScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with Apple'), findsOneWidget);
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.ensureVisible(find.text('Continue with Google'));
      expect(
        tester.getTopLeft(find.text('Continue with Google')).dy,
        greaterThan(tester.getTopLeft(fields.first).dy),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final english in [false, true]) {
    testWidgets(
      'Confirmation has no password form and returns to sign-in: English=$english',
      (tester) async {
        language.english = english;
        addTearDown(() => language.english = false);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final navigation = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigation,
            theme: buildAppTheme(),
            locale: language.locale,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: Text('Sign-in page')),
          ),
        );
        navigation.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const EmailConfirmationScreen(email: 'driver@example.test'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('driver@example.test'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final back = find.text(
          english ? 'Back to sign in' : 'العودة إلى تسجيل الدخول',
        );
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('Sign-in page'), findsOneWidget);
        expect(find.text('driver@example.test'), findsNothing);
      },
    );
    testWidgets('Auth fits narrow display with large text: English=$english', (
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
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const AuthScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          english ? 'Continue with Google' : 'المتابعة باستخدام Google',
        ),
        findsOneWidget,
      );
      expect(
        find.text(english ? 'Continue with Apple' : 'المتابعة باستخدام Apple'),
        findsNothing,
      );
      expect(find.text(english ? 'Passenger' : 'راكب'), findsOneWidget);
      await tester.ensureVisible(find.text(english ? 'Driver' : 'سائق'));
      await tester.tap(find.text(english ? 'Driver' : 'سائق'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          english ? 'Continue with Google' : 'المتابعة باستخدام Google',
        ),
        findsNothing,
      );
      await tester.tap(find.text(english ? 'Passenger' : 'راكب'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      final signup = find.text(
        english ? 'Create a new account' : 'إنشاء حساب جديد',
      );
      await tester.ensureVisible(signup);
      await tester.tap(signup);
      await tester.pumpAndSettle();
      expect(
        find.text(
          english ? 'Continue with Google' : 'المتابعة باستخدام Google',
        ),
        findsNothing,
      );
      expect(
        find.text(english ? 'Continue with Apple' : 'المتابعة باستخدام Apple'),
        findsNothing,
      );
      final driverEntry = find.text(
        english ? 'Register as a driver' : 'التسجيل كسائق',
      );
      await tester.ensureVisible(driverEntry);
      await tester.tap(driverEntry);
      await tester.pumpAndSettle();
      expect(
        find.text(
          english ? 'Full name as on license' : 'الاسم الكامل حسب الرخصة',
        ),
        findsOneWidget,
      );
      expect(
        find.text(english ? 'Phone number' : 'رقم الهاتف'),
        findsOneWidget,
      );
      expect(
        find.text(english ? 'Date of birth' : 'تاريخ الميلاد'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      language.english = false;
    });
  }
}
