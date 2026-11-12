import 'schedule_lesson.dart';
import '../constants/moscow_time.dart';

/// Quick homework is due at the next pair of the discipline; long homework has its
/// own deadline the student picks.
enum HomeworkKind { quick, long }

/// The student's own homework note, kept on the device only.
class HomeworkNote {
  final String id;
  final String disciplineTitle;
  final String text;
  final HomeworkKind kind;
  final DateTime due;
  final bool done;
  final DateTime createdAt;

  const HomeworkNote({
    required this.id,
    required this.disciplineTitle,
    required this.text,
    required this.kind,
    required this.due,
    this.done = false,
    required this.createdAt,
  });

  bool isOverdue(DateTime now) => !done && due.isBefore(now);

  /// Shown on this pair held on [date]: quick homework on the exact pair it is due at,
  /// long homework on the discipline's pairs on its deadline day.
  bool isFor(ScheduleLesson lesson, DateTime date) {
    if (disciplineTitle != lesson.disciplineTitle ||
        due.year != date.year ||
        due.month != date.month ||
        due.day != date.day) {
      return false;
    }
    if (kind == HomeworkKind.long) return true;
    final start = '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
    return lesson.startTime.trim().padLeft(5, '0') == start;
  }

  HomeworkNote copyWith({String? text, HomeworkKind? kind, DateTime? due, bool? done}) => HomeworkNote(
        id: id,
        disciplineTitle: disciplineTitle,
        text: text ?? this.text,
        kind: kind ?? this.kind,
        due: due ?? this.due,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'disciplineTitle': disciplineTitle,
        'text': text,
        'kind': kind.name,
        'due': due.toIso8601String(),
        'done': done,
        'createdAt': createdAt.toIso8601String(),
      };

  factory HomeworkNote.fromJson(Map<String, dynamic> json) => HomeworkNote(
        id: json['id'] as String,
        disciplineTitle: json['disciplineTitle'] as String? ?? '',
        text: json['text'] as String? ?? '',
        kind: json['kind'] == HomeworkKind.long.name ? HomeworkKind.long : HomeworkKind.quick,
        due: DateTime.parse(json['due'] as String),
        done: json['done'] == true,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// The next pair of [disciplineTitle] after [now], with the moment it starts.
///
/// Week parity alternates every Monday starting from [currentWeekIsNumerator], so a
/// numerator-only pair is found in the right week. Looks two weeks ahead; null when the
/// discipline has no pairs in the schedule.
({ScheduleLesson lesson, DateTime start})? nextPairOf(
  String disciplineTitle,
  List<ScheduleLesson> lessons, {
  required bool currentWeekIsNumerator,
  required DateTime now,
}) {
  final ofDiscipline = lessons.where((l) => l.disciplineTitle == disciplineTitle).toList();
  if (ofDiscipline.isEmpty) return null;

  final today = now.dateOnly;
  final monday = today.mondayOfWeek;
  for (var offset = 0; offset < 15; offset++) {
    final date = today.plusDays(offset);
    final weeksAhead = monday.calendarDaysUntil(date) ~/ 7;
    final isNumerator = weeksAhead.isEven ? currentWeekIsNumerator : !currentWeekIsNumerator;

    final candidates = <({ScheduleLesson lesson, DateTime start})>[];
    for (final l in ofDiscipline) {
      if (l.day != date.weekday || !l.matchesWeek(isNumeratorWeek: isNumerator)) continue;
      final parts = l.startTime.split(':');
      final start = DateTime(date.year, date.month, date.day, int.tryParse(parts.first) ?? 0,
          parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
      if (start.isAfter(now)) candidates.add((lesson: l, start: start));
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => a.start.compareTo(b.start));
      return candidates.first;
    }
  }
  return null;
}
