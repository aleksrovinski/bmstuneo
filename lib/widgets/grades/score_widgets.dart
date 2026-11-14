import 'package:flutter/material.dart';

import '../../models/discipline_progress.dart';

/// Colour of a 5-point grade; null (not judged yet) is the theme's neutral.
Color gradeColor(int? grade, ColorScheme scheme) {
  switch (grade) {
    case 5:
      return const Color(0xFF10B981); // Emerald
    case 4:
      return const Color(0xFF3B82F6); // Blue
    case 3:
      return const Color(0xFFF59E0B); // Amber
    case 2:
      return const Color(0xFFEF4444); // Red
    default:
      return scheme.onSurfaceVariant;
  }
}

String gradeLabel(int? grade) => switch (grade) {
  5 => 'идёт на «5»',
  4 => 'идёт на «4»',
  3 => 'идёт на «3»',
  2 => 'недобор',
  _ => 'ещё нет баллов',
};

/// Big "48 из 100" with the grade the discipline is on.
class DisciplineScore extends StatelessWidget {
  final DisciplineProgress disc;
  const DisciplineScore({super.key, required this.disc});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final graded = disc.gradedModulesCount > 0;
    final grade = disc.estimatedGrade;
    final color = graded ? gradeColor(grade, scheme) : scheme.onSurfaceVariant;
    final max = disc.maxPoints;

    return Semantics(
      label: graded
          ? 'Набрано ${disc.scoredModulePoints}${max != null ? ' из $max' : ''} баллов, ${gradeLabel(grade)}'
          : 'Баллов пока нет${max != null ? ', максимум $max' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: graded ? '${disc.scoredModulePoints}' : '—',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color, height: 1),
                ),
                if (max != null)
                  TextSpan(
                    text: ' / $max',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            gradeLabel(graded ? grade : null),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// The discipline's modules side by side, each as wide as the points it gives and
/// filled as far as it was scored; the tick is the pass threshold.
class ModuleScoreBar extends StatelessWidget {
  final List<ControlEvent> modules;
  final void Function(ControlEvent module)? onTap;

  const ModuleScoreBar({super.key, required this.modules, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, m) in modules.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            flex: (m.threshold('point_all') ?? 1).clamp(1, 1000),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap == null ? null : () => onTap!(m),
              child: _ModuleSegment(module: m, scheme: scheme),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModuleSegment extends StatelessWidget {
  final ControlEvent module;
  final ColorScheme scheme;
  const _ModuleSegment({required this.module, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final score = module.moduleScore;
    final max = module.threshold('point_all');
    final pass = module.threshold('point_3');
    final color = score == null ? scheme.onSurfaceVariant : gradeColor(module.moduleGrade ?? 5, scheme);
    final fill = (score != null && max != null && max > 0) ? (score / max).clamp(0.0, 1.0) : 0.0;
    final passAt = (pass != null && max != null && max > 0) ? (pass / max).clamp(0.0, 1.0) : null;

    final String points;
    if (score != null) {
      points = max != null ? '$score/$max' : '$score б.';
    } else {
      points = max != null ? 'до $max' : 'нет баллов';
    }

    return Semantics(
      label: '${module.title}: ${score != null ? 'набрано $points' : 'не оценён, $points'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fill,
                      child: Container(
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    // Pass threshold
                    if (passAt != null)
                      Positioned(
                        left: (box.maxWidth * passAt - 1).clamp(0.0, box.maxWidth - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: scheme.surface),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              module.title.replaceFirst('Модуль ', 'М'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
            Text(
              points,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: score == null ? scheme.onSurfaceVariant : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Points over the whole semester, shown above the disciplines.
class SemesterScoreCard extends StatelessWidget {
  final SemesterScore score;
  const SemesterScoreCard({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = score.semesterMax;
    final percent = score.percentOfGraded;
    // Against the whole semester when LKS gives its maximum, else against what was graded
    final scale = max ?? score.gradedMax;
    final scoredPart = scale > 0 ? (score.scored / scale).clamp(0.0, 1.0) : 0.0;
    final gradedPart = scale > 0 ? (score.gradedMax / scale).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Баллы за семестр',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${score.scored}',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          if (max != null)
                            TextSpan(
                              text: '  из $max',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (percent != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$percent%',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
                    ),
                    Text(
                      'от возможных ${score.gradedMax}',
                      style: TextStyle(fontSize: 10.5, color: scheme.onPrimaryContainer.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Scored (solid) inside what the graded modules could give (pale)
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: scheme.onPrimaryContainer.withValues(alpha: 0.12)),
                  FractionallySizedBox(
                    widthFactor: gradedPart,
                    child: Container(color: scheme.onPrimaryContainer.withValues(alpha: 0.28)),
                  ),
                  FractionallySizedBox(
                    widthFactor: scoredPart,
                    child: Container(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                score.gradedModules == 0
                    ? 'Модули ещё не оценены'
                    : 'Оценено модулей: ${score.gradedModules} из ${score.totalModules}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
              ),
              for (final grade in const [5, 4, 3, 2])
                if ((score.disciplinesByGrade[grade] ?? 0) > 0)
                  _GradeCount(grade: grade, count: score.disciplinesByGrade[grade]!, scheme: scheme),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeCount extends StatelessWidget {
  final int grade;
  final int count;
  final ColorScheme scheme;
  const _GradeCount({required this.grade, required this.count, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(grade, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            grade == 2 ? 'недобор: $count' : 'на «$grade»: $count',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
