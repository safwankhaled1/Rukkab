// Keep event copy readable for recipients on either side of a booking.
const copy: Record<string, [string, string]> = {
  "booking.requested": ["طلب حجز جديد", "New booking request"],
  "booking.confirmed": ["تم تأكيد الحجز", "Booking confirmed"],
  "booking.reject": [
    "رُفض طلب الحجز؛ يمكنك اختيار رحلة أخرى",
    "Booking request declined; choose another trip",
  ],
  "booking.cancel": ["تم إلغاء الحجز", "Booking cancelled"],
  "booking.pickup": [
    "بدأ السائق التوجه لنقطة الركوب",
    "The driver is heading to pickup",
  ],
  "booking.arrive": [
    "وصلت السيارة إلى نقطة الركوب",
    "The car reached the pickup point",
  ],
  "booking.near": [
    "السيارة اقتربت من نقطة الركوب",
    "The car is approaching pickup",
  ],
  "booking.board": ["تم تأكيد الركوب", "Boarding confirmed"],
  "booking.alight": ["تم تأكيد النزول", "Drop-off confirmed"],
  "booking.no_show": [
    "تم تسجيل عدم حضور؛ يمكنك الاعتراض",
    "No-show recorded; you can appeal",
  ],
  "booking.accept_time": [
    "تمت الموافقة على الموعد الجديد؛ الحجز مؤكد",
    "New departure time accepted; booking confirmed",
  ],
  "booking.decline_time": [
    "رُفض الموعد الجديد وأُلغي الحجز دون مخالفة",
    "New departure time declined; booking cancelled without a violation",
  ],
  "trip.start": ["بدأت الرحلة", "The trip started"],
  "trip.pickup": [
    "بدأ السائق التوجه لنقطة الركوب",
    "The driver is heading to pickup",
  ],
  "trip.finish": ["اكتملت الرحلة", "The trip is complete"],
  "trip.reschedule": [
    "تغير موعد الانطلاق؛ راجع الموعد الجديد",
    "Departure changed; review the new time",
  ],
  "trip.cancel": ["ألغى السائق الرحلة", "The driver cancelled the trip"],
  "offer.created": ["وصلك عرض من سائق", "A driver made an offer"],
  "offer.accepted": [
    "تم قبول العرض والحجز مؤكد",
    "Offer accepted; booking confirmed",
  ],
  "account.warning": [
    "مخالفة إضافية قد توقف الحجوزات",
    "One more violation may suspend bookings",
  ],
  "account.suspended": [
    "تم تعليق الحجوزات ٧ أيام؛ يمكنك الاعتراض",
    "Bookings suspended for 7 days; you can appeal",
  ],
  "request.expired": [
    "لم تتوفر سيارة؛ استعرض الرحلات أو انشر طلبًا",
    "No car available; browse trips or post a request",
  ],
};
export function rideMessage(kind: string, en: boolean): string {
  return (
    copy[kind]?.[en ? 1 : 0] ??
    (en ? "Your ride was updated" : "تم تحديث رحلتك")
  );
}
