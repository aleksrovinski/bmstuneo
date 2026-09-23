import 'package:flutter/material.dart';
import '../../models/discipline_progress.dart';

class EventDetailModal {
  static void show(BuildContext context, ControlEvent e) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Type
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: e.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      e.statusIcon,
                      color: e.statusColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.disciplineTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Prominent Status Explanation Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: e.statusColor.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: e.statusColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(e.statusIcon, color: e.statusColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.statusHeadline,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: e.statusColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.statusSubtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 12),

              // Parameter Rows
              _buildModalRow(
                'Неделя семестра',
                'Неделя ${e.week}',
                context: context,
              ),
              _buildModalRow(
                'Статус задания',
                e.statusTitle,
                badgeColor: e.statusColor,
                badgeIcon: e.statusIcon,
                context: context,
              ),

              if (e.passStatusTitle != null)
                _buildModalRow(
                  'Сроки сдачи',
                  e.passStatusTitle!,
                  badgeColor: e.passStatus == 'late'
                      ? theme.colorScheme.error
                      : const Color(0xFF10B981),
                  context: context,
                ),

              if (e.type == 'М' && e.points != null) ...[
                _buildModalRow(
                  'Количество баллов',
                  '${e.value ?? "Не выставлено"} из ${e.points?['point_all'] ?? 60} б.',
                  context: context,
                ),
                if (e.points?['point_3'] != null)
                  _buildModalRow(
                    'Пороги оценок',
                    '«3» от ${e.points!['point_3']} б.  |  «4» от ${e.points!['point_4']} б.  |  «5» от ${e.points!['point_5']} б.',
                    context: context,
                  ),
              ] else if (e.value != null && e.value.toString().isNotEmpty) ...[
                _buildModalRow(
                  'Процент выполнения',
                  '${e.value}%',
                  context: context,
                ),
              ],

              if (e.formattedSetDate != null)
                _buildModalRow(
                  'Время выставления',
                  e.formattedSetDate!,
                  context: context,
                ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildModalRow(
    String label,
    String value, {
    Color? badgeColor,
    IconData? badgeIcon,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (badgeColor != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (badgeIcon != null) ...[
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
