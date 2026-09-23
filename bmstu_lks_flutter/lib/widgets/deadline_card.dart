import 'package:flutter/material.dart';
import '../models/discipline_progress.dart';
import '../providers/progress_provider.dart';

class DeadlineCard extends StatelessWidget {
  final ControlEvent event;
  final DeadlineStatus status;

  const DeadlineCard({
    super.key,
    required this.event,
    required this.status,
  });

  Color _getStatusColor(BuildContext context) {
    final theme = Theme.of(context);
    if (event.isSubmitted) return const Color(0xFF10B981); // Green: Сдано
    if (event.isIssued) {
      if (event.type == 'РК' || event.type == 'КР') return theme.colorScheme.primary; // Indigo/Primary: Назначен
      return theme.colorScheme.primary;   // Blue/Primary: Выдано
    }
    if (event.isMissed) return theme.colorScheme.error;   // Red: Просрочено
    if (status == DeadlineStatus.thisWeek) return const Color(0xFFF59E0B); // Amber: На этой неделе
    if (status == DeadlineStatus.overdue) return theme.colorScheme.error;
    return theme.colorScheme.outline; // Neutral: В плане
  }

  String _getStatusText() {
    final isRk = event.type == 'РК' || event.type == 'КР';
    if (event.isSubmitted) {
      if (event.value != null && event.value.toString().isNotEmpty) {
        return 'Сдано: ${event.value} б.';
      }
      return 'Сдано';
    }
    if (event.isIssued) {
      if (status == DeadlineStatus.thisWeek) {
        return isRk ? 'РК на этой неделе!' : 'Выдано (дедлайн!)';
      }
      return isRk ? 'Назначен' : 'Выдано';
    }
    if (event.isMissed || status == DeadlineStatus.overdue) {
      return isRk ? 'Не сдан' : 'Просрочено';
    }
    if (status == DeadlineStatus.thisWeek) {
      return 'На этой неделе!';
    }
    return isRk ? 'В плане' : 'Не выдано';
  }

  IconData _getStatusIcon() {
    if (event.isSubmitted) return Icons.check_circle_rounded;
    if (event.isIssued) {
      if (event.type == 'РК' || event.type == 'КР') return Icons.assignment_late_rounded;
      return Icons.edit_note_rounded;
    }
    if (event.isMissed || status == DeadlineStatus.overdue) return Icons.cancel_rounded;
    if (status == DeadlineStatus.thisWeek) return Icons.warning_amber_rounded;
    return Icons.schedule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == DeadlineStatus.thisWeek
              ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: status == DeadlineStatus.thisWeek ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Event Type & Week Badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  event.type,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
                Text(
                  '${event.week} нед',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Titles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.disciplineTitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStatusIcon(),
                  size: 13,
                  color: statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
