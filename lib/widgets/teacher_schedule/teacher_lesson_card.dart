import 'package:flutter/material.dart';
import '../../models/schedule_lesson.dart';

/// One pair in a teacher's day: time, type, discipline, rooms and groups.
class TeacherLessonCard extends StatelessWidget {
  final ScheduleLesson lesson;

  const TeacherLessonCard({super.key, required this.lesson});

  static Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
      case 'лекция':
        return const Color(0xFF3B82F6);
      case 'seminar':
      case 'семинар':
        return const Color(0xFF10B981);
      case 'lab':
      case 'лабораторная':
      case 'лабораторная работа':
        return const Color(0xFFF59E0B);
      case 'military':
      case 'военная кафедра':
      case 'вк':
        return const Color(0xFF15803D);
      case 'elective':
      case 'факультатив':
        return const Color(0xFF0EA5E9);
      case 'consultation':
      case 'консультация':
        return const Color(0xFFE11D48);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typeColor = _typeColor(lesson.actType);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Pair number, time, and type badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHigh
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lesson.time > 0 ? '${lesson.time} пара' : 'Занятие',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lesson.startTime} — ${lesson.endTime}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lesson.actTypeTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Discipline title
            Text(
              lesson.disciplineTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),

            // Audience & Group row
            Row(
              children: [
                // Classroom
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          lesson.audiencesFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Group / Stream being taught
                if (lesson.streamName != null && lesson.streamName!.isNotEmpty)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            lesson.streamName!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (!lesson.isEveryWeek) ...[
              const SizedBox(height: 8),
              Text(
                'Периодичность: ${lesson.weekTitle}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
