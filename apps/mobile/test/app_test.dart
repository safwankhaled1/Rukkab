import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/main.dart';
import 'package:rukkab/core/translations.dart';
import 'package:rukkab/core/booking_rules.dart';

void main() {
  testWidgets('Arabic layout switches to English without losing setup state', (
    tester,
  ) async {
    language.english = false;
    await tester.pumpWidget(const RukkabApp());
    await tester.pumpAndSettle();
    expect(find.text('الطريق بيجمعنا'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الطريق بيجمعنا'))),
      TextDirection.rtl,
    );
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    expect(find.text('Every road connects us'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Every road connects us'))),
      TextDirection.ltr,
    );
    language.english = false;
  });
  test(
    'boarding transfers reservation into occupancy without double counting',
    () {
      const waiting = SeatSummary(
        capacity: 7,
        streetPassengers: 2,
        reserved: 3,
        boarded: 0,
      );
      const riding = SeatSummary(
        capacity: 7,
        streetPassengers: 2,
        reserved: 1,
        boarded: 2,
      );
      expect(waiting.available, 2);
      expect(riding.available, 2);
      expect(riding.onBoard, 4);
    },
  );
  test(
    'location display ends on cancellation, drop-off and schedule change',
    () {
      expect(canViewLocation('confirmed', 'active'), true);
      expect(canViewLocation('boarded', 'active'), true);
      for (final state in [
        'pending',
        'completed',
        'cancelled',
        'reschedule_pending',
      ]) {
        expect(canViewLocation(state, 'active'), false);
      }
      expect(canViewLocation('confirmed', 'published'), false);
      expect(canViewLocation('confirmed', 'published', instant: true), true);
    },
  );
}
