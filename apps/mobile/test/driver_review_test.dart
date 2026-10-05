import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rukkab/core/repository.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/features/driver/driver_onboarding_screen.dart';

class ReviewRepository extends RideRepository {
  ReviewRepository(super.client);
  @override
  String get userId => 'driver-fixture';
  @override
  Future<Record> profile() async => {'full_name': 'Fixture Driver'};
  @override
  Future<Record?> driverIdentity() async => {
    'phone': '+970599000000',
    'date_of_birth': '1990-01-01',
  };
  @override
  Future<List<Record>> list(
    String table, {
    String? key,
    dynamic value,
    String order = 'created_at',
  }) async => [];
}

void main() {
  late SupabaseClient client;
  var state = 'submitted';
  setUpAll(() {
    client = SupabaseClient(
      'https://fixture.test',
      'fixture-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final rows = request.url.path.endsWith('/vehicle_ownership')
            ? [
                {
                  'vehicle_owner_name': 'Vehicle Owner',
                  'permit_holder_name': 'Permit Holder',
                },
              ]
            : [
                {
                  'state': state,
                  'review_note': state == 'rejected'
                      ? 'Upload a clearer license'
                      : null,
                },
              ];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => client.dispose());
  testWidgets(
    'Live rejection opens editable document steps and preserves driver details',
    (tester) async {
      language.english = true;
      addTearDown(() => language.english = false);
      final vehicle = <String, dynamic>{
        'id': 'vehicle-fixture',
        'plate': 'TEST-1',
        'kind': 'minibus',
        'capacity': 7,
        'permit_line': 'Fixture route',
        'approved': false,
      };
      Widget app(Record value) => MaterialApp(
        home: DriverOnboardingScreen(
          repository: ReviewRepository(client),
          vehicle: value,
          onRefresh: () async {},
        ),
      );
      await tester.pumpWidget(app(vehicle));
      await tester.pumpAndSettle();
      expect(find.text('Your application was received'), findsOneWidget);
      state = 'rejected';
      await tester.pumpWidget(
        app({...vehicle, 'review_note': 'Upload a clearer license'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your application was received'), findsNothing);
      expect(find.textContaining('Upload a clearer license'), findsOneWidget);
      expect(find.text('Required documents'), findsOneWidget);
      for (var step = 0; step < 2; step++) {
        final back = find.text('Back');
        await tester.ensureVisible(back);
        await tester.pumpAndSettle();
        await tester.tap(back);
        await tester.pumpAndSettle();
      }
      final name = find.byType(TextFormField).first;
      await tester.enterText(name, 'اسم مصحح لم يُحفظ');
      await tester.pumpWidget(
        app({...vehicle, 'updated_at': 'fixture-refresh'}),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((field) => field.controller.text),
        contains('اسم مصحح لم يُحفظ'),
      );
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((field) => field.controller.text),
        contains('+970599000000'),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
