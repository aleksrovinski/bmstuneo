import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_lesson.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/pair_card.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/add_custom_lesson_sheet.dart';
import '../widgets/offline_status_banner.dart';
import 'teacher_schedule_screen.dart';

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

  void _pickGroup(BuildContext context, String currentGroupTitle) {
    final auth = context.read<AuthProvider>();
    final sched = context.read<ScheduleProvider>();
    GroupPickerSheet.show(context, currentGroupTitle: currentGroupTitle).then((group) {
      if (group == null) return;
      if (auth.isGuest) auth.setGuestGroup(group.title, group.uuid);
      sched.switchGroup(group);
    });
  }

  void _selectDay(ScheduleProvider sched, int index) {
    sched.setSelectedDay(index + 1);
    _dayPageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();

    final currentGroupTitle = sched.currentGroupTitle.isNotEmpty ? sched.currentGroupTitle : auth.currentGroupTitle;

    final now = DateTime.now();
    final week = sched.currentWeek;
    final isCurrentNumerator = week?.isNumerator ?? true;
    // Dates under the day names; on Sunday the strip already shows the coming week
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: now.weekday == DateTime.sunday ? 7 : 0));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: InkWell(
          onTap: () => _pickGroup(context, currentGroupTitle),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(currentGroupTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Icon(Icons.expand_more_rounded, size: 22, color: scheme.onSurfaceVariant),
                  ],
                ),
                Text(
                  week == null
                      ? 'Расписание'
                      : '${week.weekNumber} неделя · ${isCurrentNumerator ? 'числитель' : 'знаменатель'}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded),
            tooltip: 'Расписание преподавателя',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TeacherScheduleScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddCustomLesson(context),
        tooltip: 'Добавить своё занятие',
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          if (sched.syncStatus != null && !sched.syncStatus!.isLive)
            OfflineStatusBanner(
              message: sched.syncStatus?.message,
              lastUpdated: sched.syncStatus?.lastUpdated,
              onRetry: sched.isLoading ? null : () => sched.refresh(),
            ),

          // Week filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                segments: const [
                  ButtonSegment(value: 'current', label: Text('Текущая', maxLines: 1, softWrap: false)),
                  ButtonSegment(value: 'numerator', label: Text('Числ.')),
                  ButtonSegment(value: 'denominator', label: Text('Знам.')),
                  ButtonSegment(value: 'all', label: Text('Все')),
                ],
                selected: {sched.selectedWeekFilter},
                onSelectionChanged: (selection) => sched.setSelectedWeekFilter(selection.first),
              ),
            ),
          ),

          // Day strip: weekday and date, today marked by color
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: List.generate(6, (index) {
                final dayNum = index + 1;
                final isSelected = sched.selectedDay == dayNum;
                final date = monday.add(Duration(days: index));
                final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                final foreground = isSelected ? scheme.onPrimary : (isToday ? scheme.primary : scheme.onSurface);

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    label: '${ScheduleScreen.daysFull[index]}, ${date.day}${isToday ? ', сегодня' : ''}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _selectDay(sched, index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? scheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              ScheduleScreen.daysShort[index],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? scheme.onPrimary.withValues(alpha: 0.85) : scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${date.day}',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: foreground),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),

          // Days, swipeable
          Expanded(
            child: sched.isLoading && sched.allLessons.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : PageView.builder(
                    controller: _dayPageController,
                    itemCount: 6,
                    onPageChanged: (index) => sched.setSelectedDay(index + 1),
                    itemBuilder: (context, index) {
                      final dayLessons = sched.getLessonsForDay(index + 1, sched.selectedWeekFilter);

                      return RefreshIndicator(
                        onRefresh: () => sched.refresh(),
                        child: dayLessons.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(32, 72, 32, 80),
                                children: [
                                  Icon(Icons.event_available_rounded, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Пар нет',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Проверьте фильтр недели или добавьте своё занятие кнопкой +',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
                                itemCount: dayLessons.length,
                                itemBuilder: (context, lessonIdx) {
                                  final lesson = dayLessons[lessonIdx];
                                  return PairCard(
                                    lesson: lesson,
                                    onDelete: lesson.isCustom ? () => _confirmDeleteLesson(context, lesson) : null,
                                  );
                                },
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
