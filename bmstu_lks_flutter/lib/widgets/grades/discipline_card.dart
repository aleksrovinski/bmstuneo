import 'package:flutter/material.dart';
import '../../models/discipline_progress.dart';
import 'event_detail_modal.dart';

class DisciplineCard extends StatelessWidget {
  final DisciplineProgress disc;
  final List<ControlEvent> events;
  final int currentWeek;
  final bool isDark;

  const DisciplineCard({
    super.key,
    required this.disc,
    required this.events,
    required this.currentWeek,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group events by week
    final weekEvents = <int, List<ControlEvent>>{};
    for (final e in events) {
      weekEvents.putIfAbsent(e.week, () => []).add(e);
    }

    final pointsSummary = disc.currentPointsSummary;
    final submittedEventsCount = events.where((e) => e.isSubmitted).length;
    final issuedHomeworksCount = events
        .where((e) => (e.type == 'ДЗ' || e.type == 'ЛР') && e.isIssued)
        .length;
    final scheduledControlCount = events
        .where((e) =>
            (e.type == 'РК' || e.type == 'КР' || e.type == 'М') && e.isIssued)
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Discipline Header with summary indicators
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        disc.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (issuedHomeworksCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_note_rounded,
                                      size: 13,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Выдано: $issuedHomeworksCount',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (scheduledControlCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.assignment_late_rounded,
                                      size: 13,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Назначен РК: $scheduledControlCount',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    size: 12, color: Color(0xFF10B981)),
                                const SizedBox(width: 3),
                                Text(
                                  'Сдано: $submittedEventsCount/${events.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (pointsSummary != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                          theme.colorScheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      pointsSummary,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // 2. Horizontal Semester Week Timeline (Weeks 1 to 17)
          Container(
            height: 84,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 17,
              itemBuilder: (context, idx) {
                final week = idx + 1;
                final isCurrent = week == currentWeek;
                final weekList = weekEvents[week] ?? [];

                return Container(
                  width: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Week Label
                      Text(
                        '$week н.',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w600,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Event chips in this week with icons
                      Expanded(
                        child: weekList.isEmpty
                            ? Center(
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.outlineVariant,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: weekList.map((e) {
                                    return _buildEventMiniChip(context, e);
                                  }).toList(),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 3. Informative Event Chips Row
          if (events.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: events.map((e) {
                  return _buildEventFullChip(context, e);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Mini chip in week column (with icon + title)
  Widget _buildEventMiniChip(BuildContext context, ControlEvent e) {
    return GestureDetector(
      onTap: () => EventDetailModal.show(context, e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: e.statusColor.withValues(alpha: isDark ? 0.25 : 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: e.statusColor, width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(e.statusIcon, size: 9, color: e.statusColor),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                e.title,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: e.statusColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Full chip showing: [ Icon | Title | Status Badge | Week ]
  Widget _buildEventFullChip(BuildContext context, ControlEvent e) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => EventDetailModal.show(context, e),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: e.statusColor.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: e.statusColor.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(e.statusIcon, size: 14, color: e.statusColor),
            const SizedBox(width: 5),
            Text(
              e.title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: e.statusColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                e.shortBadgeText,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: e.statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${e.week} н.',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
