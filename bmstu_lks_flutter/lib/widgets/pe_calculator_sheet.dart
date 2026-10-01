import 'dart:math';
import 'package:flutter/material.dart';
import '../models/physical_culture.dart';

class PeCalculatorSheet extends StatefulWidget {
  final PhysicalCultureData data;
  final int currentWeekNum;

  const PeCalculatorSheet({
    super.key,
    required this.data,
    required this.currentWeekNum,
  });

  static Future<void> show(
    BuildContext context, {
    required PhysicalCultureData data,
    required int currentWeekNum,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PeCalculatorSheet(
        data: data,
        currentWeekNum: currentWeekNum,
      ),
    );
  }

  @override
  State<PeCalculatorSheet> createState() => _PeCalculatorSheetState();
}

class _PeCalculatorSheetState extends State<PeCalculatorSheet> {
  int _selectedPace = 2; // Default 2 visits per week

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final data = widget.data;
    final currentWeek = widget.currentWeekNum.clamp(1, 17);
    final remainingWeeks = max(1, 17 - currentWeek);

    final pointsNeeded = max(0, PhysicalCultureData.targetPoints - data.studyPoints);
    final attendsNeeded = max(0, PhysicalCultureData.targetAttends - data.studyAttends);

    final isAlreadyCredit = data.isCreditReady;

    final requiredPace = (attendsNeeded / remainingWeeks).ceil();

    final projectedFinishWeek = currentWeek + (_selectedPace > 0 ? (attendsNeeded / _selectedPace).ceil() : 0);

    Color riskColor;
    String riskTitle;
    String riskDesc;

    if (isAlreadyCredit) {
      riskColor = const Color(0xFF10B981);
      riskTitle = 'Зачёт по физкультуре уже готов! 🎉';
      riskDesc = 'Вы набрали необходимые ${data.studyPoints} б. и ${data.studyAttends} посещений.';
    } else if (requiredPace <= 1) {
      riskColor = const Color(0xFF10B981);
      riskTitle = 'Отличный темп — риска нет';
      riskDesc = 'Достаточно посещать всего 1 раз в неделю до 17-й недели.';
    } else if (requiredPace == 2) {
      riskColor = const Color(0xFFF59E0B);
      riskTitle = 'Умеренный темп — старайтесь не пропускать';
      riskDesc = 'Необходимо ходить стабильно 2 раза в неделю до конца семестра.';
    } else {
      riskColor = const Color(0xFFEF4444);
      riskTitle = 'Высокий риск — требуется ускорение';
      riskDesc = 'Нужно ходить $requiredPace+ раза в неделю или брать отработки кафедры ФВ.';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.calculate_rounded, color: theme.colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Калькулятор закрытия семестра',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Норматив кафедры ФКиС МГТУ: 60 б. и 25 пос.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 1. Current Status Metrics
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  title: 'Осталось набрать',
                  value: '$pointsNeeded б.',
                  subtitle: '${data.studyPoints} из 60 б.',
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context,
                  title: 'Осталось посетить',
                  value: '$attendsNeeded пос.',
                  subtitle: '${data.studyAttends} из 25 пос.',
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context,
                  title: 'Недель до конца',
                  value: '$remainingWeeks нед.',
                  subtitle: 'Идёт $currentWeek нед.',
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Risk Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: riskColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  isAlreadyCredit ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: riskColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        riskTitle,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: riskColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        riskDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Simulator: Interactive Pace Slider
          if (!isAlreadyCredit) ...[
            Text(
              'Симулятор темпа: сколько раз в неделю ходить?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 раз/нед')),
                ButtonSegment(value: 2, label: Text('2 раза/нед')),
                ButtonSegment(value: 3, label: Text('3 раза/нед')),
                ButtonSegment(value: 4, label: Text('4 раза/нед')),
              ],
              selected: {_selectedPace},
              onSelectionChanged: (set) {
                setState(() => _selectedPace = set.first);
              },
            ),
            const SizedBox(height: 14),

            // Simulation Result Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    projectedFinishWeek <= 17 ? Icons.event_available_rounded : Icons.warning_amber_rounded,
                    color: projectedFinishWeek <= 17 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      projectedFinishWeek <= 17
                          ? 'При темпе $_selectedPace раз(а) в неделю вы закроете норматив на $projectedFinishWeek-й неделе (за ${17 - projectedFinishWeek} нед. до сессии)!'
                          : 'При таком темпе норматив закроется только на $projectedFinishWeek-й неделе. Это позже конца семестра (17 нед.) — ходите чаще!',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
