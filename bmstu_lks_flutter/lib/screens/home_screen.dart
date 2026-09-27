import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/fv_provider.dart';
import '../widgets/pair_card.dart';
import '../widgets/deadline_card.dart';
import '../widgets/home_hero_card.dart';
import '../models/nearest_pe_lesson.dart';
import '../services/widget_sync_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenGrades;
  final VoidCallback onOpenFv;

  const HomeScreen({
    super.key,
    required this.onOpenSchedule,
    required this.onOpenGrades,
    required this.onOpenFv,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final enabled = await WidgetSyncService.isLiveNotificationEnabled();
      if (enabled) {
        final hasPermission = await WidgetSyncService.hasNotificationPermission();
        if (!hasPermission) {
          await WidgetSyncService.requestNotificationPermission();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();
    final prog = context.watch<ProgressProvider>();
    final fv = context.watch<FvProvider>();

    final user = auth.userProfile;
    final currentWeek = sched.currentWeek;
    final currentWeekNum = currentWeek?.weekNumber ?? 1;
    final liveStatus = sched.getLivePairStatus();
    final nearestDeadlines = prog.getNearestDeadlines(currentWeekNum, limit: 3);
    final todayLessons = sched.lessonsForToday;

    final nearestPe = NearestPeLesson.findNearest(
      records: fv.currentRecords,
      lessons: sched.allLessons,
      isCurrentWeekNumerator: sched.currentWeek?.isNumerator ?? true,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              auth.isGuest ? 'Гостевой режим' : (user?.groupTitle ?? 'Студент'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              auth.isGuest ? 'МГТУ им. Н.Э. Баумана' : '${user?.lastName} ${user?.firstName}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          // Week Badge
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (currentWeek?.isNumerator ?? true)
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (currentWeek?.isNumerator ?? true)
                    ? theme.colorScheme.primary.withValues(alpha: 0.35)
                    : theme.colorScheme.tertiary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: (currentWeek?.isNumerator ?? true)
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  '$currentWeekNum нед • ${currentWeek?.isNumerator == true ? "Числ" : "Знам"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: (currentWeek?.isNumerator ?? true)
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await sched.refresh();
          if (auth.isFullAuth && user?.stageUuid != null) {
            await Future.wait([
              prog.refresh(),
              fv.refresh(),
            ]);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // 1. Unified Hero Card (Greeting + Next/Live Pair Tracker + Compact Pass Button)
              HomeHeroCard(
                onOpenSchedule: widget.onOpenSchedule,
              ),

              // 2. Physical Culture Quick Card
              if (auth.isFullAuth || nearestPe != null) ...[
                _buildFvBanner(context, fv, nearestPe),
              ],

              // 5. Upcoming Deadlines Section
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ближайшие дедлайны и РК',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (auth.isFullAuth)
                      TextButton(
                        onPressed: widget.onOpenGrades,
                        child: const Text('Прогресс →', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              if (auth.isGuest)
                _buildGuestFeatureNotice('Дедлайны и баллы доступны после авторизации в ЛКС')
              else if (prog.isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (nearestDeadlines.isEmpty)
                _buildEmptyNotice('Нет горящих дедлайнов на ближайшие недели! 🎉')
              else
                ...nearestDeadlines.map(
                  (c) => DeadlineCard(
                    event: c,
                    status: prog.getStatusForEvent(c, currentWeekNum),
                  ),
                ),

              // 6. Schedule Preview (Today or Tomorrow if today ended)
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (liveStatus.type == LivePairType.finishedForToday || todayLessons.isEmpty)
                                ? 'Пары на завтра (${sched.tomorrowDayTitle})'
                                : 'Расписание на сегодня',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          if (liveStatus.type == LivePairType.finishedForToday)
                            Text(
                              'Пары на сегодня уже закончились',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onOpenSchedule,
                      child: const Text('Всё расписание →', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              if (liveStatus.type == LivePairType.finishedForToday || todayLessons.isEmpty) ...[
                if (sched.lessonsForTomorrow.isEmpty)
                  _buildEmptyNotice(
                    sched.tomorrowWeekday == 7
                        ? 'Завтра воскресенье — пар нет! Отдыхайте! ✨'
                        : 'На завтра (${sched.tomorrowDayTitle}) пар нет ✨',
                  )
                else
                  ...sched.lessonsForTomorrow.map((l) => PairCard(lesson: l, isCurrent: false)),
              ] else ...[
                ...todayLessons.map((l) {
                  final isCurrent = liveStatus.currentLesson?.time == l.time;
                  return PairCard(lesson: l, isCurrent: isCurrent);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildGuestFeatureNotice(String message) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyNotice(String text) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFvBanner(BuildContext context, FvProvider fv, NearestPeLesson? nearestPe) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isIOS = theme.platform == TargetPlatform.iOS;
    final data = fv.data;
    final isCreditReady = data?.isCreditReady ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isIOS
            ? (isDark
                ? colorScheme.surfaceContainer.withValues(alpha: 0.72)
                : colorScheme.surfaceContainerLow.withValues(alpha: 0.82))
            : (isDark ? colorScheme.surfaceContainer : colorScheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isIOS && isDark
              ? Colors.white.withValues(alpha: 0.12)
              : colorScheme.outlineVariant,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onOpenFv,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.fitness_center_rounded,
                        color: colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Физкультура (ФКиС)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isCreditReady) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Зачёт готов! 🎉',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${fv.studyPoints}/60 б. • ${fv.studyAttends}/25 пос.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Nearest PE Lesson box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: nearestPe?.isNow == true
                        ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                        : (isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: nearestPe?.isNow == true
                          ? colorScheme.primary.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        nearestPe?.isNow == true
                            ? Icons.play_circle_fill_rounded
                            : Icons.alarm_on_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nearestPe != null
                                  ? 'Ближайшая пара: ${nearestPe.dayTitle}, ${nearestPe.time}'
                                  : 'Ближайших занятий не найдено',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: nearestPe?.isNow == true
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nearestPe != null
                                  ? '${nearestPe.title} • ${nearestPe.place}${nearestPe.teacher.isNotEmpty ? " • ${nearestPe.teacher}" : ""}'
                                  : 'Нажмите для перехода в раздел ФКиС',
                              style: TextStyle(
                                fontSize: 11,
                                color: nearestPe?.isNow == true
                                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.85)
                                    : colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
