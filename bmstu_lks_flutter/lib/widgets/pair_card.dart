import 'package:flutter/material.dart';
import '../models/schedule_lesson.dart';

class PairCard extends StatelessWidget {
  final ScheduleLesson lesson;
  final bool isCurrent;
  final VoidCallback? onDelete;

  const PairCard({
    super.key,
    required this.lesson,
    this.isCurrent = false,
    this.onDelete,
  });

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'lecture':
      case 'лекция':
        return const Color(0xFF3B82F6); // Blue
      case 'seminar':
      case 'семинар':
        return const Color(0xFF10B981); // Emerald Green
      case 'lab':
      case 'лабораторная':
      case 'лабораторная работа':
        return const Color(0xFFF59E0B); // Amber
      case 'military':
      case 'военная кафедра':
      case 'вк':
        return const Color(0xFF15803D); // Forest Green
      case 'elective':
      case 'факультатив':
        return const Color(0xFF0EA5E9); // Sky Blue
      case 'consultation':
      case 'консультация':
        return const Color(0xFFE11D48); // Rose
      default:
        return const Color(0xFF8B5CF6); // Purple
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typeColor = _getTypeColor(lesson.actType);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isCurrent ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrent
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Pair number, time, and type badge
            Row(
              children: [
                // Pair badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : (isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : theme.colorScheme.surface),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lesson.time > 0 ? '${lesson.time} пара' : 'Занятие',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isCurrent
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Time
                Text(
                  '${lesson.startTime} — ${lesson.endTime}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (lesson.isCustom) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.tertiary
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Своя',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                ],
                // Act Type Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                if (lesson.isCustom && onDelete != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Discipline Title
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

            // Audiences and Teachers row
            Row(
              children: [
                // Audience with Building
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
                // Teacher
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          lesson.teachersFormatted,
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
              ],
            ),

            // Stream information or week badge
            if (lesson.isStream && lesson.streamName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Поток: ${lesson.streamName}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else if (!lesson.isEveryWeek) ...[
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
