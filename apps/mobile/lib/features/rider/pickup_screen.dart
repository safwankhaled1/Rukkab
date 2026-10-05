import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';

class PickupScreen extends StatefulWidget {
  final RideRepository repository;
  final Record route;
  final List<Record> stops;
  final String destination;
  const PickupScreen({
    super.key,
    required this.repository,
    required this.route,
    required this.stops,
    required this.destination,
  });
  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  Record? _proposal;
  String? _error;
  bool _busy = false;
  LatLng point(Record s) => LatLng(
    (s['latitude'] as num).toDouble(),
    (s['longitude'] as num).toDouble(),
  );
  Future<void> _choose(LatLng location) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.repository.rpc('propose_pickup', {
        'r': widget.route['id'],
        'lat': location.latitude,
        'lng': location.longitude,
        'destination': widget.destination,
      });
      if (mounted) setState(() => _proposal = Map<String, dynamic>.from(p));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = language.text(
            'اختر نقطة أقرب للخط المعتمد أو موقفًا معروفًا.',
            'Choose a point closer to the approved route or an existing stop.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.route['path_geojson'] as Record?;
    final coordinates = (raw?['coordinates'] as List?) ?? [];
    final path = coordinates
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(language.text('نقطة ركوب مشتركة', 'Common pickup point')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              language.text(
                'اضغط قرب خط السيارة. نقترح نقطة مشتركة للركاب القريبين، أو أقرب موقف إذا لم يعتمد مسار الطريق بعد.',
                'Tap near the vehicle route. We suggest a shared meeting point, or a nearby station if road geometry is not approved yet.',
              ),
            ),
          ),
          Expanded(
            child: const bool.fromEnvironment('MAPS_ENABLED')
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: point(widget.stops.first),
                      zoom: 12,
                    ),
                    onTap: _busy ? null : _choose,
                    markers: {
                      ...widget.stops.map(
                        (s) => Marker(
                          markerId: MarkerId(s['id']),
                          position: point(s),
                          infoWindow: InfoWindow(
                            title: s[language.english ? 'name_en' : 'name_ar'],
                          ),
                          onTap: () => _choose(point(s)),
                        ),
                      ),
                      if (_proposal != null)
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: point(_proposal!),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueGreen,
                          ),
                        ),
                    },
                    polylines: {
                      if (path.isNotEmpty)
                        Polyline(
                          polylineId: const PolylineId('approved-road'),
                          points: path,
                          width: 5,
                          color: const Color(0xffb94e0e),
                        ),
                    },
                  )
                : ListView(
                    children: widget.stops
                        .where((s) => s['id'] != widget.destination)
                        .map(
                          (s) => ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(
                              s[language.english ? 'name_en' : 'name_ar'],
                            ),
                            onTap: () => _choose(point(s)),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_proposal != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(_proposal![language.english ? 'name_en' : 'name_ar']),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, _proposal),
                    child: Text(
                      language.text(
                        'اعتماد نقطة الركوب',
                        'Use this pickup point',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
