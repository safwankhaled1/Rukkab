import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/account/account_screen.dart';

void main() {
  testWidgets(
    'Passenger account has no driver registration or conversion action',
    (tester) async {
      language.english = true;
      // Supabase starts a JSON isolate; create/dispose it outside widget fake time.
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.test',
          'fixture-key-only',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountScreen(
              repository: RideRepository(client),
              profile: {'role': 'rider', 'full_name': 'Fixture Rider'},
              notifications: const [],
              violations: const [],
              onRefresh: () async {},
            ),
          ),
        ),
      );
      expect(find.text('Edit name'), findsOneWidget);
      expect(find.textContaining('driver'), findsNothing);
      expect(find.byIcon(Icons.directions_bus_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => client.dispose());
      language.english = false;
    },
  );
}
