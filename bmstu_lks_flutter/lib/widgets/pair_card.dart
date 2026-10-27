import 'package:flutter/material.dart';

import '../models/schedule_lesson.dart';
import 'teacher_details_sheet.dart';

class PairCard extends StatelessWidget {
  final ScheduleLesson lesson;
  final bool isCurrent;
  final VoidCallback? onDelete;

  const PairCard({super.key, required this.lesson, this.isCurrent = false, this.onDelete});

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
    final scheme = theme.colorScheme;
    final typeColor = _getTypeColor(lesson.actType);
    final hasTeachers = lesson.teachers.isNotEmpty;
    final meta = [lesson.audiencesFormatted, if (!lesson.isEveryWeek) lesson.weekTitle].join(' · ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.55) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: isCurrent ? Border.all(color: scheme.primary, width: 1.5) : null,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Time column: pair number, start and end
            SizedBox(
              width: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.time > 0 ? '${lesson.time} пара' : 'Своя',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lesson.startTime,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  ),
                  Text(lesson.endTime, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            // Lesson type as a colored rail
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.disciplineTitle,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: lesson.actTypeTitle,
                          style: TextStyle(color: typeColor, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' · $meta'),
                      ],
                    ),
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasTeachers) ...[
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => TeacherDetailsSheet.show(
                        context,
                        teachers: lesson.teachers,
                        disciplineTitle: lesson.disciplineTitle,
                        actTypeTitle: lesson.actTypeTitle,
                        audiences: lesson.audiencesFormatted,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          lesson.teachersFormatted,
                          style: TextStyle(fontSize: 12.5, color: scheme.primary, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  if (lesson.isStream && lesson.streamName != null)
                    Text(
                      'Поток: ${lesson.streamName}',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (lesson.isCustom && onDelete != null)
              IconButton(
                onPressed: onDelete,
                tooltip: 'Удалить своё занятие',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
