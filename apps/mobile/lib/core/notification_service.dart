import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static StreamSubscription<String>? _refresh;
  static bool available = false;
  static Stream<String> get foregroundMessages => available
      ? FirebaseMessaging.onMessage.map(
          (m) => m.notification?.body ?? 'ركاب | Rukkab',
        )
      : const Stream<String>.empty();
  static Future<void> initialize() async {
    // Native Firebase files are supplied by the project owner, never committed.
    if (!const bool.fromEnvironment('FIREBASE_ENABLED')) return;
    try {
      await Firebase.initializeApp();
      available = true;
    } catch (_) {
      available = false;
    }
  }

  static Future<void> register() async {
    if (!available) return;
    try {
      await _refresh?.cancel();
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _save(token);
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((
        token,
      ) async {
        try {
          await _save(token);
        } catch (_) {}
      });
    } catch (_) {
      /* The authenticated in-app inbox remains available if push setup fails. */
    }
  }

  static Future<void> _save(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    await Supabase.instance.client.rpc(
      'account_action',
      params: {
        'a': 'device_token',
        'p': {'token': token},
      },
    );
  }

  static Future<void> unregister() async {
    if (!available) return;
    await _refresh?.cancel();
    _refresh = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && Supabase.instance.client.auth.currentUser != null) {
        await Supabase.instance.client.rpc(
          'account_action',
          params: {
            'a': 'remove_device_token',
            'p': {'token': token},
          },
        );
      }
    } catch (_) {
      /* A temporary delivery failure must never prevent signing out. */
    }
  }

  static String message(String kind, bool en, {String? body}) {
    if (kind.startsWith('document.')) {
      try {
        final data = jsonDecode(body ?? '{}') as Map<String, dynamic>;
        final name =
            <String, String>{
              'license': en ? 'Driving license' : 'رخصة القيادة',
              'permit': en ? 'Permit' : 'البيرميت',
              'insurance': en ? 'Insurance' : 'التأمين',
              'registration': en ? 'Vehicle registration' : 'ترخيص السيارة',
            }[data['document_kind']] ??
            (en ? 'Document' : 'الوثيقة');
        final detail =
            '$name · ${data['plate'] ?? ''} · ${data['expires_on'] ?? ''}';
        return kind == 'document.renewal'
            ? (en
                  ? '$detail: renew before expiry (${data['days_remaining']} days remaining).'
                  : '$detail: جدد قبل الانتهاء (متبقي ${data['days_remaining']} يوم).')
            : (en
                  ? '$detail: expired. New driver work is paused until renewal and approval.'
                  : '$detail: انتهت الصلاحية. العمل الجديد متوقف لحين التجديد والاعتماد.');
      } catch (_) {
        return en ? 'Review your vehicle documents.' : 'راجع وثائق السيارة.';
      }
    }
    return {
          'booking.requested': en ? 'New booking request' : 'طلب حجز جديد',
          'booking.confirmed': en
              ? 'Your booking is confirmed'
              : 'تم تأكيد حجزك',
          'booking.near': en
              ? 'Your car is approaching the pickup point'
              : 'السيارة اقتربت من نقطة الركوب',
          'booking.reject': en
              ? 'Booking request declined; choose another trip'
              : 'رُفض طلب الحجز؛ يمكنك اختيار رحلة أخرى',
          'booking.accept_time': en
              ? 'New departure time accepted; booking confirmed'
              : 'تمت الموافقة على الموعد الجديد؛ الحجز مؤكد',
          'booking.decline_time': en
              ? 'New departure time declined; booking cancelled without a violation'
              : 'رُفض الموعد الجديد وأُلغي الحجز دون مخالفة',
          'booking.pickup': en
              ? 'The driver is heading to pickup'
              : 'بدأ السائق التوجه لنقطة الركوب',
          'booking.cancel': en ? 'Booking cancelled' : 'تم إلغاء الحجز',
          'booking.board': en ? 'Boarding confirmed' : 'تم تأكيد الركوب',
          'booking.alight': en ? 'Drop-off confirmed' : 'تم تأكيد النزول',
          'booking.arrive': en
              ? 'The car reached the pickup point'
              : 'وصلت السيارة إلى نقطة الركوب',
          'booking.no_show': en
              ? 'No-show recorded. You can appeal.'
              : 'تم تسجيل عدم حضور. يمكنك الاعتراض.',
          'trip.pickup': en
              ? 'The driver is heading to pickup'
              : 'بدأ السائق التوجه لنقطة الركوب',
          'trip.finish': en ? 'The trip is complete' : 'اكتملت الرحلة',
          'trip.start': en ? 'The trip started' : 'بدأت الرحلة',
          'trip.reschedule': en
              ? 'Departure changed. Confirm the new time.'
              : 'تغير موعد الانطلاق. وافق على الموعد الجديد.',
          'trip.cancel': en
              ? 'The driver cancelled the trip'
              : 'ألغى السائق الرحلة',
          'offer.created': en ? 'A driver made an offer' : 'وصلك عرض من سائق',
          'offer.accepted': en ? 'Your offer was accepted' : 'تم قبول عرضك',
          'account.warning': en
              ? 'One more violation may suspend bookings'
              : 'مخالفة إضافية قد توقف حجوزاتك',
          'account.suspended': en
              ? 'Bookings suspended for 7 days. You can appeal.'
              : 'تم تعليق الحجوزات ٧ أيام. يمكنك الاعتراض.',
          'request.expired': en
              ? 'No car available. Browse trips or post a request.'
              : 'لم تتوفر سيارة. استعرض الرحلات أو انشر طلبًا.',
        }[kind] ??
        (en ? 'You have a new notification' : 'لديك إشعار جديد');
  }
}
