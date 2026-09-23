import 'package:flutter/material.dart';

class GradesStatusLegend extends StatelessWidget {
  const GradesStatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildLegendPill(
              icon: Icons.edit_note_rounded,
              label: 'Выдано (ДЗ/ЛР)',
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            _buildLegendPill(
              icon: Icons.assignment_late_rounded,
              label: 'Назначен (РК/КР)',
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            _buildLegendPill(
              icon: Icons.check_circle_rounded,
              label: 'Сдано / Зачтено',
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 12),
            _buildLegendPill(
              icon: Icons.schedule_rounded,
              label: 'В плане',
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            _buildLegendPill(
              icon: Icons.cancel_rounded,
              label: 'Пропущено',
              color: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
