import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/requests/requests_screen.dart';

class RequestsFixtureRepository extends RideRepository {
  RequestsFixtureRepository(super.client);
  List<String> loadedVehicleIds = [];
  @override
  String get userId => 'fixture-user';
  @override
  Future<List<Record>> list(
    String table, {
    String? key,
    dynamic value,
    String order = 'created_at',
  }) async {
    expect(table, 'vehicles');
    expect(key, 'driver_id');
    expect(value, userId);
    return [
      {'id': 'owned-vehicle', 'driver_id': userId},
    ];
  }

  @override
  Future<List<Record>> publishedTripsForVehicles(Iterable<String> ids) async {
    loadedVehicleIds = ids.toList();
    return const [];
  }

  @override
  Future<List<Record>> tripsForOffers(Iterable<String> ids) async => [
    {
      'id': 'trip-fixture',
      'service': 'shared',
      'price': 12.5,
      'state': 'published',
      'starts_at': '2099-01-01T08:00:00Z',
      'ends_at': '2099-01-01T09:00:00Z',
    },
  ];
}

const request = {
  'id': 'request-fixture',
  'rider_id': 'fixture-user',
  'mode': 'posted',
  'state': 'booked',
  'origin': 'السموع',
  'destination': 'الخليل',
  'service': 'shared',
  'seats': 3,
  'requested_at': '2099-01-01T08:00:00Z',
};

void main() {
  late SupabaseClient client;
  setUpAll(() async {
    final cairo = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await cairo.load();
    client = SupabaseClient(
      'https://fixture.test',
      'fixture-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  tearDown(() => language.english = false);

  testWidgets(
    'Arabic selected and unselected offers fit a narrow screen with enlarged text',
    (tester) async {
      language.english = false;
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: RequestsScreen(
                  repository: RequestsFixtureRepository(client),
                  requests: const [request],
                  offers: const [
                    {
                      'id': 'offer-chosen',
                      'request_id': 'request-fixture',
                      'trip_id': 'trip-fixture',
                      'state': 'accepted',
                    },
                    {
                      'id': 'offer-other',
                      'request_id': 'request-fixture',
                      'trip_id': 'trip-fixture',
                      'state': 'rejected',
                    },
                  ],
                  driver: false,
                  onRefresh: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(RequestsScreen))),
        TextDirection.rtl,
      );
      expect(find.text('تم اختيار العرض وتأكيد الحجز'), findsOneWidget);
      expect(find.text('اختيار العرض وتأكيد الحجز'), findsNothing);
      expect(find.text('الأجرة الإجمالية: ₪ 37.5'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('../../work/screenshots').create(recursive: true);
        await File(
          '../../work/screenshots/mobile-offers-arabic-large.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.ensureVisible(find.text('لم يتم اختيار هذا العرض'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Driver sees offers only for another rider and loads owned vehicle trips',
    (tester) async {
      language.english = true;
      final repository = RequestsFixtureRepository(client);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestsScreen(
              repository: repository,
              requests: [
                {...request, 'state': 'searching'},
                {
                  ...request,
                  'id': 'other-request',
                  'state': 'searching',
                  'rider_id': 'another-rider',
                },
              ],
              offers: const [],
              driver: true,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.loadedVehicleIds, ['owned-vehicle']);
      expect(find.text('Offer a time & fare'), findsOneWidget);
      expect(find.text('السموع → الخليل'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pull to refresh works even on an empty requests page', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestsScreen(
            repository: RequestsFixtureRepository(client),
            requests: const [],
            offers: const [],
            driver: false,
            onRefresh: () async {
              refreshes++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });
}
