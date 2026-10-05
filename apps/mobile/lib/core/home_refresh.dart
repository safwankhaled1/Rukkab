/// Data dependencies for the home screen. GPS updates belong to tracking only.
const homeResources = {
  'profiles',
  'routes',
  'stops',
  'vehicles',
  'bookings',
  'ride_requests',
  'offers',
  'notifications',
  'violations',
};

Set<String> homeRefreshResources(String table) => switch (table) {
  'profiles' => {'profiles', 'vehicles'},
  'driver_details' => {'profiles', 'vehicles'},
  'routes' => {'routes', 'stops', 'vehicles'},
  'stops' => {'stops'},
  'vehicles' ||
  'documents' ||
  'vehicle_routes' ||
  'driver_applications' => {'vehicles'},
  // Bookings embed trip details; refreshing vehicles also updates driver trips.
  'trips' => {'bookings', 'vehicles', 'offers'},
  'bookings' => {'bookings', 'vehicles'},
  'ride_requests' => {'ride_requests', 'offers'},
  'offers' => {'offers', 'ride_requests'},
  'notifications' => {'notifications'},
  'violations' || 'appeals' => {'violations', 'profiles'},
  _ => {},
};

/// Coalesces events without dropping those received during an in-flight fetch.
class HomeRefreshQueue {
  final Set<String> _pending = {};
  void add(Iterable<String> resources) => _pending.addAll(resources);
  bool get isEmpty => _pending.isEmpty;
  Set<String> take() {
    final batch = Set<String>.of(_pending);
    _pending.clear();
    return batch;
  }
}
