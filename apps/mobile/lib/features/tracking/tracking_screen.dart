import '../../core/palestine_time.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../core/booking_rules.dart';

class TrackingScreen extends StatefulWidget {
  final RideRepository repository;
  final String bookingId, vehicleId;
  const TrackingScreen({
    super.key,
    required this.repository,
    required this.bookingId,
    required this.vehicleId,
  });
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Record? _location, _estimate;
  DateTime? _estimatedAt;
  String? _error;
  Timer? _timer;
  GoogleMapController? _map;
  bool _ended = false, _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final booking = await widget.repository.client
          .from('bookings')
          .select('state,trips(state,instant)')
          .eq('id', widget.bookingId)
          .single();
      if (!canViewLocation(
        booking['state'],
        (booking['trips'] as Record)['state'],
        instant: (booking['trips'] as Record)['instant'] == true,
      )) {
        if (mounted) {
          setState(() {
            _location = null;
            _ended = true;
          });
        }
        _timer?.cancel();
        return;
      }
      final rows = await widget.repository.list(
        'vehicle_locations',
        key: 'vehicle_id',
        value: widget.vehicleId,
        order: 'updated_at',
      );
      if (mounted) {
        setState(() {
          _location = rows.firstOrNull;
          _error = null;
        });
      }
      if (_location != null) {
        _map?.animateCamera(CameraUpdate.newLatLng(_point));
      }
      if (const bool.fromEnvironment('ESTIMATES_ENABLED') &&
          (_estimatedAt == null ||
              DateTime.now().difference(_estimatedAt!) >
                  const Duration(seconds: 30))) {
        _estimatedAt = DateTime.now();
        try {
          final response = await widget.repository.client.functions.invoke(
            'estimate-arrival',
            body: {'booking_id': widget.bookingId},
          );
          if (mounted) {
            setState(
              () => _estimate = Map<String, dynamic>.from(response.data),
            );
          }
        } catch (_) {
          if (mounted) setState(() => _estimate = null);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = language.text(
            'تعذّر تحديث الموقع. راجع وقت آخر تحديث.',
            'Could not refresh location. Check the last update time.',
          ),
        );
      }
    } finally {
      _loading = false;
    }
  }

  LatLng get _point => LatLng(
    (_location!['latitude'] as num).toDouble(),
    (_location!['longitude'] as num).toDouble(),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(language.text('موقع السيارة', 'Car location'))),
    body: _ended
        ? Center(
            child: Text(
              language.text(
                'انتهى التتبع لهذا الحجز',
                'Tracking has ended for this booking',
              ),
            ),
          )
        : Column(
            children: [
              if (_estimate != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${language.text('وصول تقديري حسب الخرائط', 'Estimated arrival from maps')}: ${_estimate!['minutes']} ${language.text('دقيقة', 'min')}',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              Expanded(
                child: _location == null
                    ? Center(
                        child: Text(
                          language.text(
                            'بانتظار تحديث موقع السائق',
                            'Waiting for the driver’s location',
                          ),
                        ),
                      )
                    : const bool.fromEnvironment('MAPS_ENABLED')
                    ? GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _point,
                          zoom: 14,
                        ),
                        onMapCreated: (c) => _map = c,
                        markers: {
                          Marker(
                            markerId: const MarkerId('vehicle'),
                            position: _point,
                            infoWindow: InfoWindow(
                              title: language.text('سيارتك', 'Your car'),
                            ),
                          ),
                        },
                        myLocationButtonEnabled: false,
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 60,
                              color: Color(0xffb94e0e),
                            ),
                            Text(
                              '${_location!['latitude']}, ${_location!['longitude']}',
                            ),
                            Text(
                              language.text(
                                'عرض الخريطة يحتاج مفتاح Google Maps',
                                'Map display requires a Google Maps key',
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_location != null)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    '${language.text('آخر تحديث', 'Last update')}: ${palestineTime(DateTime.parse(_location!['updated_at']))}\n${DateTime.now().difference(DateTime.parse(_location!['updated_at'])).inMinutes >= 2 ? language.text('الموقع قديم؛ قد تكون السيارة تحركت.', 'Location is stale; the car may have moved.') : ''}',
                  ),
                ),
            ],
          ),
  );
}
