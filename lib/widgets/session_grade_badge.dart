import 'package:flutter/material.dart';
import '../models/session_result.dart';

/// Colored grade pill used by the session results table and the profile card.
class SessionGradeBadge extends StatelessWidget {
  final SessionDiscipline discipline;

  const SessionGradeBadge({super.key, required this.discipline});

  @override
  Widget build(BuildContext context) {
    final d = discipline;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bg;
    Color textColor;
    FontWeight weight = FontWeight.w600;

    if (d.isExcellent) {
      bg = isDark ? const Color(0xFF0F381E) : const Color(0xFFDCFCE7);
      textColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
      weight = FontWeight.w900;
    } else if (d.isGood) {
      bg = isDark ? const Color(0xFF382A0A) : const Color(0xFFFEF9C3);
      textColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFCA8A04);
      weight = FontWeight.w700;
    } else if (d.isCreditPassed) {
      bg = isDark ? const Color(0xFF0F381E) : const Color(0xFFDCFCE7);
      textColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
      weight = FontWeight.w600;
    } else if (d.isSatisfactory) {
      bg = isDark ? const Color(0xFF0C2A3D) : const Color(0xFFE0F2FE);
      textColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
      weight = FontWeight.w600;
    } else if (d.isDebt) {
      bg = isDark ? const Color(0xFF3B1212) : const Color(0xFFFEE2E2);
      textColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      weight = FontWeight.w800;
    } else {
      bg = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
      textColor = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withValues(alpha: 0.25)),
      ),
      child: Text(
        d.grade.isEmpty ? '—' : d.grade,
        style: TextStyle(fontSize: 12, fontWeight: weight, color: textColor),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

String disciplinesWord(int count) {
  if (count % 10 == 1 && count % 100 != 11) return 'дисциплина';
  if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
    return 'дисциплины';
  }
  return 'дисциплин';
}
