import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';

void main() {
  test(
    'Offer trip loading resolves all referenced IDs in bounded batches and skips duplicates',
    () async {
      final batches = <List<String>>[];
      final client = SupabaseClient(
        'https://fixture.test',
        'fixture-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/trips');
          final ids =
              RegExp(
                    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                  )
                  .allMatches(request.url.queryParameters['id'] ?? '')
                  .map((match) => match.group(0)!)
                  .toList();
          expect(ids.length, inInclusiveRange(1, 100));
          batches.add(ids);
          return http.Response(
            jsonEncode(ids.map((id) => {'id': id}).toList()),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        final repository = RideRepository(client);
        final ids = List.generate(
          205,
          (index) =>
              '10000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
        );
        final rows = await repository.tripsForOffers([...ids, ids.first]);
        expect(rows.map((row) => row['id']).toList(), ids);
        expect(batches.map((batch) => batch.length).toList(), [100, 100, 5]);
        expect(await repository.tripsForOffers(const []), isEmpty);
        expect(batches.length, 3);
      } finally {
        await client.dispose();
      }
    },
  );
}
