import 'package:flutter_test/flutter_test.dart';
import 'package:rukkab/core/home_refresh.dart';

void main() {
  test('GPS and unrelated tables do not reload home data', () {
    expect(homeRefreshResources('vehicle_locations'), isEmpty);
    expect(homeRefreshResources('audit_log'), isEmpty);
    expect(homeRefreshResources('notifications'), {'notifications'});
  });

  test('trip and approval events refresh dependent driver and rider data', () {
    expect(
      homeRefreshResources('trips'),
      containsAll(['bookings', 'vehicles', 'offers']),
    );
    expect(homeRefreshResources('documents'), {'vehicles'});
    expect(homeRefreshResources('vehicle_routes'), {'vehicles'});
    expect(homeRefreshResources('profiles'), contains('profiles'));
  });

  test(
    'events received while fetching remain queued and duplicates coalesce',
    () {
      final queue = HomeRefreshQueue();
      queue.add(homeResources);
      final inFlight = queue.take();
      queue.add(homeRefreshResources('bookings'));
      queue.add(homeRefreshResources('bookings'));
      queue.add(homeRefreshResources('notifications'));
      expect(inFlight, homeResources);
      expect(queue.take(), {'bookings', 'vehicles', 'notifications'});
      expect(queue.isEmpty, isTrue);
    },
  );
}
