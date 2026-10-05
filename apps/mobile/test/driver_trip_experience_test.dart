import 'dart:async';
import 'package:rukkab/core/location_service.dart';
import 'package:rukkab/core/palestine_time.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/app_theme.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/driver/driver_screen.dart';
import 'package:rukkab/features/bookings/bookings_screen.dart';
import 'package:rukkab/shared/trip_seat_summary.dart';

class DriverTripsFixture extends RideRepository {
  DriverTripsFixture(super.client);
  final actions = <Record>[];
  final locationOrder = <String>[];
  List<Record> trips = [];
  Completer<List<Record>>? delayedFirstCar;
  @override
  String get userId => 'driver-fixture';
  @override
  Future<Record?> driverIdentity() async => {
    'phone': '+970599000000',
    'date_of_birth': '1990-01-01',
  };
  @override
  Future<bool> vehicleReady(String id) async => true;
  @override
  Future<List<Record>> vehicleTrips(String vehicleId) async =>
      vehicleId == 'car-first' && delayedFirstCar != null
      ? delayedFirstCar!.future
      : trips;
  @override
  Future<List<Record>> list(
    String table, {
    String? key,
    dynamic value,
    String order = 'created_at',
  }) async => [];
  @override
  Future<void> tripAction(
    String id,
    String action, [
    Record p = const {},
  ]) async {
    actions.add({'id': id, 'action': action, 'parameters': p});
  }

  @override
  Future<void> accountAction(String action, Record p) async {
    locationOrder.add(p['online'] == true ? 'server-online' : 'server-offline');
    if (p['online'] == false) throw const AppFailure('OFFLINE');
  }

  @override
  Future<void> bookingAction(String id, String action) async {
    actions.add({'id': id, 'action': action});
  }
}

class LocationFixture extends DriverLocationService {
  LocationFixture(super.repository, this.order);
  final List<String> order;
  @override
  Future<void> start(String id) async {
    order.add('location-start');
  }

  @override
  Future<void> stop() async {
    order.add('location-stop');
  }
}

