import '../../core/error_messages.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../core/location_service.dart';
import '../../shared/data_form.dart';
import '../../shared/driver_identity_fields.dart';
import '../../core/palestine_time.dart';
import 'package:intl/intl.dart';
import '../../core/trip_seats.dart';
import '../../shared/trip_seat_summary.dart';
import 'driver_onboarding_screen.dart';

class DriverScreen extends StatefulWidget {
  final RideRepository repository;
  final DriverLocationService? locationService;
  final List<Record> vehicles, routes, stops;
  final Future<void> Function() onRefresh;
  const DriverScreen({
    super.key,
    required this.repository,
    this.locationService,
    required this.vehicles,
    required this.routes,
    required this.stops,
    required this.onRefresh,
  });
  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  late final DriverLocationService _location;
  String? _vehicleId, _error;
  bool _busy = false, _loading = true;
  int _loadRevision = 0;
  bool _ready = false;
  Record? _identity;
  List<Record> _trips = [], _documents = [], _permitRoutes = [];
  Record? get _vehicle =>
      widget.vehicles.where((v) => v['id'] == _vehicleId).firstOrNull;
  @override
  void initState() {
    super.initState();
    _location =
        widget.locationService ?? DriverLocationService(widget.repository);
    _vehicleId =
        widget.vehicles.where((v) => v['online'] == true).firstOrNull?['id'] ??
        widget.vehicles.firstOrNull?['id'];
    _load();
    if (_vehicle?['online'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _online(true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DriverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_vehicleId == null && widget.vehicles.isNotEmpty) {
      _vehicleId = widget.vehicles.first['id'];
      _load();
    } else if (oldWidget.vehicles != widget.vehicles) {
      _load();
      if (_vehicle?['online'] != true) {
        _location.stop();
      }
    }
  }

  @override
  void dispose() {
    _location.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final vehicleId = _vehicleId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identity = await widget.repository.driverIdentity();
      if (vehicleId == null) {
        if (mounted && revision == _loadRevision) {
          setState(() => _identity = identity);
        }
        return;
      }
      final ready = await widget.repository.vehicleReady(vehicleId);
      final rows = await Future.wait([
        widget.repository.vehicleTrips(vehicleId),
        widget.repository.list(
          'documents',
          key: 'vehicle_id',
          value: vehicleId,
        ),
        widget.repository.list(
          'vehicle_routes',
          key: 'vehicle_id',
          value: vehicleId,
          order: 'route_id',
        ),
      ]);
      if (mounted && revision == _loadRevision && vehicleId == _vehicleId) {
        setState(() {
          _identity = identity;
          _ready = ready;
          _trips = rows[0];
          _documents = rows[1];
          _permitRoutes = rows[2];
        });
      }
    } catch (e) {
      if (mounted && revision == _loadRevision) {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _registerVehicle() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriverOnboardingScreen(
          repository: widget.repository,
          onRefresh: widget.onRefresh,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _editIdentity() async => _run(() async {
    final profile = await widget.repository.profile();
    if (!mounted) return;
    final p = await showDriverIdentityForm(
      context,
      fullName: profile['full_name'],
      phone: _identity?['phone'],
      dateOfBirth: _identity?['date_of_birth'],
    );
    if (p != null) await widget.repository.accountAction('driver_identity', p);
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await widget.onRefresh();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _online(bool enabled) async => _run(() async {
    // Stop the local stream even if the server cannot acknowledge going offline.
    if (!enabled) await _location.stop();
    await widget.repository.accountAction('online', {
      'vehicle_id': _vehicleId,
      'online': enabled,
    });
    if (enabled) {
      try {
        await _location.start(_vehicleId!);
      } catch (e) {
        await widget.repository.accountAction('online', {
          'vehicle_id': _vehicleId,
          'online': false,
        });
        rethrow;
      }
    }
  });
  Future<void> _upload() async {
    final kinds = {
      'license': language.text('رخصة القيادة', 'Driving license'),
      'permit': language.text('البيرميت', 'Permit'),
      'insurance': language.text('التأمين', 'Insurance'),
      'registration': language.text('ترخيص السيارة', 'Registration'),
      'vehicle_photo': language.text('صورة السيارة', 'Vehicle photo'),
    };
    final p = await showDataForm(
      context,
      language.text('إضافة وثيقة', 'Upload document'),
      [FormFieldSpec('kind', 'الوثيقة', 'Document', options: kinds)],
    );
    if (p == null || !mounted) return;
    String? expiry;
    if (p['kind'] != 'vehicle_photo') {
      final date = await showDatePicker(
        context: context,
        initialDate: palestineNow().add(const Duration(days: 365)),
        firstDate: palestineNow(),
        lastDate: palestineNow().add(const Duration(days: 3650)),
      );
      if (date == null) return;
      expiry = date.toIso8601String().split('T').first;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: p['kind'] == 'vehicle_photo'
          ? ['jpg', 'jpeg', 'png']
          : ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    await _run(
      () => widget.repository.uploadDocument(
        vehicleId: _vehicleId!,
        kind: p['kind'],
        filename: result.files.single.name,
        bytes: result.files.single.bytes!,
        expiresOn: expiry,
      ),
    );
  }

  Future<void> _publish() async {
    final allowed = widget.routes
        .where((r) => _permitRoutes.any((x) => x['route_id'] == r['id']))
        .toList();
    final service = await showDataForm(
      context,
      language.text('نوع الرحلة', 'Trip service'),
      [
        FormFieldSpec(
          'service',
          'الخدمة',
          'Service',
          options: {
            'shared': language.text('مشترك', 'Shared'),
            if (_vehicle?['kind'] == 'taxi')
              'private': language.text('طلب خاص', 'Private'),
          },
        ),
      ],
    );
    if (service == null || !mounted) return;
    final shared = service['service'] == 'shared';
    if (shared && allowed.isEmpty) {
      setState(
        () => _error = language.text(
          'لا يوجد خط معتمد لسيارتك. تواصل مع الإدارة.',
          'No approved route for your vehicle. Contact administration.',
        ),
      );
      return;
    }
    final p = await showDataForm(
      context,
      language.text('انشر رحلة', 'Publish a trip'),
      [
        if (shared)
          FormFieldSpec(
            'route_id',
            'خط البيرميت',
            'Permit route',
            options: {
              for (final r in allowed)
                r['id']: r[language.english ? 'name_en' : 'name_ar'],
            },
          ),
        if (shared)
          FormFieldSpec(
            'direction',
            'الاتجاه',
            'Direction',
            options: {
              '1': language.text('ذهاب', 'Outbound'),
              '-1': language.text('عودة', 'Return'),
            },
          ),
        if (!shared) ...[
          const FormFieldSpec('origin', 'من', 'From'),
          const FormFieldSpec('destination', 'إلى', 'To'),
        ],
        FormFieldSpec(
          'instant',
          'توقيت الخدمة',
          'Availability',
          options: {
            'false': language.text('رحلة مسبقة', 'Scheduled trip'),
            'true': language.text('متاح الآن', 'Available now'),
          },
        ),
        FormFieldSpec(
          'starts_at',
          'موعد الانطلاق',
          'Departure',
          type: 'date',
          initial: DateTime.now().toUtc().toIso8601String(),
        ),
        FormFieldSpec(
          'ends_at',
          'نهاية الرحلة أو التوفر',
          'Trip or availability end',
          type: 'date',
          initial: DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        ),
        const FormFieldSpec(
          'price',
          'الأجرة بالشّيكل',
          'Fare in ILS',
          type: 'number',
        ),
        FormFieldSpec(
          'seat_limit',
          'المقاعد المتاحة للرحلة',
          'Trip capacity',
          type: 'number',
          initial: '${_vehicle?['capacity']}',
        ),
      ],
    );
    if (p == null) return;
    p['vehicle_id'] = _vehicleId;
    p['service'] = service['service'];
    p['instant'] = p['instant'] == 'true';
    if (shared) {
      p['direction'] = int.parse(p['direction']);
      final stops =
          widget.stops.where((s) => s['route_id'] == p['route_id']).toList()
            ..sort(
              (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
            );
      if (stops.length < 2) {
        setState(() => _error = 'ROUTE_STOPS_REQUIRED');
        return;
      }
      p['origin'] =
          stops[p['direction'] == 1 ? 0 : stops.length - 1]['name_ar'];
      p['destination'] =
          stops[p['direction'] == 1 ? stops.length - 1 : 0]['name_ar'];
    }
    await _run(() async {
      await widget.repository.rpc('publish_trip', {'p': p});
    });
  }

  @override
  Widget build(BuildContext context) =>
      _vehicle == null || _vehicle?['approved'] != true
      ? DriverOnboardingScreen(
          key: ValueKey(_vehicleId),
          repository: widget.repository,
          vehicle: _vehicle,
          onRefresh: widget.onRefresh,
        )
      : RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                language.text('أهلًا كابتن', 'Welcome, captain'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_identity?['phone'] == null ||
                  _identity?['date_of_birth'] == null) ...[
                Text(
                  language.text(
                    'أكمل الاسم الكامل وتاريخ الميلاد والهاتف قبل تسجيل السيارة أو بدء العمل.',
                    'Complete your full name, date of birth and phone before registering a vehicle or working.',
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _editIdentity,
                  child: Text(
                    language.text(
                      'إكمال بيانات السائق',
                      'Complete driver identity',
                    ),
                  ),
                ),
              ],
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        _identity?['phone'] == null ||
                        _identity?['date_of_birth'] == null
                    ? null
                    : _registerVehicle,
                icon: const Icon(Icons.directions_bus_outlined),
                label: Text(
                  language.text('تسجيل سيارة جديدة', 'Register a new vehicle'),
                ),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
              if (widget.vehicles.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _vehicleId,
                  items: widget.vehicles
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'] as String,
                          child: Text(v['plate']),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (id) {
                          _location.stop();
                          setState(() {
                            _vehicleId = id;
                            _ready = false;
                            _trips = [];
                            _documents = [];
                            _permitRoutes = [];
                          });
                          _load();
                        },
                  decoration: InputDecoration(
                    labelText: language.text('السيارة', 'Vehicle'),
                  ),
                ),
              if (_vehicle != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ready
                              ? language.text(
                                  'السيارة معتمدة',
                                  'Vehicle approved',
                                )
                              : language.text(
                                  'العمل متوقف: أكمل البيانات وجدد الوثائق واطلب اعتماد الإدارة',
                                  'Work paused: complete identity, renew documents and obtain admin approval',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${language.text('السعة', 'Capacity')}: ${_vehicle!['capacity']}',
                        ),
                        if (_vehicle!['review_note'] != null)
                          Text(_vehicle!['review_note']),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            language.text('متاح للعمل', 'Available for work'),
                          ),
                          subtitle: Text(
                            language.text(
                              'يشارك موقع السيارة أثناء العمل',
                              'Shares vehicle location while working',
                            ),
                          ),
                          value: _vehicle!['online'],
                          onChanged:
                              _busy ||
                                  _loading ||
                                  (!_ready && !_vehicle!['online'])
                              ? null
                              : _online,
                        ),
                      ],
                    ),
                  ),
                ),
                ..._documents.map(
                  (d) => ListTile(
                    leading: Icon(
                      d['verified']
                          ? Icons.verified_outlined
                          : Icons.pending_outlined,
                    ),
                    title: Text(
                      {
                            'license': language.text(
                              'رخصة القيادة',
                              'Driving license',
                            ),
                            'permit': language.text('البيرميت', 'Permit'),
                            'insurance': language.text('التأمين', 'Insurance'),
                            'registration': language.text(
                              'الترخيص',
                              'Registration',
                            ),
                            'vehicle_photo': language.text(
                              'صورة السيارة',
                              'Vehicle photo',
                            ),
                          }[d['kind']] ??
                          d['kind'],
                    ),
                    subtitle: Text(
                      '${language.text('صالح حتى', 'Expires')}: ${d['expires_on'] ?? '—'}',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    language.text(
                      'رفع أو تحديث وثيقة',
                      'Upload or replace document',
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                FilledButton.icon(
                  onPressed: _busy || _loading || _error != null || !_ready
                      ? null
                      : _publish,
                  icon: const Icon(Icons.add_road),
                  label: Text(
                    language.text(
                      'نشر رحلة وتحديد الأجرة',
                      'Publish a trip & set fare',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  language.text('رحلات السيارة', 'Vehicle trips'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  language.text(
                    'تشمل القائمة الرحلات الحالية وأحدث ١٠٠ رحلة منتهية.',
                    'All current trips and the latest 100 finished trips.',
                  ),
                ),
                ..._trips.map(
                  (trip) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${trip['origin']} ${language.text('←', '→')} ${trip['destination']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${language.status(trip['state'])} · ₪ ${trip['price']}',
                          ),
                          Text(
                            DateFormat('yyyy-MM-dd HH:mm').format(
                              palestineTime(DateTime.parse(trip['starts_at'])),
                            ),
                          ),
                          TripSeatSummary(
                            seats: TripSeats.fromTrip(trip),
                            privateTaxi: trip['service'] == 'private',
                          ),
                          if (trip['service'] != 'private')
                            Text(
                              '${language.text('ركاب الشارع', 'Street passengers')}: ${trip['street_passengers']}',
                            ),
                          if (trip['state'] == 'active' &&
                              TripSeats.fromTrip(trip).hasPassengersRemaining)
                            Text(
                              language.text(
                                'أنهِ حالات الركاب من الحجوزات وسجّل نزول ركاب الشارع قبل إنهاء الرحلة.',
                                'Resolve passenger bookings and record street passengers leaving before finishing the trip.',
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (trip['state'] == 'published')
                                _tripButton(
                                  trip,
                                  'start',
                                  language.text('بدء الرحلة', 'Start trip'),
                                ),
                              if (trip['state'] == 'active') ...[
                                if (trip['service'] != 'private') ...[
                                  _tripButton(
                                    trip,
                                    'street',
                                    language.text(
                                      'ركب من الشارع +١',
                                      'Street rider +1',
                                    ),
                                    {'delta': 1},
                                  ),
                                  _tripButton(
                                    trip,
                                    'street',
                                    language.text(
                                      'نزل من الشارع −١',
                                      'Street rider −1',
                                    ),
                                    {'delta': -1},
                                  ),
                                ],
                                _tripButton(
                                  trip,
                                  'finish',
                                  language.text('إنهاء الرحلة', 'Finish trip'),
                                ),
                              ],
                              if ([
                                'published',
                                'active',
                              ].contains(trip['state']))
                                _tripButton(
                                  trip,
                                  'cancel',
                                  language.text('إلغاء الرحلة', 'Cancel trip'),
                                ),
                              if (trip['state'] == 'published')
                                OutlinedButton(
                                  onPressed: _busy || _loading || _error != null
                                      ? null
                                      : () => _reschedule(trip),
                                  child: Text(
                                    language.text('تعديل الموعد', 'Reschedule'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
  Future<void> _actOnTrip(Record trip, String action, Record parameters) async {
    if (action == 'cancel') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(language.text('إلغاء الرحلة؟', 'Cancel this trip?')),
          content: Text(
            language.text(
              'سيُبلّغ الركاب ويُلغى حجزهم دون مخالفة عليهم.',
              'Passengers will be notified and their bookings cancelled without a violation.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(language.text('رجوع', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(language.text('إلغاء الرحلة', 'Cancel trip')),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    if (!mounted) return;
    await _run(
      () => widget.repository.tripAction(trip['id'], action, parameters),
    );
  }

  Future<void> _reschedule(Record trip) async {
    final p = await showDataForm(
      context,
      language.text(
        'تعديل الموعد · سيحتاج الركاب للموافقة',
        'Change time · passengers must reconfirm',
      ),
      [
        FormFieldSpec(
          'starts_at',
          'الانطلاق',
          'Departure',
          type: 'date',
          initial: trip['starts_at'],
        ),
        FormFieldSpec(
          'ends_at',
          'الوصول',
          'Arrival',
          type: 'date',
          initial: trip['ends_at'],
        ),
      ],
    );
    if (p == null || !mounted) return;
    final format = DateFormat('yyyy-MM-dd HH:mm');
    final unchanged = ['starts_at', 'ends_at'].every(
      (key) =>
          format.format(palestineTime(DateTime.parse(p[key]))) ==
          format.format(palestineTime(DateTime.parse(trip[key]))),
    );
    if (unchanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.text(
              'لم يتغير موعد الرحلة.',
              'The trip time is unchanged.',
            ),
          ),
        ),
      );
      return;
    }
    await _run(() => widget.repository.tripAction(trip['id'], 'reschedule', p));
  }

  Widget _tripButton(
    Record trip,
    String action,
    String label, [
    Record p = const {},
  ]) => OutlinedButton(
    onPressed:
        _busy ||
            _loading ||
            _error != null ||
            (action == 'street' &&
                p['delta'] == 1 &&
                TripSeats.fromTrip(trip).available == 0) ||
            (action == 'street' &&
                p['delta'] == -1 &&
                trip['street_passengers'] == 0) ||
            (action == 'cancel' && TripSeats.fromTrip(trip).occupied > 0) ||
            (action == 'finish' &&
                TripSeats.fromTrip(trip).hasPassengersRemaining)
        ? null
        : () => _actOnTrip(trip, action, p),
    child: Text(label),
  );
}
