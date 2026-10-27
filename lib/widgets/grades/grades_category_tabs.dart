import 'package:flutter/material.dart';
import '../../providers/progress_provider.dart';

class GradesCategoryTabs extends StatelessWidget {
  final ProgressCategory activeCategory;
  final int totalControlsCount;
  final int totalLabsCount;
  final int totalSeminarsCount;
  final ValueChanged<ProgressCategory> onCategoryChanged;

  const GradesCategoryTabs({
    super.key,
    required this.activeCategory,
    required this.totalControlsCount,
    required this.totalLabsCount,
    required this.totalSeminarsCount,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      color: colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTab(
              context,
              title: 'Текущий прогресс',
              subtitle: 'ДЗ, РК, КР, М ($totalControlsCount)',
              category: ProgressCategory.controls,
            ),
            const SizedBox(width: 8),
            _buildTab(
              context,
              title: 'Лабораторные',
              subtitle: 'ЛР ($totalLabsCount)',
              category: ProgressCategory.laboratory,
            ),
            const SizedBox(width: 8),
            _buildTab(
              context,
              title: 'Семинары',
              subtitle: 'СЗ ($totalSeminarsCount)',
              category: ProgressCategory.seminars,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    BuildContext context, {
    required String title,
    required String subtitle,
    required ProgressCategory category,
  }) {
    final theme = Theme.of(context);
    final isSelected = category == activeCategory;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => onCategoryChanged(category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : (isDark
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.surfaceContainer),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark
                    ? theme.colorScheme.outlineVariant
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
