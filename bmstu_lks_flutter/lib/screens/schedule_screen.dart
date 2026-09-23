import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_lesson.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/pair_card.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/add_custom_lesson_sheet.dart';
import '../widgets/live_activity_settings_sheet.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  static const List<String> daysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ'];
  static const List<String> daysFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
  ];

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final PageController _dayPageController;

  @override
  void initState() {
    super.initState();
    final initialDay = context.read<ScheduleProvider>().selectedDay;
    _dayPageController =
        PageController(initialPage: (initialDay - 1).clamp(0, 5));
  }

  @override
  void dispose() {
    _dayPageController.dispose();
    super.dispose();
  }

  Future<void> _openAddCustomLesson(BuildContext context) async {
    final sched = context.read<ScheduleProvider>();
    final newLesson = await AddCustomLessonSheet.show(
      context,
      initialDay: sched.selectedDay,
    );

    if (newLesson != null && context.mounted) {
      await sched.addCustomLesson(newLesson);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Занятие "${newLesson.disciplineTitle}" добавлено!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteLesson(
      BuildContext context, ScheduleLesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить занятие?'),
        content: Text(
            'Вы действительно хотите удалить занятие "${lesson.disciplineTitle}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted && lesson.id != null) {
      await context.read<ScheduleProvider>().deleteCustomLesson(lesson.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Занятие удалено')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();

    final currentGroupTitle = sched.currentGroupTitle.isNotEmpty
        ? sched.currentGroupTitle
        : auth.currentGroupTitle;

    final todayWeekday = DateTime.now().weekday;
    final isCurrentNumerator = sched.currentWeek?.isNumerator ?? true;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Расписание занятий',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            InkWell(
              onTap: () {
                GroupPickerSheet.show(context,
                        currentGroupTitle: currentGroupTitle)
                    .then((group) {
                  if (group != null) {
                    if (auth.isGuest) {
                      auth.setGuestGroup(group.title, group.uuid);
                    }
                    sched.switchGroup(group);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentGroupTitle,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: 'Live Activity и виджет',
            onPressed: () => LiveActivitySettingsSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить расписание',
            onPressed: sched.isLoading ? null : () => sched.refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddCustomLesson(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Своя пара'),
        tooltip: 'Добавить своё занятие в расписание',
      ),
      body: Column(
        children: [
          // 1. Segmented Button for Week Filter
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'current',
                    label: Text(
                      'Текущая (${isCurrentNumerator ? "Числ." : "Знам."})',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                  ),
                  const ButtonSegment<String>(
                    value: 'numerator',
                    label: Text(
                      'Числитель',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const ButtonSegment<String>(
                    value: 'denominator',
                    label: Text(
                      'Знаменатель',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const ButtonSegment<String>(
                    value: 'all',
                    label: Text(
                      'Все недели',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                selected: {sched.selectedWeekFilter},
                onSelectionChanged: (newSelection) {
                  sched.setSelectedWeekFilter(newSelection.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: theme.colorScheme.primary,
                  selectedForegroundColor: theme.colorScheme.onPrimary,
                  backgroundColor: isDark
                      ? theme.colorScheme.surfaceContainer
                      : theme.colorScheme.surfaceContainerLow,
                  foregroundColor: theme.colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),

          // 2. Day Selector Bar (ПН — СБ) with animated click and swipe sync
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: isDark
                ? theme.colorScheme.surfaceContainer
                : theme.colorScheme.surfaceContainerLow,
            child: Row(
              children: List.generate(6, (index) {
                final dayNum = index + 1;
                final isSelected = sched.selectedDay == dayNum;
                final isToday = todayWeekday == dayNum;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      sched.setSelectedDay(dayNum);
                      _dayPageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark
                                ? theme.colorScheme.surfaceContainerHigh
                                : theme.colorScheme.surface),
                        borderRadius: BorderRadius.circular(14),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: theme.colorScheme.primary, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ScheduleScreen.daysShort[index],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // 3. PageView supporting swipe gestures between days of the week (ПН -> СБ)
          Expanded(
            child: sched.isLoading
                ? const Center(child: CircularProgressIndicator())
                : PageView.builder(
                    controller: _dayPageController,
                    itemCount: 6,
                    onPageChanged: (index) {
                      sched.setSelectedDay(index + 1);
                    },
                    itemBuilder: (context, index) {
                      final dayNum = index + 1;
                      final dayLessons = sched.getLessonsForDay(
                          dayNum, sched.selectedWeekFilter);

                      return RefreshIndicator(
                        onRefresh: () => sched.refresh(),
                        child: Column(
                          children: [
                            // Day Title Header & Pair Count
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 12, 20, 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    ScheduleScreen.daysFull[index],
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${dayLessons.length} пар(ы)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Lessons list or Empty state
                            Expanded(
                              child: dayLessons.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        const SizedBox(height: 80),
                                        Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.event_busy_rounded,
                                                size: 56,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.3),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'В этот день пар нет!',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: theme
                                                      .colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Проверьте фильтр или добавьте своё занятие ✨',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              FilledButton.tonalIcon(
                                                onPressed: () =>
                                                    _openAddCustomLesson(
                                                        context),
                                                icon: const Icon(
                                                    Icons.add_rounded,
                                                    size: 18),
                                                label: const Text(
                                                    'Добавить своё занятие'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          0, 8, 0, 80),
                                      itemCount: dayLessons.length,
                                      itemBuilder: (context, lessonIdx) {
                                        final lesson = dayLessons[lessonIdx];
                                        return PairCard(
                                          lesson: lesson,
                                          onDelete: lesson.isCustom
                                              ? () => _confirmDeleteLesson(
                                                  context, lesson)
                                              : null,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
