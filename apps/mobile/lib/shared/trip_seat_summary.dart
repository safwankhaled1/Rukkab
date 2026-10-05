import 'package:flutter/material.dart';
import '../core/trip_seats.dart';
import '../core/translations.dart';

class TripSeatSummary extends StatelessWidget {
  final TripSeats seats;
  final bool privateTaxi;
  const TripSeatSummary({
    super.key,
    required this.seats,
    required this.privateTaxi,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xffeff7f3),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          language.text(
            'مقاعد الرحلة: ${seats.capacity}',
            'Trip seats: ${seats.capacity}',
          ),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _stat(
              context,
              language.text('المتاحة', 'Available'),
              seats.available,
            ),
            _stat(
              context,
              language.text('المحجوزة', 'Reserved'),
              seats.reserved,
            ),
            _stat(
              context,
              language.text('المشغولة', 'Occupied'),
              seats.occupied,
            ),
          ],
        ),
        if (seats.retained > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              language.text(
                '${seats.retained} مقاعد استخدمها ركاب نزلوا؛ لا تباع ثانية في هذه الرحلة المسبقة.',
                '${seats.retained} seats were used by passengers who left; they remain allocated for this scheduled trip.',
              ),
            ),
          ),
        if (privateTaxi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              language.text(
                'التكسي الخاص يحجز جميع المقاعد للطلب نفسه.',
                'A private taxi reserves all seats for one booking.',
              ),
            ),
          ),
      ],
    ),
  );
  Widget _stat(BuildContext context, String label, int value) => SizedBox(
    width: 100,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text('$value', style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}
