import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/notification_service.dart';

void main() {
  test(
    'Reschedule responses explain confirmation or cancellation without a penalty',
    () {
      expect(
        NotificationService.message('booking.accept_time', true),
        contains('confirmed'),
      );
      expect(
        NotificationService.message('booking.decline_time', true),
        contains('without a violation'),
      );
      expect(
        NotificationService.message('booking.decline_time', false),
        contains('دون مخالفة'),
      );
      expect(
        NotificationService.message('booking.reject', true),
        contains('another trip'),
      );
      expect(
        NotificationService.message('booking.no_show', true),
        contains('appeal'),
      );
    },
  );
  test(
    'Pickup and trip completion have readable Arabic and English notification copy',
    () {
      for (final kind in ['booking.pickup', 'trip.pickup', 'trip.finish']) {
        expect(
          NotificationService.message(kind, false),
          isNot(NotificationService.message('unknown', false)),
        );
        expect(
          NotificationService.message(kind, true),
          isNot(NotificationService.message('unknown', true)),
        );
      }
    },
  );
}
