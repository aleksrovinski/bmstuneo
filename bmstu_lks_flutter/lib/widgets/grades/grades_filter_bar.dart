import 'package:flutter/material.dart';
import '../../providers/progress_provider.dart';

class GradesFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ProgressStatusFilter statusFilter;
  final ValueChanged<ProgressStatusFilter> onStatusFilterChanged;
  final int totalCount;
  final int issuedCount;
  final int submittedCount;
  final int notIssuedCount;

  const GradesFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.totalCount,
    required this.issuedCount,
    required this.submittedCount,
    required this.notIssuedCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      color: colorScheme.surface,
      child: Column(
        children: [
          // Search field
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Поиск по названию предмета или номеру ДЗ/РК...',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 12,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 18,
              ),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 16, color: colorScheme.onSurfaceVariant),
                      onPressed: onClearSearch,
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Status Filter Chips (Все, Выдано, Сдано, Не выдано)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusFilterChip(
                  context,
                  label: 'Все ($totalCount)',
                  icon: Icons.all_inclusive_rounded,
                  filter: ProgressStatusFilter.all,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                _buildStatusFilterChip(
                  context,
                  label: 'К сдаче / Назначено ($issuedCount)',
                  icon: Icons.assignment_late_rounded,
                  filter: ProgressStatusFilter.issued,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _buildStatusFilterChip(
                  context,
                  label: 'Сдано ($submittedCount)',
                  icon: Icons.check_circle_rounded,
                  filter: ProgressStatusFilter.submitted,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                _buildStatusFilterChip(
                  context,
                  label: 'В плане ($notIssuedCount)',
                  icon: Icons.schedule_rounded,
                  filter: ProgressStatusFilter.notIssued,
                  color: colorScheme.outline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required ProgressStatusFilter filter,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isSelected = filter == statusFilter;

    return GestureDetector(
      onTap: () => onStatusFilterChanged(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? color
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
