/// Moscow time for everything tied to the BMSTU timetable.
///
/// Pairs start at 08:30 Moscow time wherever the student's phone is, so "today",
/// the current pair, numerator/denominator and homework deadlines are worked out on
/// the Moscow clock (UTC+3, no daylight saving since 2014), not the phone's.
///
/// [now] returns the Moscow wall-clock time as a plain local `DateTime`: its fields are
/// what a clock in Moscow shows, so it compares directly with lesson times built as
/// `DateTime(y, m, d, 8, 30)`. Use it only for such wall-clock logic; moments in time
/// (sync timestamps, ids, alarms) keep using `DateTime.now()`.
class MoscowTime {
  static const offset = Duration(hours: 3);

  /// The real clock; replaced in tests.
  static DateTime Function() clock = DateTime.now;

  static DateTime now() => of(clock());

  /// The Moscow wall-clock time at the moment [instant].
  static DateTime of(DateTime instant) {
    final m = instant.toUtc().add(offset);
    return DateTime(m.year, m.month, m.day, m.hour, m.minute, m.second, m.millisecond, m.microsecond);
  }

  /// The moment at which Moscow clocks show [wallClock] (from [now] or a lesson time).
  static DateTime instantOf(DateTime wallClock) => DateTime.utc(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
    wallClock.second,
    wallClock.millisecond,
    wallClock.microsecond,
  ).subtract(offset);
}

/// Calendar-day arithmetic for wall-clock dates. `add(Duration(days: 1))` adds 24 hours,
/// which lands on the wrong date where the phone's zone moves its clocks (and a Moscow
/// wall-clock time lives in the phone's zone as a plain `DateTime`).
extension CalendarDays on DateTime {
  /// Midnight of this day.
  DateTime get dateOnly => DateTime(year, month, day);

  /// The same wall-clock time [days] calendar days later (earlier when negative).
  DateTime plusDays(int days) => DateTime(year, month, day + days, hour, minute, second, millisecond, microsecond);

  /// Monday of this week, at midnight.
  DateTime get mondayOfWeek => DateTime(year, month, day - (weekday - 1));

  /// Whole calendar days from this date to [other]'s date.
  int calendarDaysUntil(DateTime other) =>
      DateTime.utc(other.year, other.month, other.day).difference(DateTime.utc(year, month, day)).inDays;
}
