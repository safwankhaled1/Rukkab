import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';

void main() {
  test(
    'Driver offers retain older eligible trips and query only owned vehicles',
    () async {
      final ranges = <String>[];
      final client = SupabaseClient(
        'https://fixture.test',
        'fixture-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(request.url.path, '/rest/v1/trips');
          expect(query['vehicle_id'], 'in.("owned-vehicle")');
          expect(query['state'], 'eq.published');
          expect(query['ends_at'], startsWith('gt.'));
          expect(query['order'], 'starts_at.asc.nullslast,id.asc.nullslast');
          final offset = int.parse(query['offset'] ?? '0');
          final limit = int.parse(query['limit'] ?? '0');
          expect(limit, 100);
          ranges.add('$offset:$limit');
          final count = offset == 0 ? 100 : 5;
          return http.Response(
            jsonEncode(
              List.generate(
                count,
                (index) => {
                  'id': 'eligible-trip-${offset + index}',
                  'vehicle_id': 'owned-vehicle',
                  'state': 'published',
                },
              ),
            ),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        final repository = RideRepository(client);
        final trips = await repository.publishedTripsForVehicles([
          'owned-vehicle',
          'owned-vehicle',
        ]);
        expect(trips.length, 105);
        expect(trips.last['id'], 'eligible-trip-104');
        expect(ranges, ['0:100', '100:100']);
        expect(await repository.publishedTripsForVehicles(const []), isEmpty);
        expect(ranges.length, 2);
      } finally {
        await client.dispose();
      }
    },
  );
}
