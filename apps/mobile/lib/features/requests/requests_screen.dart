import '../../core/palestine_time.dart';
import '../../core/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/fare_quote.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../shared/data_form.dart';

class RequestsScreen extends StatefulWidget {
  final RideRepository repository;
  final List<Record> requests, offers;
  final bool driver;
  final Future<void> Function() onRefresh;
  const RequestsScreen({
    super.key,
    required this.repository,
    required this.requests,
    required this.offers,
    required this.driver,
    required this.onRefresh,
  });
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<Record> _trips = [];
  Set<String> _ownVehicles = {};
  String? _error;
  bool _busy = false, _loading = true;
  int _loadRevision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests ||
        oldWidget.offers != widget.offers ||
        oldWidget.driver != widget.driver) {
      _load();
    }
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = widget.driver
          ? await widget.repository.list(
              'vehicles',
              key: 'driver_id',
              value: widget.repository.userId,
            )
          : <Record>[];
      final owned = vehicles
          .where((v) => v['driver_id'] == widget.repository.userId)
          .map((v) => v['id'] as String)
          .toSet();
      final trips = widget.driver
          ? await widget.repository.publishedTripsForVehicles(owned)
          : await widget.repository.tripsForOffers(
              widget.offers.map((offer) => offer['trip_id'] as String),
            );
      if (mounted && revision == _loadRevision) {
        setState(() {
          _trips = trips;
          _ownVehicles = owned;
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

  Future<void> _offer(Record request) async {
    final options = {
      for (final t in _trips.where(
        (t) =>
            _ownVehicles.contains(t['vehicle_id']) &&
            t['state'] == 'published' &&
            t['service'] == request['service'] &&
            (t['service'] == 'private' || t['route_id'] == request['route_id']),
      ))
        t['id'] as String:
            '${t['origin']} ${language.text('←', '→')} ${t['destination']} · ₪ ${t['price']}',
    };
    if (options.isEmpty) {
      setState(
        () => _error = language.text(
          'انشر رحلة مناسبة أولًا، ثم قدم عرضك عليها.',
          'Publish a matching trip first, then offer it.',
        ),
      );
      return;
    }
    final p = await showDataForm(
      context,
      language.text('قدّم عرضًا', 'Make an offer'),
      [
        FormFieldSpec(
          'trip_id',
          'رحلتك المناسبة',
          'Matching trip',
          options: options,
        ),
      ],
    );
    if (p == null) return;
    await _run(() async {
      await widget.repository.rpc('offer_action', {
        'p': {
          'action': 'create',
          'request_id': request['id'],
          'trip_id': p['trip_id'],
        },
      });
    });
  }

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

  String _offerStatus(String state) => switch (state) {
    'accepted' => language.text(
      'تم اختيار العرض وتأكيد الحجز',
      'Offer selected · booking confirmed',
    ),
    'rejected' => language.text(
      'لم يتم اختيار هذا العرض',
      'This offer was not selected',
    ),
    'pending' => language.text(
      'عرض بانتظار اختيار الراكب',
      'Awaiting passenger selection',
    ),
    _ => language.status(state),
  };

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      await widget.onRefresh();
      await _load();
    },
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.driver
              ? language.text(
                  'طلبات الركاب المناسبة',
                  'Eligible rider requests',
                )
              : language.text(
                  'طلباتك وعروض السائقين',
                  'Your requests & driver offers',
                ),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 15),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
        if (widget.requests.isEmpty)
          Text(language.text('لا توجد طلبات حاليًا', 'No requests yet')),
        ...widget.requests.map(
          (r) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['origin']} ${language.text('←', '→')} ${r['destination']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${language.status(r['state'])} · ${language.text('المقاعد', 'Seats')}: ${r['seats']}',
                  ),
                  Text(
                    DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(palestineTime(DateTime.parse(r['requested_at']))),
                  ),
                  if (widget.driver &&
                      r['rider_id'] != widget.repository.userId &&
                      r['mode'] == 'posted' &&
                      ['searching', 'offered'].contains(r['state']))
                    OutlinedButton(
                      onPressed: _busy || _loading || _error != null
                          ? null
                          : () => _offer(r),
                      child: Text(
                        language.text(
                          'قدّم عرضًا بوقت وسعر',
                          'Offer a time & fare',
                        ),
                      ),
                    ),
                  if (r['rider_id'] == widget.repository.userId &&
                      ['searching', 'offered'].contains(r['state']))
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.repository.accountAction(
                                'cancel_request',
                                {'id': r['id']},
                              ),
                            ),
                      child: Text(
                        language.text('إلغاء الطلب', 'Cancel request'),
                      ),
                    ),
                  ...widget.offers.where((o) => o['request_id'] == r['id']).map((
                    offer,
                  ) {
                    final trip = _trips
                        .where((t) => t['id'] == offer['trip_id'])
                        .firstOrNull;
                    final total = trip == null
                        ? null
                        : quotedTotal(
                            trip['price'],
                            trip['service'],
                            r['seats'],
                          );
                    final ends = DateTime.tryParse(trip?['ends_at'] ?? '');
                    final available =
                        trip != null &&
                        total != null &&
                        trip['state'] == 'published' &&
                        trip['service'] == r['service'] &&
                        ends != null &&
                        ends.isAfter(DateTime.now());
                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xffeff7f3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _offerStatus(offer['state'] as String),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${language.text('الأجرة الإجمالية', 'Total fare')}: ₪ ${total == null ? '—' : NumberFormat('#,##0.##').format(total)}',
                          ),
                          Text(
                            trip?['service'] == 'private'
                                ? language.text(
                                    'التكسي كامل · الدفع كاش',
                                    'Whole taxi · Pay cash',
                                  )
                                : language.text(
                                    'لـ ${r['seats']} مقاعد · الدفع كاش',
                                    'For ${r['seats']} seats · Pay cash',
                                  ),
                          ),
                          if (trip != null)
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm').format(
                                palestineTime(
                                  DateTime.parse(trip['starts_at']),
                                ),
                              ),
                            ),
                          if (offer['state'] == 'pending' &&
                              !_loading &&
                              !available)
                            Text(
                              language.text(
                                'العرض غير متاح الآن. اسحب لتحديث الخيارات.',
                                'This offer is unavailable. Pull to refresh options.',
                              ),
                            ),
                          if (r['rider_id'] == widget.repository.userId &&
                              offer['state'] == 'pending' &&
                              available &&
                              ['searching', 'offered'].contains(r['state']))
                            FilledButton(
                              onPressed: _busy || _loading || _error != null
                                  ? null
                                  : () => _run(() async {
                                      await widget.repository.rpc(
                                        'offer_action',
                                        {
                                          'p': {
                                            'action': 'accept',
                                            'offer_id': offer['id'],
                                          },
                                        },
                                      );
                                    }),
                              child: Text(
                                language.text(
                                  'اختيار العرض وتأكيد الحجز',
                                  'Choose offer & confirm booking',
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
