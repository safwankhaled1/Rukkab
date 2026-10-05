import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'repository.dart';

class DriverLocationService {
  final RideRepository repository;
  StreamSubscription<Position>? _stream;
  DateTime? _sent;
  Timer? _heartbeat;
  DriverLocationService(this.repository);
  Future<void> start(String vehicleId) async {
    await stop();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppFailure('LOCATION_SERVICE_DISABLED');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const AppFailure('LOCATION_PERMISSION_REQUIRED');
    }
    LocationSettings settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 30,
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ركاب | Rukkab',
          notificationText:
              'مشاركة موقع السيارة أثناء العمل · Vehicle location sharing is active',
          enableWakeLock: true,
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    Future<void> send(Position position) async {
      if (_sent != null &&
          DateTime.now().difference(_sent!) < const Duration(seconds: 8)) {
        return;
      }
      _sent = DateTime.now();
      try {
        await repository.rpc('update_location', {
          'vid': vehicleId,
          'lat': position.latitude,
          'lng': position.longitude,
        });
      } catch (_) {
        /* Never queue stale coordinates for replay after reconnect. */
      }
    }

    await send(await Geolocator.getCurrentPosition(locationSettings: settings));
    _stream = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(send);
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await send(
          await Geolocator.getCurrentPosition(locationSettings: settings),
        );
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _stream?.cancel();
    _stream = null;
    _sent = null;
  }
}
