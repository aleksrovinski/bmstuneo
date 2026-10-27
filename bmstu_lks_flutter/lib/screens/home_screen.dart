import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/fv_provider.dart';
import '../widgets/pair_card.dart';
import '../widgets/deadline_card.dart';
import '../widgets/home_hero_card.dart';
import '../widgets/offline_status_banner.dart';
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
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    int minutesOf(String hhmm) {
      final parts = hhmm.split(':');
      return parts.length < 2 ? 0 : (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    // Once the last pair of the day is over the list switches to tomorrow
    final showTomorrow = liveStatus.type == LivePairType.finishedForToday ||
        todayLessons.isEmpty ||
        todayLessons.every((l) => minutesOf(l.endTime) <= nowMinutes);

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
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),

              if (sched.syncStatus != null && !sched.syncStatus!.isLive) ...[
                OfflineStatusBanner(
                  message: sched.syncStatus?.message,
                  lastUpdated: sched.syncStatus?.lastUpdated,
                  onRetry: sched.isLoading ? null : () => sched.refresh(),
                ),
                const SizedBox(height: 4),
              ],

              // 1. Unified Hero Card (Greeting + Next/Live Pair Tracker + Compact Pass Button)
              HomeHeroCard(
                onOpenSchedule: widget.onOpenSchedule,
              ),

              // 2. Physical Culture Quick Card
              if (auth.isFullAuth || nearestPe != null) ...[
                _buildFvBanner(context, fv, nearestPe),
              ],

              // Upcoming deadlines
              _buildSectionHeader(
                'Ближайшие дедлайны',
                action: auth.isFullAuth ? 'Успеваемость' : null,
                onAction: widget.onOpenGrades,
              ),

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

              // Schedule preview: today, or tomorrow once today is over
              _buildSectionHeader(
                showTomorrow
                    ? 'Завтра, ${sched.tomorrowDayTitle.toLowerCase()}'
                    : 'Сегодня',
                action: 'Всё расписание',
                onAction: widget.onOpenSchedule,
              ),

              if (showTomorrow) ...[
                if (sched.lessonsForTomorrow.isEmpty)
                  _buildEmptyNotice('Пар нет — можно отдохнуть ✨')
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



  Widget _buildSectionHeader(String title, {String? action, VoidCallback? onAction}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action, style: const TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildGuestFeatureNotice(String message) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
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
    final scheme = Theme.of(context).colorScheme;
    final isCreditReady = fv.data?.isCreditReady ?? false;
    final isNow = nearestPe?.isNow == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isNow ? scheme.primaryContainer.withValues(alpha: 0.55) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onOpenFv,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.fitness_center_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCreditReady
                            ? 'Физкультура · зачёт готов'
                            : 'Физкультура · ${fv.studyPoints}/60 б., ${fv.studyAttends}/25 пос.',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nearestPe != null
                            ? '${isNow ? 'Сейчас' : '${nearestPe.dayTitle}, ${nearestPe.time}'} · ${nearestPe.place}'
                            : 'Ближайших занятий не найдено',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
