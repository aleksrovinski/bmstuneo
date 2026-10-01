import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discipline_progress.dart';
import '../providers/auth_provider.dart';
import '../providers/progress_provider.dart';

class GradebookScreen extends StatefulWidget {
  const GradebookScreen({super.key});

  @override
  State<GradebookScreen> createState() => _GradebookScreenState();
}

class _GradebookScreenState extends State<GradebookScreen> {
  int _selectedSemesterIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final auth = context.watch<AuthProvider>();
    final prog = context.watch<ProgressProvider>();
    final user = auth.userProfile;

    final stages = user?.stages ?? [];
    final currentDisciplines = prog.disciplines;
    final gpa = prog.gpa;
    final status = prog.scholarshipStatus;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Электронная зачётка',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              user?.cardNumber != null
                  ? 'Зачётная книжка № ${user!.cardNumber}'
                  : (user?.groupTitle ?? 'МГТУ им. Н.Э. Баумана'),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. GPA & Scholarship Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.surfaceContainerHigh,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // GPA Badge
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gpa > 0 ? gpa.toStringAsFixed(2) : '—',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                              Text(
                                'GPA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      // Grades Breakdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Успеваемость семестра',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _buildGradePill(context, 'Отл (5)', prog.countGrade5, const Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                _buildGradePill(context, 'Хор (4)', prog.countGrade4, const Color(0xFF3B82F6)),
                                const SizedBox(width: 6),
                                _buildGradePill(context, 'Удовл (3)', prog.countGrade3, const Color(0xFFF59E0B)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
                  const SizedBox(height: 12),
                  // Scholarship status row
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: status.color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: status.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Semesters switcher (if student has recorded stages)
            if (stages.isNotEmpty) ...[
              Text(
                'Ступени и семестры обучения',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stages.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final stage = stages[idx];
                    final isSelected = _selectedSemesterIndex == idx;
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text('${stage.semester} семестр (${stage.groupTitle})'),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedSemesterIndex = idx);
                          if (stage.uuid != prog.stageUuid) {
                            prog.loadProgress(stage.uuid);
                          }
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 3. Disciplines List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Дисциплины и отчётность (${currentDisciplines.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Итог / Балл',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (prog.isLoading && currentDisciplines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (currentDisciplines.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    'Данные зачётки за этот период отсутствуют в ЛКС',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ...currentDisciplines.map((disc) => _buildDisciplineRow(context, disc, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildGradePill(BuildContext context, String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$title: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDisciplineRow(BuildContext context, DisciplineProgress disc, bool isDark) {
    final theme = Theme.of(context);
    final grade = disc.estimatedGrade;

    Color badgeColor;
    if (grade == 5) {
      badgeColor = const Color(0xFF10B981);
    } else if (grade == 4) {
      badgeColor = const Color(0xFF3B82F6);
    } else if (grade == 3) {
      badgeColor = const Color(0xFFF59E0B);
    } else if (grade == 2) {
      badgeColor = const Color(0xFFEF4444);
    } else {
      badgeColor = theme.colorScheme.primary;
    }

    final modules = disc.controls.where((c) => c.type == 'М' && c.value != null).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (modules.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: modules.map((m) {
                      return Text(
                        '${m.title}: ${m.value}б.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Grade Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Text(
                  disc.gradeDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
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
