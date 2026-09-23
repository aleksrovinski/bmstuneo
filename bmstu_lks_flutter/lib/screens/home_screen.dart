import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/fv_provider.dart';
import '../widgets/pair_card.dart';
import '../widgets/deadline_card.dart';
import '../widgets/qr_pass_dialog.dart';
import '../widgets/live_tracker_card.dart';
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

  String _getBaumanGreeting(String studentName) {
    final hour = DateTime.now().hour;
    final name = studentName.isNotEmpty ? ', $studentName' : ', Бауманец';

    if (hour >= 6 && hour < 12) {
      return 'Доброе утро$name! ☕\nКофе выпит, гранит науки ждёт!';
    } else if (hour >= 12 && hour < 18) {
      return 'Здравствуй$name! 🚀\nДержи хвост пистолетом, а лабы сданными!';
    } else if (hour >= 18 && hour < 23) {
      return 'Добрый вечер$name! 📚\nВремя закрывать хвосты и готовиться к РК!';
    } else {
      return 'Ночь в Бауманке$name... 🌙\nСлава роботам и крепким нервам!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

              // 1. Original Bauman Greeting Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [theme.colorScheme.surfaceContainerHigh, theme.colorScheme.surfaceContainer]
                        : [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.82)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getBaumanGreeting(user?.firstName ?? ''),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Сегодня: ${todayLessons.length} пар(ы)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Live Pair Tracker Card (isolated real-time countdown)
              const LiveTrackerCard(),

              // 3. Digital Pass (QR-код) Quick Card
              if (auth.isFullAuth && user?.qrUrl != null && user!.qrUrl!.isNotEmpty) ...[
                _buildQrPassBanner(context, user.qrUrl!, user.fullName, user.groupTitle),
              ],

              // 4. Physical Culture Quick Card
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

  Widget _buildQrPassBanner(
    BuildContext context,
    String qrUrl,
    String studentName,
    String groupTitle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => QrPassDialog.show(
        context,
        qrUrl: qrUrl,
        studentName: studentName,
        groupTitle: groupTitle,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Miniature QR
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
              ),
              child: CachedNetworkImage(
                imageUrl: qrUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.qr_code,
                  size: 24,
                  color: Colors.black45,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Электронный пропуск МГТУ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Нажмите для открытия QR-кода турникета',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary),
          ],
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
    final data = fv.data;
    final isCreditReady = data?.isCreditReady ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onOpenFv,
          borderRadius: BorderRadius.circular(18),
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
