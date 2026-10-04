import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session_result.dart';
import '../providers/auth_provider.dart';

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
      final results = await auth.apiService.getSessionResults(
        stageUuid: auth.userProfile?.stageUuid,
        forceRefresh: forceRefresh,
      );
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
              user?.groupTitle ?? 'МГТУ им. Н.Э. Баумана',
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
                : _buildSessionContent(context, isDark, latestUpdate),
      ),
    );
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
    String? latestUpdate,
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
        // 1. "Данные актуальны на ..." (Matching LKS web)
        if (latestUpdate != null && latestUpdate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              latestUpdate,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // 2. Card header with Title & Dropdown (Matching LKS PrimeReact Card)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Результаты сессий',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // PrimeReact Dropdown replica
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHighest
                          : colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedSemesterNumber,
                        isDense: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Показать все',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          ..._sessions.map((s) => DropdownMenuItem<int?>(
                                value: s.semesterNumber,
                                child: Text(
                                  s.semesterTitle,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
              // Compact Filter Chips
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
        const SizedBox(height: 16),

        // 3. Tables for each Semester (Matching LKS web table container)
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
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      color: isDark ? colorScheme.surfaceContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Semester Header: <h1>Семестр N</h1>
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  session.semesterTitle,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${disciplines.length} ${disciplinesWord(disciplines.length)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Table Header (p-datatable-thead replica)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Дисциплина (Кафедра, тип сдачи)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    'Часы',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows (p-datatable-tbody replica)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: disciplines.length,
            separatorBuilder: (_, index) => Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            itemBuilder: (context, idx) {
              final d = disciplines[idx];
              final isOdd = idx.isOdd;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                color: isOdd
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.012))
                    : Colors.transparent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Col 1: Discipline Title & Department
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: d.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                height: 1.3,
                              ),
                            ),
                            if (d.department.isNotEmpty || d.controlType.isNotEmpty)
                              TextSpan(
                                text: ' (${d.department}${d.department.isNotEmpty && d.controlType.isNotEmpty ? ', ' : ''}${d.controlType})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Col 2: Hours
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${d.hours}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                    // Col 3: Grade Badge (Matching PrimeReact style)
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: weight,
          color: textColor,
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
