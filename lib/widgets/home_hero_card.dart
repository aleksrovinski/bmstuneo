import 'dart:async';
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

  String _getBaumanGreeting(String studentName) =>
      HomeGreetings.forTime(DateTime.now(), studentName);

  static const _weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();

    final user = auth.userProfile;
    final status = sched.getLivePairStatus();
    final todayLessons = sched.lessonsForToday;

    final hasQrPass = auth.isFullAuth && user?.qrUrl != null && user!.qrUrl!.isNotEmpty;
    final isInProgress = status.type == LivePairType.inProgress;
    final lesson = isInProgress ? status.currentLesson : status.nextLesson;

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

    // A countdown over days is noise; the day and time below say it better
    var headline = status.headline;
    String? when;
    if (lesson != null) {
      if (isInProgress) {
        when = 'до ${lesson.endTime}';
      } else if (lesson.day != DateTime.now().weekday) {
        when = '${_weekdaysShort[(lesson.day - 1).clamp(0, 6)]}, ${lesson.startTime}';
        headline = 'Следующая пара';
      } else {
        when = 'в ${lesson.startTime}';
      }
    }

    final onCard = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.85);
    final greeting = _getBaumanGreeting(user?.firstName ?? '').split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting + pass
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting.first,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: onCard),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (greeting.length > 1)
                      Text(
                        greeting[1],
                        style: TextStyle(fontSize: 12, color: dim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (hasQrPass) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => QrPassDialog.show(
                    context,
                    qrUrl: user.qrUrl!,
                    studentName: user.fullName,
                    groupTitle: user.groupTitle,
                  ),
                  tooltip: 'Пропуск',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: onCard,
                  ),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 22),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Current or next pair: what, where, until when (tap → Live Update settings)
          Material(
            color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.16),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => LiveActivitySettingsSheet.show(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(statusIcon, color: onCard, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: dim,
                              // Fixed-width digits: the countdown ticks every second without jitter
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lesson?.disciplineTitle ?? status.subline,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: onCard, height: 1.2),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (lesson != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded, size: 14, color: onCard),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    lesson.displayAudiences,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onCard),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(Icons.schedule_rounded, size: 14, color: dim),
                                const SizedBox(width: 3),
                                Text(when!, style: TextStyle(fontSize: 12.5, color: dim)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer: today at a glance + link to the schedule
          InkWell(
            onTap: widget.onOpenSchedule,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      todayLessons.isEmpty ? 'Сегодня пар нет' : 'Сегодня пар: ${todayLessons.length}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dim),
                    ),
                  ),
                  Text('Расписание', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onCard)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: onCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Greeting on the home hero card: a pool of phrases per part of the day.
///
/// The phrase is picked from the date, not at random: the card rebuilds every
/// second for the countdown, so it must stay the same within a part of the day
/// and change from one day to the next.
class HomeGreetings {
  static const _morning = [
    ('Доброе утро', '☕', 'Кофе выпит, гранит науки ждёт!'),
    ('Доброе утро', '🌅', 'Первая пара сама себя не посетит.'),
    ('С добрым утром', '🎒', 'Пропуск, конспект, зарядка — проверь всё.'),
    ('Доброе утро', '⚙️', 'Сегодня отличный день, чтобы сдать лабу.'),
    ('Подъём', '⏰', 'До ГУКа ещё надо доехать — не тяни.'),
  ];
  static const _day = [
    ('Привет', '🚀', 'Держи хвост пистолетом, а лабы — сданными!'),
    ('Привет', '🧮', 'Половина дня позади, половина формул впереди.'),
    ('Здравствуй', '🍜', 'Не забудь пообедать между парами.'),
    ('Привет', '📐', 'Чертёж сам себя не начертит.'),
    ('Хорошего дня', '💡', 'Задай вопрос на семинаре — это засчитывается.'),
  ];
  static const _evening = [
    ('Добрый вечер', '📚', 'Время закрывать хвосты и готовиться к РК!'),
    ('Добрый вечер', '📝', 'Самое время разобрать сегодняшний конспект.'),
    ('Добрый вечер', '🧪', 'Отчёт по лабе лучше написать сегодня, чем в ночь перед сдачей.'),
    ('Вечер добрый', '🎧', 'Пары закончились — можно и выдохнуть.'),
    ('Добрый вечер', '🗓', 'Загляни в расписание на завтра, чтобы утром не бежать.'),
  ];
  static const _night = [
    ('Ночь в Бауманке', '🌙', 'Слава роботам и крепким нервам!'),
    ('Доброй ночи', '😴', 'Сон тоже входит в подготовку к экзамену.'),
    ('Доброй ночи', '🦉', 'Курсовая подождёт до утра. Наверное.'),
    ('Глубокая ночь', '✨', 'Закрывай ноутбук — завтра первая пара.'),
  ];
  static const _weekend = [
    ('Хороших выходных', '🛋', 'Отдыхай, а дедлайны подождут до понедельника.'),
    ('Хороших выходных', '🌿', 'Самое время доделать то, что копилось всю неделю.'),
    ('Привет', '🎮', 'Заслуженный отдых — тоже часть учёбы.'),
    ('Привет', '☀️', 'В выходные пар нет, а ДЗ — есть. Но можно и погулять.'),
  ];

  static String forTime(DateTime now, String studentName) {
    final name = studentName.isNotEmpty ? ', $studentName' : '';
    final hour = now.hour;
    final isNight = hour >= 23 || hour < 6;
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    final List<(String, String, String)> pool;
    if (isNight) {
      pool = _night;
    } else if (isWeekend) {
      pool = _weekend;
    } else if (hour < 12) {
      pool = _morning;
    } else if (hour < 18) {
      pool = _day;
    } else {
      pool = _evening;
    }

    final dayIndex = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final (hello, emoji, line) = pool[dayIndex % pool.length];
    return '$hello$name! $emoji\n$line';
  }
}
