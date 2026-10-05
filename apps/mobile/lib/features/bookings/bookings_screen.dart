import '../../core/palestine_time.dart';
import '../../core/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../core/booking_rules.dart';
import '../../shared/no_show_button.dart';
import '../tracking/tracking_screen.dart';

class BookingsScreen extends StatefulWidget {
  final RideRepository repository;
  final List<Record> bookings;
  final bool driver;
  final Future<void> Function() onRefresh;
  const BookingsScreen({
    super.key,
    required this.repository,
    required this.bookings,
    required this.driver,
    required this.onRefresh,
  });
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String? _busy, _error;
  Future<void> _action(Record booking, String action) async {
    if (action == 'cancel' || action == 'no_show') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(language.text('تأكيد العملية', 'Confirm action')),
          content: Text(
            action == 'cancel'
                ? language.text(
                    'الإلغاء مجاني. الإلغاءات المتأخرة المتكررة قد توقف الحجوزات ٧ أيام.',
                    'Cancellation is free. Repeated late cancellations can suspend bookings for 7 days.',
                  )
                : language.text(
                    'تأكد من الوصول لنقطة هذا الراكب والانتظار ٥ دقائق.',
                    'Confirm arrival at this rider’s pickup point and wait 5 minutes.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(language.text('رجوع', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(language.text('تأكيد', 'Confirm')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _busy = booking['id'];
      _error = null;
    });
    try {
      if (action == 'accept') {
        await widget.repository.rpc('accept_booking', {'bid': booking['id']});
      } else {
        await widget.repository.bookingAction(booking['id'], action);
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: widget.onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          language.text('حجوزاتك', 'Your bookings'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 15),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
        if (widget.bookings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Text(language.text('ما عندك حجوزات لسه', 'No bookings yet')),
          ),
        ...widget.bookings.map((b) {
          final trip = Map<String, dynamic>.from(b['trips'] ?? {});
          final state = b['state'] as String;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.english
                        ? '${trip['origin']} → ${trip['destination']}'
                        : '${trip['origin']} ← ${trip['destination']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    language.status(state),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (widget.driver)
                    Text(
                      '${language.text('الراكب', 'Rider')}: ${b['profiles']?['full_name'] ?? b['rider_id']}',
                    ),
                  Text(
                    '${language.text('المقاعد', 'Seats')}: ${b['seats']} · ₪ ${b['total_price']} · ${language.text('كاش', 'Cash')}',
                  ),
                  if (b['pickup_text'] != null && b['pickup_text'] != '')
                    Text(
                      '${language.text('الركوب', 'Pickup')}: ${b['pickup_text']}',
                    ),
                  if (trip['starts_at'] != null)
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(
                        palestineTime(DateTime.parse(trip['starts_at'])),
                      ),
                    ),
                  if (widget.driver &&
                      state == 'confirmed' &&
                      trip['state'] == 'published')
                    Text(
                      language.text(
                        'ابدأ الرحلة من صفحة السائق لتأكيد الركوب.',
                        'Start the trip from the driver page before confirming boarding.',
                      ),
                    ),
                  if (!widget.driver &&
                      state == 'reschedule_pending' &&
                      trip['previous_starts_at'] != null)
                    Text(
                      '${language.text('الموعد السابق', 'Previous departure')}: ${DateFormat('yyyy-MM-dd HH:mm').format(palestineTime(DateTime.parse(trip['previous_starts_at'])))}',
                    ),
                  if (!widget.driver && state == 'reschedule_pending')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        language.text(
                          'تغير موعد الرحلة. اختر قبول الموعد أعلاه أو رفضه؛ الرفض يحرر مقاعدك دون مخالفة.',
                          'The departure time changed. Accept the time above or decline it; declining releases your seats without a violation.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.driver && state == 'pending') ...[
                        _button(b, 'accept', language.text('قبول', 'Accept')),
                        _button(b, 'reject', language.text('رفض', 'Reject')),
                      ],
                      if (widget.driver &&
                          state == 'confirmed' &&
                          trip['state'] == 'active') ...[
                        _button(
                          b,
                          'pickup',
                          language.text('بطريقي للراكب', 'Heading to rider'),
                        ),
                        _button(
                          b,
                          'arrive',
                          language.text(
                            'وصلت نقطة الركوب',
                            'Arrived at pickup',
                          ),
                        ),
                        _button(
                          b,
                          'board',
                          language.text('تأكيد الركوب', 'Confirm boarding'),
                        ),
                        NoShowButton(
                          key: ValueKey('no-show-${b['id']}'),
                          arrivedAt: DateTime.tryParse(b['arrived_at'] ?? ''),
                          startsAt: DateTime.tryParse(trip['starts_at'] ?? ''),
                          busy: _busy != null,
                          onPressed: () => _action(b, 'no_show'),
                        ),
                      ],
                      if (widget.driver && state == 'boarded')
                        _button(
                          b,
                          'alight',
                          language.text('تأكيد النزول', 'Confirm drop-off'),
                        ),
                      if (!widget.driver && state == 'reschedule_pending') ...[
                        _button(
                          b,
                          'accept_time',
                          language.text('موافق على الموعد', 'Accept new time'),
                        ),
                        _button(
                          b,
                          'decline_time',
                          language.text(
                            'الموعد ما بناسبني',
                            'Decline new time',
                          ),
                        ),
                      ],
                      if (canCancel(state))
                        _button(b, 'cancel', language.text('إلغاء', 'Cancel')),
                      if (!widget.driver &&
                          canViewLocation(
                            state,
                            trip['state'] ?? '',
                            instant: trip['instant'] == true,
                          ))
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrackingScreen(
                                repository: widget.repository,
                                bookingId: b['id'],
                                vehicleId: trip['vehicle_id'],
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.location_on_outlined),
                          label: Text(
                            language.text('وين السيارة؟', 'Track car'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    ),
  );
  Widget _button(Record b, String action, String label) => OutlinedButton(
    onPressed: _busy != null ? null : () => _action(b, action),
    child: Text(label),
  );
}
