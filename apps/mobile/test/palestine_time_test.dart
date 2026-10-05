import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/palestine_time.dart';

void main() {
  test('Summer and winter schedules preserve Palestinian wall time', () {
    for (final month in [1, 7, 10]) {
      final local = palestineWallTime(2026, month, 4, 8, 30);
      final restored = palestineTime(local.toUtc());
      expect(restored.hour, 8);
      expect(restored.minute, 30);
      expect(restored.month, month);
      expect(local.toUtc().hour, isNot(8));
    }
  });
}
