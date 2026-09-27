import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import 'qr_pass_dialog.dart';
import 'live_activity_settings_sheet.dart';

class HomeHeroCard extends StatefulWidget {
  final VoidCallback onOpenSchedule;

  const HomeHeroCard({
    super.key,
    required this.onOpenSchedule,
  });

  @override
  State<HomeHeroCard> createState() => _HomeHeroCardState();
}

class _HomeHeroCardState extends State<HomeHeroCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Isolated 1-second ticker for real-time countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final isIOS = theme.platform == TargetPlatform.iOS;

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();

    final user = auth.userProfile;
    final status = sched.getLivePairStatus();
    final todayLessons = sched.lessonsForToday;
    final currentWeek = sched.currentWeek;
    final currentWeekNum = currentWeek?.weekNumber ?? 1;
    final isNumerator = currentWeek?.isNumerator ?? true;

    final hasQrPass = auth.isFullAuth &&
        user?.qrUrl != null &&
        user!.qrUrl!.isNotEmpty;

    final isInProgress = status.type == LivePairType.inProgress;

    IconData statusIcon;
    switch (status.type) {
      case LivePairType.inProgress:
        statusIcon = Icons.play_circle_fill_rounded;
        break;
      case LivePairType.upcoming:
        statusIcon = Icons.alarm_rounded;
        break;
      case LivePairType.noPairsToday:
      case LivePairType.sunday:
        statusIcon = Icons.beach_access_rounded;
        break;
      default:
        statusIcon = Icons.check_circle_outline_rounded;
        break;
    }

    final cardContent = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                colors: [
                  theme.colorScheme.surfaceContainerHigh,
                  theme.colorScheme.surfaceContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(26),
        border: isIOS
            ? Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.35),
                width: 1,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : theme.colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Greeting + Compact Pass Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _getBaumanGreeting(user?.firstName ?? ''),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.32,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (hasQrPass) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => QrPassDialog.show(
                      context,
                      qrUrl: user.qrUrl!,
                      studentName: user.fullName,
                      groupTitle: user.groupTitle,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.38),
                          width: 1.0,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Пропуск',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Row 2: Unified Next/Live Lesson status block (Tap opens Live Activity settings)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => LiveActivitySettingsSheet.show(context),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: isInProgress ? 0.28 : 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          statusIcon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.headline,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status.subline,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Row 3: Footer with day stats & quick link
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Сегодня: ${todayLessons.length} пар(ы) • $currentWeekNum нед (${isNumerator ? "Числ" : "Знам"})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              InkWell(
                onTap: widget.onOpenSchedule,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Все пары',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: isIOS
          ? ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: cardContent,
              ),
            )
          : cardContent,
    );
  }
}
