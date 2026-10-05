import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/input_normalization.dart';
import 'package:rukkab/core/driver_identity.dart';

void main() {
  test('Arabic and Persian numbers parse without changing Arabic names', () {
    expect(num.parse(normalizeNumber('١٩')), 19);
    expect(num.parse(normalizeNumber('۵۵')), 55);
    expect(num.parse(normalizeNumber('١٬٢٥٠٫٥٠')), 1250.5);
    expect(normalizeDigits('صفوان خالد'), 'صفوان خالد');
    expect(validDriverName('صفوان خالد الرواشدة'), true);
    expect(normalizePhone('\u200f٠٥٩٢٢٠٨١٣٣'), '+970592208133');
  });
}