const firstCar = {
  'id': 'car-first',
  'plate': 'CAR-1',
  'capacity': 7,
  'approved': true,
  'online': false,
};
const secondCar = {
  'id': 'car-second',
  'plate': 'CAR-2',
  'capacity': 7,
  'approved': true,
  'online': false,
};
const trip = {
  'id': 'trip-fixture',
  'origin': 'السموع',
  'destination': 'الخليل',
  'state': 'active',
  'service': 'shared',
  'price': 15,
  'seat_limit': 7,
  'street_passengers': 1,
  'instant': false,
  'starts_at': '2099-01-01T08:00:00Z',
  'ends_at': '2099-01-01T09:00:00Z',
  'bookings': [
    {'seats': 2, 'state': 'confirmed'},
    {'seats': 1, 'state': 'boarded'},
    {'seats': 1, 'state': 'completed'},
  ],
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
  setUp(() => language.english = true);
  tearDown(() => language.english = false);
  Widget driver(
    DriverTripsFixture repository, {
    List<Record> cars = const [firstCar],
  }) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: DriverScreen(
        repository: repository,
        vehicles: cars,
        routes: const [],
        stops: const [],
        onRefresh: () async {},
      ),
    ),
  );

  testWidgets(
    'Driver sees allocated seats and cannot finish or cancel with passengers aboard',
    (tester) async {
      final repository = DriverTripsFixture(client)..trips = [trip];
      await tester.pumpWidget(driver(repository));
      await tester.pumpAndSettle();
      final summary = tester
          .widget<TripSeatSummary>(find.byType(TripSeatSummary))
          .seats;
      expect(
        [
          summary.available,
          summary.reserved,
          summary.occupied,
          summary.retained,
        ],
        [2, 2, 2, 1],
      );
      expect(find.text('Available'), findsOneWidget);
      expect(find.textContaining('remain allocated'), findsOneWidget);
      for (final label in ['Finish trip', 'Cancel trip']) {
        final button = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Private taxi has no street controls; cancellation requires a deliberate choice',
    (tester) async {
      final repository = DriverTripsFixture(client)
        ..trips = [
          {
            ...trip,
            'service': 'private',
            'street_passengers': 0,
            'bookings': const [],
          },
        ];
      await tester.pumpWidget(driver(repository));
      await tester.pumpAndSettle();
      expect(find.text('Street rider +1'), findsNothing);
      expect(find.textContaining('reserves all seats'), findsOneWidget);
      final cancel = find.text('Cancel trip');
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(repository.actions, isEmpty);
      expect(find.text('Cancel this trip?'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(repository.actions, isEmpty);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel trip'));
      await tester.pumpAndSettle();
      expect(repository.actions.single['action'], 'cancel');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A delayed previous vehicle response cannot replace the newly selected vehicle trips',
    (tester) async {
      final delayed = Completer<List<Record>>();
      final repository = DriverTripsFixture(client)
        ..delayedFirstCar = delayed
        ..trips = [
          {...trip, 'origin': 'SECOND-CAR-TRIP'},
        ];
      await tester.pumpWidget(
        driver(repository, cars: const [firstCar, secondCar]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('CAR-1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('CAR-2').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('SECOND-CAR-TRIP'), findsOneWidget);
      delayed.complete([
        {...trip, 'origin': 'STALE-FIRST-CAR'},
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('STALE-FIRST-CAR'), findsNothing);
      expect(find.textContaining('SECOND-CAR-TRIP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic reschedule details show old and new times without overflow and decline safely',
    (tester) async {
      language.english = false;
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = DriverTripsFixture(client);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: BookingsScreen(
                repository: repository,
                driver: false,
                onRefresh: () async {},
                bookings: [
                  {
                    'id': 'booking-fixture',
                    'state': 'reschedule_pending',
                    'seats': 3,
                    'total_price': 45,
                    'trips': {
                      ...trip,
                      'starts_at': '2099-01-01T09:00:00Z',
                      'previous_starts_at': '2099-01-01T08:00:00Z',
                    },
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('الموعد السابق'), findsOneWidget);
      expect(find.text('وافق على الموعد الجديد'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('الموعد ما بناسبني'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الموعد ما بناسبني'));
      await tester.pumpAndSettle();
      expect(repository.actions.single, {
        'id': 'booking-fixture',
        'action': 'decline_time',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Going offline stops local location sharing even when the network request fails',
    (tester) async {
      final repository = DriverTripsFixture(client)..trips = const [];
      final service = LocationFixture(repository, repository.locationOrder);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DriverScreen(
              repository: repository,
              locationService: service,
              vehicles: [
                {...firstCar, 'online': true},
              ],
              routes: const [],
              stops: const [],
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.locationOrder, contains('location-start'));
      repository.locationOrder.clear();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(repository.locationOrder, ['location-stop', 'server-offline']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reschedule picker preserves existing date and time; unchanged save sends no update',
    (tester) async {
      final current = DateTime.now().toUtc();
      final start = DateTime.utc(
        current.year,
        current.month,
        current.day + 3,
        8,
        17,
      );
      final end = start.add(const Duration(hours: 1));
      final repository = DriverTripsFixture(client)
        ..trips = [
          {
            ...trip,
            'state': 'published',
            'starts_at': start.toIso8601String(),
            'ends_at': end.toIso8601String(),
            'street_passengers': 0,
            'bookings': const [],
          },
        ];
      await tester.pumpWidget(driver(repository));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reschedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reschedule'));
      await tester.pumpAndSettle();
      final departure = find.widgetWithText(TextFormField, 'Departure');
      final form = tester.widget<TextFormField>(departure);
      expect(
        form.controller!.text,
        DateFormat('yyyy-MM-dd HH:mm').format(palestineTime(start)),
      );
      await tester.tap(departure);
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      final expected = palestineTime(start);
      expect(
        calendar.initialDate,
        DateTime(expected.year, expected.month, expected.day),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialTime,
        TimeOfDay.fromDateTime(expected),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(repository.actions, isEmpty);
      expect(find.text('The trip time is unchanged.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
