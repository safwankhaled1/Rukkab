import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/trip_seats.dart';

void main() {
  test(
    'Boarding transfers allocation once; scheduled drop-off cannot resell seats',
    () {
      Record snapshot(String state) => {
        'seat_limit': 7,
        'street_passengers': 1,
        'instant': false,
        'bookings': [
          {'seats': 3, 'state': state},
          {'seats': 7, 'state': 'pending'},
          {'seats': 5, 'state': 'cancelled'},
          {'seats': 5, 'state': 'no_show'},
        ],
      };
      final reserved = TripSeats.fromTrip(snapshot('confirmed'));
      expect(
        [reserved.occupied, reserved.reserved, reserved.available],
        [1, 3, 3],
      );
      final boarded = TripSeats.fromTrip(snapshot('boarded'));
      expect(
        [boarded.occupied, boarded.reserved, boarded.available],
        [4, 0, 3],
      );
      final completed = TripSeats.fromTrip(snapshot('completed'));
      expect(
        [
          completed.occupied,
          completed.reserved,
          completed.retained,
          completed.available,
        ],
        [1, 0, 3, 3],
      );
      expect(TripSeats.fromTrip(snapshot('reschedule_pending')).available, 3);
      expect(TripSeats.fromTrip(snapshot('cancelled')).available, 6);
    },
  );
  test(
    'Instant alighting releases seats; private taxi reserves the entire car',
    () {
      final instant = TripSeats.fromTrip({
        'seat_limit': 4,
        'street_passengers': 0,
        'instant': true,
        'bookings': [
          {'seats': 4, 'state': 'completed'},
        ],
      });
      expect(instant.available, 4);
      expect(instant.hasPassengersRemaining, isFalse);
      final private = TripSeats.fromTrip({
        'seat_limit': 4,
        'street_passengers': 0,
        'instant': false,
        'bookings': [
          {'seats': 4, 'state': 'confirmed'},
        ],
      });
      expect(
        [private.reserved, private.occupied, private.available],
        [4, 0, 0],
      );
      expect(private.hasPassengersRemaining, isTrue);
    },
  );
  test(
    'Vehicle overview retains all live trips beyond 100 and embeds only seat data',
    () async {
      var liveReads = 0;
      var historyReads = 0;
      final client = SupabaseClient(
        'https://fixture.test',
        'fixture-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(query['vehicle_id'], 'eq.owned-car');
          expect(query['select'], '*,bookings(seats,state)');
          final live = (query['state'] ?? '').startsWith('in.');
          final offset = int.parse(query['offset'] ?? '0');
          final count = live ? (offset == 0 ? 100 : 1) : 1;
          if (live) {
            liveReads++;
          } else {
            historyReads++;
          }
          final rows = List.generate(
            count,
            (index) => {
              'id': live ? 'live-${offset + index}' : 'historic',
              'bookings': [
                {'seats': 1, 'state': 'confirmed'},
              ],
            },
          );
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        final rows = await RideRepository(client).vehicleTrips('owned-car');
        expect(rows.length, 102);
        expect(rows[100]['id'], 'live-100');
        expect(rows.last['id'], 'historic');
        expect(rows[100]['bookings'], [
          {'seats': 1, 'state': 'confirmed'},
        ]);
        expect([liveReads, historyReads], [2, 1]);
      } finally {
        await client.dispose();
      }
    },
  );
}
