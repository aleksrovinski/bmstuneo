import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session_result.dart';
import '../providers/auth_provider.dart';
import '../providers/progress_provider.dart';

enum GradeFilter {
  all('Все'),
  passed('Сдано'),
  debts('Задолженности');

  final String title;
  const GradeFilter(this.title);
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<SemesterSession> _sessions = [];
  int? _selectedSemesterNumber; // null means 'Показать все'
  GradeFilter _gradeFilter = GradeFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    try {
      final results = await auth.apiService.getSessionResults(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _sessions = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }

    // Fallback: If no sessions loaded from network/cache, try generating from ProgressProvider
    if (_sessions.isEmpty && mounted) {
      try {
        final prog = context.read<ProgressProvider>();
        final disciplines = prog.disciplines;
        if (disciplines.isNotEmpty) {
          final user = auth.userProfile;
          final semNum = user?.semester ?? 1;
          final fallbackDisciplines = disciplines.map((d) {
            final grade = d.estimatedGrade != null
                ? (d.estimatedGrade! >= 5
                    ? 'Отлично'
                    : d.estimatedGrade! == 4
                        ? 'Хорошо'
                        : d.estimatedGrade! == 3
                            ? 'Удовлетворительно'
                            : 'Не аттестован')
                : (d.isPassed ? 'Зачтено' : '—');
            return SessionDiscipline(
              title: d.title,
              department: '',
              controlType: 'Зач',
              hours: 72,
              grade: grade,
            );
          }).toList();

          setState(() {
            _sessions = [
              SemesterSession(
                semesterTitle: 'Семестр $semNum',
                semesterNumber: semNum,
                disciplines: fallbackDisciplines,
                lastUpdated: 'Текущий семестр (из прогресса)',
              ),
            ];
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final auth = context.watch<AuthProvider>();
    final user = auth.userProfile;

    // Determine latest update string
    final latestUpdate = _sessions.isNotEmpty
        ? _sessions.first.lastUpdated
        : null;

    // Compute debts and passed across all displayed sessions
    final allFilteredDisciplines = _getFilteredDisciplines();
    final totalCount = allFilteredDisciplines.length;
    final debtCount = allFilteredDisciplines.where((d) => d.isDebt).length;
    final isAdmissionGranted = debtCount == 0 && totalCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Результаты сессий',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              latestUpdate ?? user?.groupTitle ?? 'МГТУ им. Н.Э. Баумана',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить сессию',
            onPressed: _isLoading ? null : () => _loadData(forceRefresh: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        child: _isLoading && _sessions.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _sessions.isEmpty
                ? _buildEmptyState(context)
                : _buildSessionContent(context, isDark, isAdmissionGranted, debtCount),
      ),
    );
  }

  List<SessionDiscipline> _getFilteredDisciplines() {
    final sessionsToScan = _selectedSemesterNumber == null
        ? _sessions
        : _sessions.where((s) => s.semesterNumber == _selectedSemesterNumber);

    final list = <SessionDiscipline>[];
    for (final s in sessionsToScan) {
      for (final d in s.disciplines) {
        if (_gradeFilter == GradeFilter.passed && !d.isPassed) continue;
        if (_gradeFilter == GradeFilter.debts && !d.isDebt) continue;
        list.add(d);
      }
    }
    return list;
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Данные сессии не загружены',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Потяните вниз для обновления данных сессии из ЛКС BMSTU или проверьте подключение к сети.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _loadData(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить запрос'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionContent(
    BuildContext context,
    bool isDark,
    bool isAdmissionGranted,
    int debtCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final displayedSessions = _selectedSemesterNumber == null
        ? _sessions
        : _sessions.where((s) => s.semesterNumber == _selectedSemesterNumber).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 1. Semester & Filter Bar (Matching LKS dropdown)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Семестр:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  // LKS BMSTU Style Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedSemesterNumber,
                        isDense: true,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Показать все',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          ..._sessions.map((s) => DropdownMenuItem<int?>(
                                value: s.semesterNumber,
                                child: Text(
                                  s.semesterTitle,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedSemesterNumber = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Grade Filters
              Row(
                children: GradeFilter.values.map((f) {
                  final isSelected = _gradeFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.title),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _gradeFilter = f;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Admission Status Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isAdmissionGranted
                ? (isDark ? const Color(0xFF0F291E) : const Color(0xFFE8F5E9))
                : (isDark ? const Color(0xFF331616) : const Color(0xFFFFEBEE)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAdmissionGranted
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                  : const Color(0xFFE53935).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isAdmissionGranted ? Icons.verified_rounded : Icons.warning_amber_rounded,
                color: isAdmissionGranted ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAdmissionGranted
                          ? 'Допуск к сессии получен'
                          : 'Имеются задолженности: $debtCount',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isAdmissionGranted
                            ? (isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20))
                            : (isDark ? const Color(0xFFE57373) : const Color(0xFFB71C1C)),
                      ),
                    ),
                    Text(
                      isAdmissionGranted
                          ? 'Все дисциплины сданы в срок, долгов нет'
                          : 'Обратитесь в деканат или к преподавателям для ликвидации задолженности',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Tables for each Semester
        ...displayedSessions.map((session) => _buildSemesterTableCard(context, session, isDark)),
      ],
    );
  }

  Widget _buildSemesterTableCard(BuildContext context, SemesterSession session, bool isDark) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter disciplines by grade filter
    final disciplines = session.disciplines.where((d) {
      if (_gradeFilter == GradeFilter.passed) return d.isPassed;
      if (_gradeFilter == GradeFilter.debts) return d.isDebt;
      return true;
    }).toList();

    if (disciplines.isEmpty && _gradeFilter != GradeFilter.all) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Semester Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(
              children: [
                Text(
                  session.semesterTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${disciplines.length} ${disciplinesWord(disciplines.length)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Дисциплина (Кафедра, тип сдачи)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    'Часы',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 105,
                  child: Text(
                    'Оценка',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: disciplines.length,
            separatorBuilder: (_, index) => Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, idx) {
              final d = disciplines[idx];
              final isOdd = idx.isOdd;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: isOdd
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.015))
                    : Colors.transparent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Col 1: Discipline Title & Department
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (d.department.isNotEmpty || d.controlType.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '(${d.department}${d.department.isNotEmpty && d.controlType.isNotEmpty ? ', ' : ''}${d.controlType})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Col 2: Hours
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${d.hours}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                    // Col 3: Grade Badge
                    SizedBox(
                      width: 105,
                      child: _buildGradeBadge(context, d, isDark),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGradeBadge(BuildContext context, SessionDiscipline d, bool isDark) {
    Color bg;
    Color text;
    FontWeight weight = FontWeight.w600;

    if (d.isExcellent) {
      bg = isDark ? const Color(0xFF0F381E) : const Color(0xFFE8F5E9);
      text = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      weight = FontWeight.w900;
    } else if (d.isGood) {
      bg = isDark ? const Color(0xFF3E320D) : const Color(0xFFFFF8E1);
      text = isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17);
      weight = FontWeight.w800;
    } else if (d.isCreditPassed) {
      bg = isDark ? const Color(0xFF0F381E) : const Color(0xFFE8F5E9);
      text = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    } else if (d.isSatisfactory) {
      bg = isDark ? const Color(0xFF0F2B38) : const Color(0xFFE1F5FE);
      text = isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0277BD);
    } else if (d.isDebt) {
      bg = isDark ? const Color(0xFF381010) : const Color(0xFFFFEBEE);
      text = isDark ? const Color(0xFFE57373) : const Color(0xFFC62828);
      weight = FontWeight.w800;
    } else {
      bg = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
      text = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: text.withValues(alpha: 0.3)),
      ),
      child: Text(
        d.grade.isEmpty ? '—' : d.grade,
        style: TextStyle(
          fontSize: 12,
          fontWeight: weight,
          color: text,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String disciplinesWord(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'дисциплина';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'дисциплины';
    }
    return 'дисциплин';
  }
}
