/// Display only. The server recomputes and reserves the final fare and seats.
num? quotedTotal(Object? price, String? service, Object? seats) {
  final unit = num.tryParse('$price');
  final count = int.tryParse('$seats');
  if (unit == null ||
      !unit.isFinite ||
      unit <= 0 ||
      !['shared', 'private'].contains(service)) {
    return null;
  }
  if (service == 'private') return unit;
  if (count == null || count < 1 || count > 80) return null;
  return unit * count;
}
