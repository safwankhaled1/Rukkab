import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/core/fare_quote.dart';
import 'package:rukkab/core/booking_rules.dart';
import 'package:rukkab/features/requests/requests_screen.dart';
import 'package:rukkab/features/bookings/bookings_screen.dart';
import 'package:rukkab/shared/no_show_button.dart';

class OfferFixtureRepository extends RideRepository {
  OfferFixtureRepository(super.client);
  List<Record> trips = [];
  List<String> requestedTrips = [];
  final calls = <Record>[];
  @override
  String get userId => 'rider-fixture';
  @override
  Future<List<Record>> tripsForOffers(Iterable<String> ids) async {
    requestedTrips = ids.toList();
    return trips.where((trip) => requestedTrips.contains(trip['id'])).toList();
  }

  @override
  Future<dynamic> rpc(String name, Record p) async {
    calls.add({'name': name, 'parameters': p});
    return 'booking-fixture';
  }
}

void main() {
  late SupabaseClient client;
  setUpAll(() {
    client = SupabaseClient(
      'https://fixture.test',
      'fixture-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => client.dispose());
  setUp(() => language.english = true);
  tearDown(() => language.english = false);
  test(
    'Shared quotes include every requested seat; private quotes cover the car once',
    () {
      expect(quotedTotal('12.50', 'shared', 3), 37.5);
      expect(quotedTotal(42.5, 'private', 3), 42.5);
      expect(quotedTotal(null, 'shared', 3), isNull);
      expect(quotedTotal('NaN', 'shared', 3), isNull);
      expect(quotedTotal(12, 'shared', 0), isNull);
    },
  );
  test('No-show waits for both arrival plus five minutes and departure', () {
    final now = DateTime.utc(2026, 10, 5, 8);
    expect(noShowWait(null, now, now), isNull);
    expect(
      noShowWait(now.subtract(const Duration(minutes: 4)), now, now),
      const Duration(minutes: 1),
    );
    expect(
      noShowWait(
        now.subtract(const Duration(minutes: 6)),
        now.add(const Duration(minutes: 2)),
        now,
      ),
      const Duration(minutes: 2),
    );
    expect(
      noShowWait(now.subtract(const Duration(minutes: 6)), now, now),
      Duration.zero,
    );
  });
  testWidgets(
    'An offer resolves its own trip and displays total fare before accepting',
    (tester) async {
      final repository = OfferFixtureRepository(client)
        ..trips = [
          {
            'id': 'older-offered-trip',
            'origin': 'السموع',
            'destination': 'الخليل',
            'service': 'shared',
            'price': '12.50',
            'state': 'published',
            'starts_at': '2099-01-01T08:00:00Z',
            'ends_at': '2099-01-01T09:00:00Z',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestsScreen(
              repository: repository,
              requests: const [
                {
                  'id': 'request-fixture',
                  'rider_id': 'rider-fixture',
                  'mode': 'posted',
                  'state': 'searching',
                  'origin': 'السموع',
                  'destination': 'الخليل',
                  'service': 'shared',
                  'seats': 3,
                  'requested_at': '2099-01-01T08:00:00Z',
                },
              ],
              offers: const [
                {
                  'id': 'offer-fixture',
                  'request_id': 'request-fixture',
                  'trip_id': 'older-offered-trip',
                  'state': 'pending',
                },
              ],
              driver: false,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.requestedTrips, ['older-offered-trip']);
      expect(find.text('Total fare: ₪ 37.5'), findsOneWidget);
      expect(find.text('For 3 seats · Pay cash'), findsOneWidget);
      final choose = find.text('Choose offer & confirm booking');
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(repository.calls.single['parameters'], {
        'p': {'action': 'accept', 'offer_id': 'offer-fixture'},
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Unknown trip fares cannot be booked from the offers page', (
    tester,
  ) async {
    final repository = OfferFixtureRepository(client);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestsScreen(
            repository: repository,
            requests: const [
              {
                'id': 'request-fixture',
                'rider_id': 'rider-fixture',
                'mode': 'posted',
                'state': 'searching',
                'origin': 'السموع',
                'destination': 'الخليل',
                'service': 'shared',
                'seats': 3,
                'requested_at': '2099-01-01T08:00:00Z',
              },
            ],
            offers: const [
              {
                'id': 'offer-fixture',
                'request_id': 'request-fixture',
                'trip_id': 'unavailable-trip',
                'state': 'pending',
              },
            ],
            driver: false,
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total fare: ₪ —'), findsOneWidget);
    expect(find.text('Choose offer & confirm booking'), findsNothing);
    expect(repository.calls, isEmpty);
  });
  testWidgets('Driver cannot board a confirmed passenger before trip start', (
    tester,
  ) async {
    final repository = OfferFixtureRepository(client);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingsScreen(
            repository: repository,
            bookings: const [
              {
                'id': 'booking-fixture',
                'state': 'confirmed',
                'seats': 1,
                'total_price': 15,
                'trips': {
                  'origin': 'السموع',
                  'destination': 'الخليل',
                  'state': 'published',
                  'starts_at': '2099-01-01T08:00:00Z',
                },
              },
            ],
            driver: true,
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm boarding'), findsNothing);
    expect(find.text('Arrived at pickup'), findsNothing);
    expect(find.textContaining('Start the trip'), findsOneWidget);
  });
  testWidgets(
    'No-show remains disabled until the wait is satisfied and respects busy state',
    (tester) async {
      var calls = 0;
      final now = DateTime.now();
      Widget app(DateTime? arrival, {bool busy = false}) => MaterialApp(
        home: Scaffold(
          body: NoShowButton(
            arrivedAt: arrival,
            startsAt: now.subtract(const Duration(minutes: 1)),
            busy: busy,
            onPressed: () => calls++,
          ),
        ),
      );
      await tester.pumpWidget(app(null));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(app(now.subtract(const Duration(minutes: 4))));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('No-show in'), findsOneWidget);
      await tester.pumpWidget(app(now.subtract(const Duration(minutes: 6))));
      await tester.tap(find.text('No-show'));
      expect(calls, 1);
      await tester.pumpWidget(
        app(now.subtract(const Duration(minutes: 6)), busy: true),
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );
}
