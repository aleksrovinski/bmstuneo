import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../widgets/grades/grades_category_tabs.dart';
import '../widgets/grades/grades_status_legend.dart';
import '../widgets/grades/grades_filter_bar.dart';
import '../widgets/grades/discipline_card.dart';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndLoadProgress();
    });
  }

  void _checkAndLoadProgress() {
    final auth = context.read<AuthProvider>();
    final prog = context.read<ProgressProvider>();
    if (auth.isFullAuth && auth.userProfile?.stageUuid != null) {
      if (prog.disciplines.isEmpty && !prog.isLoading) {
        prog.loadProgress(auth.userProfile!.stageUuid);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();
    final prog = context.watch<ProgressProvider>();

    if (auth.isGuest) {
      return _buildGuestScreen(context);
    }

    final currentWeekNum = sched.currentWeek?.weekNumber ?? 1;
    final filteredDisciplines = prog.filteredDisciplines;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Прогресс',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              auth.userProfile?.groupTitle ?? 'МГТУ им. Н.Э. Баумана',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить прогресс',
            onPressed: prog.isLoading ? null : () => prog.refresh(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // 1. Category Switcher Tabs: Текущий / Лабораторные / Семинары
          GradesCategoryTabs(
            activeCategory: prog.activeCategory,
            totalControlsCount: prog.totalControlsCount,
            totalLabsCount: prog.totalLabsCount,
            totalSeminarsCount: prog.totalSeminarsCount,
            onCategoryChanged: (cat) => prog.setActiveCategory(cat),
          ),

          // 2. Status Legend
          const GradesStatusLegend(),

          // 3. Search and Status Filter Bar
          GradesFilterBar(
            searchController: _searchController,
            onSearchChanged: (val) => prog.setSearchQuery(val),
            onClearSearch: () {
              _searchController.clear();
              prog.setSearchQuery('');
            },
            statusFilter: prog.statusFilter,
            onStatusFilterChanged: (f) => prog.setStatusFilter(f),
            totalCount: prog.currentCategoryTotalCount,
            issuedCount: prog.currentCategoryIssuedCount,
            submittedCount: prog.currentCategorySubmittedCount,
            notIssuedCount: prog.currentCategoryNotIssuedCount,
          ),

          // 4. Disciplines and Week Matrix List
          Expanded(
            child: prog.isLoading && prog.disciplines.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => prog.refresh(),
                    child: filteredDisciplines.isEmpty
                        ? _buildEmptyState(context, isDark, prog)
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 6, bottom: 40),
                            itemCount: filteredDisciplines.length,
                            itemBuilder: (context, index) {
                              final disc = filteredDisciplines[index];
                              final events = prog.getEventsForDiscipline(
                                disc,
                                prog.activeCategory,
                              );

                              return DisciplineCard(
                                disc: disc,
                                events: events,
                                currentWeek: currentWeekNum,
                                isDark: isDark,
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, bool isDark, ProgressProvider prog) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 56,
                color: isDark ? Colors.white24 : Colors.black12,
              ),
              const SizedBox(height: 12),
              Text(
                prog.disciplines.isEmpty
                    ? 'Данные о прогрессе не найдены'
                    : 'По вашему фильтру ничего не найдено',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  _searchController.clear();
                  prog.setSearchQuery('');
                  prog.setStatusFilter(ProgressStatusFilter.all);
                  prog.refresh();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Сбросить фильтры'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuestScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Прогресс')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: 44,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Прогресс семестра',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'В гостевом режиме доступно расписание групп. Для просмотра прогресса, баллов, ДЗ, РК, лабораторных и семинаров авторизуйтесь в ЛКС.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => auth.logout(),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Войти в ЛКС'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
