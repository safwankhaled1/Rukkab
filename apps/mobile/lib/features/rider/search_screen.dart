import '../../shared/journey_header.dart';
import '../../core/palestine_time.dart';
import '../../core/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import 'pickup_screen.dart';

class SearchScreen extends StatefulWidget {
  final RideRepository repository;
  final List<Record> routes, stops;
  final VoidCallback onBooked;
  const SearchScreen({
    super.key,
    required this.repository,
    required this.routes,
    required this.stops,
    required this.onBooked,
  });
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _criteriaVersion = 0;
  void _invalidate() {
    _criteriaVersion++;
    _results = [];
    _searched = false;
    _error = null;
  }

  Record? _pickup;
  String? _route, _origin, _destination;
  String _service = 'shared';
  int _seats = 1;
  bool _instant = true, _busy = false, _searched = false;
  List<Record> _results = [];
  String? _error;
  DateTime _time = palestineNow().add(const Duration(hours: 1));
  final _from = TextEditingController(), _to = TextEditingController();
  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  List<Record> get _routeStops =>
      widget.stops.where((s) => s['route_id'] == _route).toList();
  Record? get _start =>
      _routeStops.where((s) => s['id'] == _origin).firstOrNull;
  Future<Record> _payload(String service, {num? price}) async {
    double lat =
            (_pickup?['latitude'] as num?)?.toDouble() ??
            (_start?['latitude'] as num?)?.toDouble() ??
            double.nan,
        lng =
            (_pickup?['longitude'] as num?)?.toDouble() ??
            (_start?['longitude'] as num?)?.toDouble() ??
            double.nan;
    if (service == 'private' && _service == 'private') {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const AppFailure('LOCATION_PERMISSION_REQUIRED');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const AppFailure('LOCATION_PERMISSION_REQUIRED');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      lat = position.latitude;
      lng = position.longitude;
    }
    if (!lat.isFinite || !lng.isFinite) {
      throw const AppFailure('PICKUP_REQUIRED');
    }
    return {
      'origin': _service == 'private'
          ? _from.text
          : _pickup?['name_ar'] ??
                _routeStops
                    .where((s) => s['id'] == _origin)
                    .firstOrNull?['name_ar'] ??
                _from.text,
      'destination': _service == 'private'
          ? _to.text
          : _routeStops
                    .where((s) => s['id'] == _destination)
                    .firstOrNull?['name_ar'] ??
                _to.text,
      if (service != 'private') 'route_id': _route,
      if (service != 'private') 'origin_stop_id': _origin,
      if (service != 'private') 'destination_stop_id': _destination,
      'service': service,
      'seats': _seats,
      'latitude': lat,
      'longitude': lng,
      'requested_at': (_instant ? DateTime.now() : _time)
          .toUtc()
          .toIso8601String(),
      'mode': _instant ? 'instant' : 'posted',
      'quoted_price': ?price,
    };
  }

