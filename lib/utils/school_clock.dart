/// Single source of "what day is it" for attendance and other date-keyed data.
///
/// Attendance documents are keyed by calendar date (`<class>_<section>_Y-M-D`).
/// Using the raw device `DateTime.now()` meant the day boundary followed the
/// phone's timezone: a device set to a different timezone (or one a traveller
/// carries across the date line) would read/write attendance under the wrong
/// day, and a guardian on such a device would see "today" mismatch the school's
/// (#43). Anchoring to a fixed school timezone (India Standard Time, UTC+5:30)
/// makes the date deterministic regardless of device timezone.
///
/// NOTE: this corrects for the device *timezone*, not a wrong device *clock* —
/// a fully resolved fix would stamp attendance from a server timestamp. IST is
/// the right anchor for this app's schools.
abstract class SchoolClock {
  /// India Standard Time offset from UTC.
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  /// Current wall-clock instant in the school timezone (IST). The returned
  /// `DateTime` carries IST year/month/day/hour values; use its date parts for
  /// keys, not its `isUtc`/timezone metadata.
  static DateTime now() => DateTime.now().toUtc().add(_istOffset);

  /// Today's date (time component zeroed) in the school timezone.
  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }
}
