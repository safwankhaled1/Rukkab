import 'repository.dart';

/// Display the same allocation rules as available_seats; mutations remain server-authorized.
class TripSeats {
  final int capacity, occupied, reserved, retained;
  const TripSeats(this.capacity, this.occupied, this.reserved, this.retained);
  factory TripSeats.fromTrip(Record trip) {
    var occupied = (trip['street_passengers'] as num?)?.toInt() ?? 0;
    var reserved = 0;
    var retained = 0;
    for (final row in (trip['bookings'] as List?) ?? const []) {
      final seats = (row['seats'] as num).toInt();
      switch (row['state']) {
        case 'boarded':
          occupied += seats;
        case 'confirmed' || 'reschedule_pending':
          reserved += seats;
        // Scheduled allocations remain used even after a passenger leaves.
        case 'completed':
          if (trip['instant'] != true) retained += seats;
      }
    }
    return TripSeats(
      (trip['seat_limit'] as num).toInt(),
      occupied,
      reserved,
      retained,
    );
  }
  int get available =>
      (capacity - occupied - reserved - retained).clamp(0, capacity);
  bool get hasPassengersRemaining => occupied > 0 || reserved > 0;
}
