import 'physical_culture.dart';
import 'schedule_lesson.dart';

class NearestPeLesson {
  final String dayTitle; // e.g. "Сегодня", "Завтра", "Во вторник"
  final String time; // e.g. "11:35"
  final String title; // e.g. "ОФП" or "Элективные курсы по ФКиС"
  final String place; // e.g. "Манеж СК МГТУ"
  final String teacher;
  final bool isToday;
  final bool isNow;
  final int daysUntil;
  final int minutesUntil;

  NearestPeLesson({
    required this.dayTitle,
    required this.time,
    required this.title,
    required this.place,
    required this.teacher,
    required this.isToday,
    required this.isNow,
    required this.daysUntil,
    required this.minutesUntil,
  });

  static int? _parseTimeToMinutes(String timeStr) {
    final parts = timeStr.trim().split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return h * 60 + m;
      }
    }
    return null;
  }

  static int _dayNameToWeekday(String dayName) {
    final lower = dayName.toLowerCase().trim();
    if (lower.contains('пон')) return 1;
    if (lower.contains('вто')) return 2;
    if (lower.contains('сре')) return 3;
    if (lower.contains('чет')) return 4;
    if (lower.contains('пят')) return 5;
    if (lower.contains('суб')) return 6;
    return 1;
  }

  static String _weekdayToTitle(int weekday, int daysUntil) {
    if (daysUntil == 0) return 'Сегодня';
    if (daysUntil == 1) return 'Завтра';
    switch (weekday) {
      case 1:
        return 'В понедельник';
      case 2:
        return 'Во вторник';
      case 3:
        return 'В среду';
      case 4:
        return 'В четверг';
      case 5:
        return 'В пятницу';
      case 6:
        return 'В субботу';
      default:
        return 'На этой неделе';
    }
  }

  static bool isPeDiscipline(String disciplineTitle) {
    final lower = disciplineTitle.toLowerCase();
    return lower.contains('физическ') ||
        lower.contains('фкис') ||
        lower.contains('плаван') ||
        lower.contains('спорт') ||
        lower.contains('бассейн');
  }

  /// Calculates the nearest upcoming physical culture lesson
  static NearestPeLesson? findNearest({
    required List<FvRecord> records,
    required List<ScheduleLesson> lessons,
    required bool isCurrentWeekNumerator,
    DateTime? mockNow,
  }) {
    final now = mockNow ?? DateTime.now();
    final currentDay = now.weekday; // 1 = Mon ... 7 = Sun
    final currentMinutes = now.hour * 60 + now.minute;

    final candidates = <NearestPeLesson>[];

    // 1. Check LKS FKiS teacher records
    for (final rec in records) {
      final recDay = _dayNameToWeekday(rec.weekDay);
      final startMin = _parseTimeToMinutes(rec.time) ?? (9 * 60);
      final endMin = startMin + 95;

      int daysUntil;
      int minutesUntil;
      bool isNow = false;
      bool isToday = false;

      if (recDay == currentDay) {
        isToday = true;
        if (currentMinutes >= startMin && currentMinutes <= endMin) {
          isNow = true;
          daysUntil = 0;
          minutesUntil = 0;
        } else if (currentMinutes < startMin) {
          daysUntil = 0;
          minutesUntil = startMin - currentMinutes;
        } else {
          // Finished today, next occurrence is in 7 days
          daysUntil = 7;
          minutesUntil = 7 * 1440 + (startMin - currentMinutes);
        }
      } else if (recDay > currentDay) {
        daysUntil = recDay - currentDay;
        minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
      } else {
        daysUntil = 7 - currentDay + recDay;
        minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
      }

      candidates.add(
        NearestPeLesson(
          dayTitle: isNow ? 'Идёт прямо сейчас' : _weekdayToTitle(recDay, daysUntil),
          time: rec.time.isNotEmpty ? rec.time : 'По расписанию',
          title: rec.section.isNotEmpty ? rec.section : 'ФКиС',
          place: rec.place.isNotEmpty ? rec.place : 'СК МГТУ',
          teacher: rec.teacherName,
          isToday: isToday,
          isNow: isNow,
          daysUntil: daysUntil,
          minutesUntil: minutesUntil,
        ),
      );
    }

    // 2. Check academic group schedule lessons
    for (final l in lessons) {
      if (!isPeDiscipline(l.disciplineTitle)) continue;

      final lessonDay = l.day;
      final startMin = _parseTimeToMinutes(l.startTime) ?? (9 * 60);
      final endMin = _parseTimeToMinutes(l.endTime) ?? (startMin + 95);

      int daysUntil;
      int minutesUntil;
      bool isNow = false;
      bool isToday = false;

      // Parity check for this week vs next week
      final matchesThisWeek = l.matchesWeek(isNumeratorWeek: isCurrentWeekNumerator);
      final matchesNextWeek = l.matchesWeek(isNumeratorWeek: !isCurrentWeekNumerator);

      if (lessonDay == currentDay) {
        if (matchesThisWeek) {
          isToday = true;
          if (currentMinutes >= startMin && currentMinutes <= endMin) {
            isNow = true;
            daysUntil = 0;
            minutesUntil = 0;
          } else if (currentMinutes < startMin) {
            daysUntil = 0;
            minutesUntil = startMin - currentMinutes;
          } else {
            daysUntil = matchesNextWeek ? 7 : 14;
            minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
          }
        } else {
          // Only matches next week or alternate
          daysUntil = matchesNextWeek ? 7 : 14;
          minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
        }
      } else if (lessonDay > currentDay) {
        final days = lessonDay - currentDay;
        if (matchesThisWeek) {
          daysUntil = days;
        } else if (matchesNextWeek) {
          daysUntil = days + 7;
        } else {
          daysUntil = days + 14;
        }
        minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
      } else {
        final days = 7 - currentDay + lessonDay;
        if (matchesNextWeek) {
          daysUntil = days;
        } else if (matchesThisWeek) {
          daysUntil = days + 7;
        } else {
          daysUntil = days + 14;
        }
        minutesUntil = daysUntil * 1440 + (startMin - currentMinutes);
      }

      candidates.add(
        NearestPeLesson(
          dayTitle: isNow ? 'Идёт прямо сейчас' : _weekdayToTitle(lessonDay, daysUntil),
          time: l.startTime,
          title: l.disciplineTitle,
          place: l.displayAudiences.isNotEmpty && l.displayAudiences != '—'
              ? l.displayAudiences
              : 'Спорткомплекс МГТУ',
          teacher: l.displayTeachers != 'Кафедра' ? l.displayTeachers : 'Преподаватель ФКиС',
          isToday: isToday,
          isNow: isNow,
          daysUntil: daysUntil,
          minutesUntil: minutesUntil,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    // Sort by: isNow first (0), then by minutesUntil
    candidates.sort((a, b) {
      if (a.isNow && !b.isNow) return -1;
      if (!a.isNow && b.isNow) return 1;
      return a.minutesUntil.compareTo(b.minutesUntil);
    });

    return candidates.first;
  }
}
