import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/driver_identity.dart';
import 'package:rukkab/core/rider_social_auth.dart';
import 'package:rukkab/core/notification_service.dart';

void main() {
  test('Driver identity validates full name and international phone', () {
    expect(validDriverName('أحمد'), isFalse);
    expect(validDriverName(' أحمد خالد '), isTrue);
    expect(normalizePhone('٠٠٩٧٠ ٥٩٩-١٢٣-٤٥٦'), '+970599123456');
    expect(validDriverPhone('0599123456'), isTrue);
    expect(normalizePhone('٠٥٩٩١٢٣٤٥٦'), '+970599123456');
    expect(normalizePhone('۰۵۹۹۱۲۳۴۵۶'), '+970599123456');
    expect(validDriverPhone('+970 599 123 456'), isTrue);
    expect(dateOnly(DateTime(1992, 2, 3)), '1992-02-03');
  });
  test('Social role gate reads AMR rather than editable user metadata', () {
    String token(String method) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({
          'amr': [
            {'method': method},
          ],
        })))}.signature';
    expect(isSocialSession(token('oauth')), isTrue);
    expect(isSocialSession(token('password')), isFalse);
    expect(isSocialSession('invalid'), isFalse);
  });
  test(
    'Renewal notifications identify document, car and expiry in both languages',
    () {
      final body = jsonEncode({
        'document_kind': 'insurance',
        'plate': 'TEST-7',
        'expires_on': '2026-11-01',
        'days_remaining': 7,
      });
      expect(
        NotificationService.message('document.renewal', false, body: body),
        contains('التأمين'),
      );
      expect(
        NotificationService.message('document.renewal', true, body: body),
        contains('7 days'),
      );
      expect(
        NotificationService.message('document.expired', true, body: body),
        contains('paused'),
      );
      expect(
        NotificationService.message('document.expired', false, body: 'bad'),
        contains('راجع'),
      );
    },
  );
}