  bool _valid() {
    if (_service != 'private' &&
        (_origin == null || _destination == null || _origin == _destination)) {
      setState(
        () => _error = language.text(
          'اختر نقطتي ركوب ونزول مختلفتين',
          'Choose different pickup and drop-off stops',
        ),
      );
      return false;
    }
    if (_service == 'private' &&
        (_from.text.trim().isEmpty || _to.text.trim().isEmpty)) {
      setState(
        () => _error = language.text(
          'أدخل الانطلاق والوجهة',
          'Enter pickup and destination',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _search() async {
    if (!_valid()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final version = _criteriaVersion;
    try {
      final p = await _payload(_service);
      p['service'] = _service;
      p.remove('mode');
      p.remove('requested_at');
      p['instant'] = _instant;
      if (!_instant) p['day'] = DateFormat('yyyy-MM-dd').format(_time);
      final result = await widget.repository.search(p);
      if (mounted && version == _criteriaVersion) {
        setState(() {
          _results = result;
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _book(Record trip) async {
    if (!_valid() || !_results.contains(trip)) return;
    final version = _criteriaVersion;
    setState(() => _busy = true);
    try {
      final p = await _payload(trip['service'], price: trip['price'] as num);
      if (!mounted || version != _criteriaVersion) return;
      if (_instant) {
        await widget.repository.rpc('post_request', {'p': p});
      } else {
        await widget.repository.rpc('request_booking', {
          'p': {
            'trip_id': trip['id'],
            'seats': _seats,
            'origin_stop_id': _origin,
            'destination_stop_id': _destination,
            'origin': p['origin'],
            'destination': p['destination'],
            'pickup_latitude': p['latitude'],
            'pickup_longitude': p['longitude'],
          },
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language.text(
                'أُرسل الطلب. الحجز يتأكد بعد موافقة السائق.',
                'Request sent. Your booking is confirmed after driver approval.',
              ),
            ),
          ),
        );
        widget.onBooked();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    if (!_valid()) return;
    String service = _service;
    if (service == 'both') {
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            language.text('نوع الطلب المنشور', 'Posted request type'),
          ),
          children: ['shared', 'private']
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Text(
                    s == 'shared'
                        ? language.text('مشترك', 'Shared')
                        : language.text('طلب خاص', 'Private'),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (chosen == null || !mounted) return;
      service = chosen;
    }
    final version = _criteriaVersion;
    setState(() => _busy = true);
    try {
      final p = await _payload(service);
      if (!mounted || version != _criteriaVersion) return;
      p['mode'] = 'posted';
      await widget.repository.rpc('post_request', {'p': p});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language.text(
                'تم نشر طلبك للسائقين المناسبين',
                'Your request was posted to eligible drivers',
              ),
            ),
          ),
        );
        widget.onBooked();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      JourneyHeader(
        title: language.text('لوين رحلتك اليوم؟', 'Where are you heading?'),
        subtitle: language.text(
          'اختار خطك، شوف الأجرة، واحجز مقعدك. الدفع كاش للسائق.',
          'Choose your route, see the fare, and book your seat. Pay your driver in cash.',
        ),
      ),
      const SizedBox(height: 24),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'shared',
            label: Text(language.text('مشترك', 'Shared')),
            icon: const Icon(Icons.groups_outlined),
          ),
          ButtonSegment(
            value: 'private',
            label: Text(language.text('طلب', 'Private')),
            icon: const Icon(Icons.local_taxi_outlined),
          ),
          ButtonSegment(
            value: 'both',
            label: Text(language.text('الاثنين', 'Both')),
          ),
        ],
        selected: {_service},
        onSelectionChanged: (s) => setState(() {
          _invalidate();
          _pickup = null;
          _service = s.first;
        }),
      ),
      const SizedBox(height: 18),
      if (_service != 'private' && widget.routes.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.route_outlined, color: Color(0xffb94e0e)),
                const SizedBox(height: 8),
                Text(
                  language.text(
                    'الخطوط قيد الاعتماد',
                    'Routes are awaiting approval',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  language.text(
                    'ستظهر هنا الخطوط والمحطات بعد اعتمادها من الإدارة. يمكنك اختيار التكسي الخاص عند توفره.',
                    'Approved routes and stops will appear here. You can choose a private taxi when available.',
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_service != 'private') ...[
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _route,
          decoration: InputDecoration(
            labelText: language.text('الخط', 'Route'),
          ),
          items: widget.routes
              .map(
                (r) => DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(r[language.english ? 'name_en' : 'name_ar']),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _invalidate();
            _route = v;
            _origin = null;
            _destination = null;
            _pickup = null;
            _results = [];
          }),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('from-$_route-$_origin'),
          isExpanded: true,
          initialValue: _origin,
          decoration: InputDecoration(
            labelText: language.text('نقطة الركوب', 'Pickup point'),
          ),
          items: _routeStops
              .map(
                (s) => DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text(s[language.english ? 'name_en' : 'name_ar']),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _invalidate();
            _origin = v;
            _pickup = null;
          }),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('to-$_route'),
          isExpanded: true,
          initialValue: _destination,
          decoration: InputDecoration(
            labelText: language.text('نقطة النزول', 'Drop-off point'),
          ),
          items: _routeStops
              .map(
                (s) => DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text(s[language.english ? 'name_en' : 'name_ar']),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _invalidate();
            _pickup = null;
            _destination = v;
          }),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed:
              _route == null || _destination == null || _routeStops.length < 2
              ? null
              : () async {
                  final result = await Navigator.push<Record>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PickupScreen(
                        repository: widget.repository,
                        route: widget.routes.firstWhere(
                          (r) => r['id'] == _route,
                        ),
                        stops: _routeStops,
                        destination: _destination!,
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _invalidate();
                      _pickup = result;
                      _origin = result['origin_stop_id'];
                    });
                  }
                },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(
            language.text(
              'اختيار نقطة على خط السيارة',
              'Choose a point on the route',
            ),
          ),
        ),
        if (_pickup != null)
          Text(_pickup![language.english ? 'name_en' : 'name_ar']),
        Text(
          language.text(
            'نقاط الركوب على الخط مشتركة للركاب القريبين.',
            'Passengers nearby use the same route pickup points.',
          ),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
      if (_service == 'private') ...[
        TextField(
          controller: _from,
          onChanged: (_) => setState(_invalidate),
          decoration: InputDecoration(
            labelText: language.text('من وين؟', 'Pickup address'),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _to,
          onChanged: (_) => setState(_invalidate),
          decoration: InputDecoration(
            labelText: language.text('لوين؟', 'Destination'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Text(language.text('عدد الركاب', 'Passengers')),
          const Spacer(),
          IconButton(
            onPressed: _seats > 1
                ? () => setState(() {
                    _invalidate();
                    _seats--;
                  })
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$_seats'),
          IconButton(
            onPressed: _seats < 80
                ? () => setState(() {
                    _invalidate();
                    _seats++;
                  })
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(language.text('رحلة الآن', 'Ride now')),
        subtitle: Text(
          _instant
              ? language.text(
                  'نبحث عن أقرب سيارة مناسبة',
                  'Find the nearest eligible car',
                )
              : language.text(
                  'استعرض الرحلات المنشورة',
                  'Browse scheduled trips',
                ),
        ),
        value: _instant,
        onChanged: (v) => setState(() {
          _invalidate();
          _instant = v;
        }),
      ),
      if (!_instant)
        TextButton.icon(
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _time,
              firstDate: palestineNow(),
              lastDate: palestineNow().add(const Duration(days: 90)),
            );
            if (date == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_time),
            );
            if (time != null) {
              setState(() {
                _invalidate();
                _time = palestineWallTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }
          },
          icon: const Icon(Icons.calendar_month),
          label: Text(
            '${DateFormat('yyyy-MM-dd HH:mm').format(_time)} · ${language.text('توقيت فلسطين', 'Palestine time')}',
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.deepOrange),
          ),
        ),
      FilledButton.icon(
        onPressed: _busy ? null : _search,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.search),
        label: Text(
          language.text('شوف السيارات والرحلات', 'Find cars & trips'),
        ),
      ),
      const SizedBox(height: 18),
      ..._results.map(
        (trip) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      trip['service'] == 'private'
                          ? Icons.local_taxi
                          : Icons.directions_bus,
                      color: const Color(0xffb94e0e),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${trip['origin']} ← ${trip['destination']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '₪ ${trip['service'] == 'private' ? trip['price'] : (trip['price'] as num) * _seats}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${language.text('المقاعد المتاحة', 'Available seats')}: ${trip['available_seats']} · ${trip['plate']}',
                ),
                Text(
                  trip['service'] == 'private'
                      ? language.text(
                          'السعر للسيارة كاملة',
                          'Price for the whole car',
                        )
                      : language.text(
                          'الإجمالي لـ $_seats مقاعد • ₪ ${trip['price']} للمقعد',
                          'Total for $_seats seats • ₪ ${trip['price']} per seat',
                        ),
                ),
                Text(
                  DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format(palestineTime(DateTime.parse(trip['starts_at']))),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : () => _book(trip),
                  child: Text(
                    language.text('إرسال طلب الحجز', 'Request booking'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_searched && _results.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            language.text(
              'ما في سيارة مناسبة حاليًا. انشر طلبك أو جرّب الرحلات المسبقة.',
              'No eligible car is available. Post a request or browse scheduled trips.',
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _busy ? null : _post,
        icon: const Icon(Icons.campaign_outlined),
        label: Text(language.text('انشر طلب سيارة', 'Post a ride request')),
      ),
    ],
  );
}
