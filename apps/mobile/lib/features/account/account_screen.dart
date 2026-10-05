import '../../core/palestine_time.dart';
import '../../core/error_messages.dart';
import 'package:flutter/material.dart';
import '../../core/repository.dart';
import '../../core/translations.dart';
import '../../shared/data_form.dart';
import '../../core/notification_service.dart';
import '../../shared/driver_identity_fields.dart';

class AccountScreen extends StatefulWidget {
  final RideRepository repository;
  final Record? profile;
  final List<Record> notifications, violations;
  final Future<void> Function() onRefresh;
  const AccountScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.notifications,
    required this.violations,
    required this.onRefresh,
  });
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _error;
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await widget.onRefresh();
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
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 28,
                child: Icon(Icons.person_outline, size: 30),
              ),
              const SizedBox(height: 14),
              Text(
                widget.profile?['full_name'] ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(widget.repository.client.auth.currentUser?.email ?? ''),
              if (widget.profile?['suspended_until'] != null)
                Text(
                  '${language.text('الحجز معلق حتى', 'Booking suspended until')}: ${widget.profile!['suspended_until']}',
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (widget.profile?['role'] == 'driver') {
                          await _run(() async {
                            final details = await widget.repository
                                .driverIdentity();
                            if (!context.mounted) return;
                            final p = await showDriverIdentityForm(
                              context,
                              fullName: widget.profile?['full_name'] ?? '',
                              phone: details?['phone'],
                              dateOfBirth: details?['date_of_birth'],
                            );
                            if (p != null) {
                              await widget.repository.accountAction(
                                'driver_identity',
                                p,
                              );
                            }
                          });
                          return;
                        }
                        final p = await showDataForm(
                          context,
                          language.text('تعديل الحساب', 'Edit account'),
                          [
                            FormFieldSpec(
                              'full_name',
                              'الاسم الكامل',
                              'Full name',
                              initial: widget.profile?['full_name'] ?? '',
                            ),
                          ],
                        );
                        if (p != null) {
                          await _run(
                            () => widget.repository.accountAction('profile', {
                              ...p,
                              'language': language.english ? 'en' : 'ar',
                            }),
                          );
                        }
                      },
                child: Text(
                  widget.profile?['role'] == 'driver'
                      ? language.text(
                          'تعديل بيانات السائق',
                          'Edit driver identity',
                        )
                      : language.text('تعديل الاسم', 'Edit name'),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 20),
      Text(
        language.text('الإشعارات', 'Notifications'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      ...widget.notifications.map(
        (n) => ListTile(
          leading: Icon(
            n['read_at'] == null
                ? Icons.notifications_active_outlined
                : Icons.notifications_none,
          ),
          title: Text(
            n['kind'] == 'admin.message'
                ? n['body']
                : NotificationService.message(
                    n['kind'],
                    language.english,
                    body: n['body'],
                  ),
          ),
          subtitle: Text(
            palestineTime(DateTime.parse(n['created_at'])).toString(),
          ),
          onTap: () => _run(
            () => widget.repository.accountAction('read_notification', {
              'id': n['id'],
            }),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        language.text('المخالفات والاعتراضات', 'Violations & appeals'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        language.text(
          '٣ إلغاءات متأخرة أو حالات عدم حضور خلال ٣٠ يومًا تعلّق الحجوزات الجديدة ٧ أيام.',
          'Three late cancellations or no-shows within 30 days suspend new bookings for 7 days.',
        ),
      ),
      ...widget.violations.map(
        (v) => Card(
          child: ListTile(
            title: Text(
              v['kind'] == 'no_show'
                  ? language.text('عدم حضور', 'No-show')
                  : language.text('إلغاء متأخر', 'Late cancellation'),
            ),
            subtitle: Text(
              palestineTime(DateTime.parse(v['created_at'])).toString(),
            ),
            trailing: v['voided']
                ? const Icon(Icons.check)
                : TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final p = await showDataForm(
                              context,
                              language.text(
                                'اعتراض للإدارة',
                                'Appeal to administration',
                              ),
                              [
                                const FormFieldSpec(
                                  'message',
                                  'سبب الاعتراض',
                                  'Reason for appeal',
                                ),
                              ],
                            );
                            if (p != null) {
                              await _run(
                                () =>
                                    widget.repository.accountAction('appeal', {
                                      'violation_id': v['id'],
                                      'message': p['message'],
                                    }),
                              );
                            }
                          },
                    child: Text(language.text('اعتراض', 'Appeal')),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () async {
          await NotificationService.unregister();
          await widget.repository.client.auth.signOut();
        },
        icon: const Icon(Icons.logout),
        label: Text(language.text('تسجيل الخروج', 'Sign out')),
      ),
    ],
  );
}
