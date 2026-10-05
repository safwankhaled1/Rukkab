// Pure presentation rules. The server remains authoritative for every mutation.
class SeatSummary {
  final int capacity;
  final int streetPassengers;
  final int reserved;
  final int boarded;
  const SeatSummary({
    required this.capacity,
    required this.streetPassengers,
    required this.reserved,
    required this.boarded,
  });
  int get available =>
      (capacity - streetPassengers - reserved - boarded).clamp(0, capacity);
  int get onBoard => streetPassengers + boarded;
}

bool canViewLocation(
  String bookingState,
  String tripState, {
  bool instant = false,
}) =>
    ['confirmed', 'boarded'].contains(bookingState) &&
    (tripState == 'active' || (instant && tripState == 'published'));
bool canCancel(String state) =>
    ['pending', 'confirmed', 'reschedule_pending'].contains(state);

/// Mirror the wait for presentation; the server clock decides eligibility.
Duration? noShowWait(DateTime? arrival, DateTime? departure, DateTime now) {
  if (arrival == null || departure == null) return null;
  final afterWait = arrival.add(const Duration(minutes: 5));
  final eligibleAt = afterWait.isAfter(departure) ? afterWait : departure;
  final remaining = eligibleAt.difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
}
