import 'package:flutter/material.dart';

class AppLanguage extends ChangeNotifier {
  bool english = false;
  Locale get locale => Locale(english ? 'en' : 'ar');
  String text(String ar, String en) => english ? en : ar;
  void toggle() {
    english = !english;
    notifyListeners();
  }

  String status(String value) =>
      {
        'pending': text('بانتظار السائق', 'Awaiting driver'),
        'confirmed': text('حجز مؤكد', 'Confirmed'),
        'boarded': text('على متن السيارة', 'On board'),
        'completed': text('وصلت بالسلامة', 'Completed'),
        'cancelled': text('ملغي', 'Cancelled'),
        'rejected': text('لم يُقبل', 'Rejected'),
        'no_show': text('عدم حضور', 'No-show'),
        'reschedule_pending': text(
          'وافق على الموعد الجديد',
          'Confirm the new time',
        ),
        'searching': text('بانتظار سيارة', 'Searching'),
        'offered': text('الطلب وصل لسائق', 'Offered to driver'),
        'booked': text('محجوز', 'Booked'),
        'expired': text('لم تتوفر سيارة', 'No car available'),
        'published': text('رحلة منشورة', 'Published'),
        'active': text('رحلة جارية', 'Active'),
      }[value] ??
      value;
}

final language = AppLanguage();
