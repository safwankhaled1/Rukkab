import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

// Scheduled journeys always use Palestinian civil time, independent of device zone.
final tz.Location _location = () {
  data.initializeTimeZones();
  return tz.getLocation('Asia/Hebron');
}();
DateTime palestineNow() => tz.TZDateTime.now(_location);
DateTime palestineTime(DateTime instant) =>
    tz.TZDateTime.from(instant, _location);
DateTime palestineWallTime(
  int year,
  int month,
  int day,
  int hour,
  int minute,
) => tz.TZDateTime(_location, year, month, day, hour, minute);
