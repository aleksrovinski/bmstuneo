import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/theme_provider.dart';
import '../services/widget_sync_service.dart';
import '../services/cache_service.dart';
import '../constants/app_version.dart';
import '../widgets/bmstu_neo_logo.dart';
import '../widgets/student_id_card.dart';
import '../models/user_profile.dart';
import 'gradebook_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  CacheStats? _cacheStats;
  bool _isLoadingCacheStats = false;

  @override
  void initState() {
    super.initState();
    _loadCacheStats();
  }

  Future<void> _loadCacheStats() async {
    setState(() => _isLoadingCacheStats = true);
    final stats = await AppCacheManager.instance.getStats();
    if (mounted) {
      setState(() {
        _cacheStats = stats;
        _isLoadingCacheStats = false;
      });
    }
  }

  Future<void> _clearCache() async {
    await AppCacheManager.instance.clearAll();
    await _loadCacheStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Кэш данных успешно очищен'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();
    final prog = context.watch<ProgressProvider>();
    ThemeProvider? themeProv;
    try {
      themeProv = context.watch<ThemeProvider>();
    } catch (_) {}
    themeProv ??= ThemeProvider();

    final user = auth.userProfile ??
        UserProfile(
          lastName: 'Студент',
          firstName: 'МГТУ',
          middleName: '',
          groupTitle: auth.currentGroupTitle,
          groupUuid: auth.currentGroupUuid,
          stageUuid: '',
        );

    final timeFormat = DateFormat('HH:mm:ss dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль и статус'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Digital Student ID Card
            StudentIdCard(
              user: user,
              isGuest: auth.isGuest,
            ),
            const SizedBox(height: 20),

            // 2. Electronic Gradebook Quick Card
            _buildGradebookCard(context, auth, prog),
            const SizedBox(height: 20),

            // 3. Theme & Styling Section
            _buildThemeSection(context, themeProv),
            const SizedBox(height: 20),

            // 4. Real-Time Sync Section
            Text(
              'Синхронизация с серверами МГТУ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                children: [
                  _buildSyncRow(
                    context,
                    label: 'Расписание группы',
                    status: sched.syncStatus?.isLive == true ? 'Онлайн' : 'Офлайн',
                    time: sched.syncStatus != null
                        ? timeFormat.format(sched.syncStatus!.lastUpdated)
                        : '—',
                    count: '${sched.allLessons.length} занятий',
                  ),
                  if (auth.isFullAuth) ...[
                    const Divider(height: 24),
                    _buildSyncRow(
                      context,
                      label: 'Прогресс и БРС',
                      status: prog.syncStatus?.isLive == true ? 'Онлайн' : 'Офлайн',
                      time: prog.syncStatus != null
                          ? timeFormat.format(prog.syncStatus!.lastUpdated)
                          : '—',
                      count: '${prog.disciplines.length} дисциплин',
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (sched.isLoading || prog.isLoading)
                          ? null
                          : () async {
                              await sched.refresh();
                              if (auth.isFullAuth && user.stageUuid.isNotEmpty) {
                                await prog.refresh();
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Данные успешно обновлены из ЛКС МГТУ!'),
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Синхронизировать всё сейчас'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(color: theme.colorScheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Cache & Memory Section
            _buildCacheSection(context),
            const SizedBox(height: 20),

            // 6. Home Screen Widget Section
            Text(
              'Виджет на рабочий стол',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.widgets_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Расписание пар на экране',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Автоматически показывает сегодняшние или завтрашние пары',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await WidgetSyncService.updateScheduleWidget(scheduleProvider: sched);
                        if (!context.mounted) return;

                        if (defaultTargetPlatform == TargetPlatform.iOS) {
                          _showIosWidgetInstructions(context);
                          return;
                        }

                        final supported = await WidgetSyncService.isPinningSupported();
                        if (supported) {
                          final pinned = await WidgetSyncService.pinWidget();
                          if (!context.mounted) return;
                          if (pinned) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Запрос на добавление виджета отправлен! Подтвердите на экране.'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Удерживайте палец на рабочем столе и выберите "Виджеты" -> "Расписание пар МГТУ"'),
                              ),
                            );
                          }
                        } else {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Для добавления виджета: удерживайте палец на рабочем столе -> Виджеты -> BMSTU neo'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                      label: const Text('Добавить виджет на рабочий стол', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 7. About BMSTU neo Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const BmstuNeoLogo(size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              AppVersion.appName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                AppVersion.displayVersion,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Клиент ЛКС МГТУ им. Н.Э. Баумана нового поколения',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 8. Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await auth.logout();
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  auth.isGuest ? 'Выйти из гостевого режима' : 'Выйти из аккаунта',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  foregroundColor: theme.colorScheme.error,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildGradebookCard(BuildContext context, AuthProvider auth, ProgressProvider prog) {
    final theme = Theme.of(context);
    final gpa = prog.gpa;
    final status = prog.scholarshipStatus;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.menu_book_rounded, color: theme.colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Электронная зачётная книжка',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auth.isGuest
                          ? 'Доступно после авторизации в ЛКС'
                          : 'Средний балл: ${gpa > 0 ? gpa.toStringAsFixed(2) : "—"} • ${status.title}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: auth.isGuest
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GradebookScreen()),
                      );
                    },
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('Открыть зачётку и семестры', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context, ThemeProvider themeProv) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Оформление и тема',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Theme Mode Segmented Button
              Text(
                'Режим темы',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('Авто', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.brightness_auto_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Светлая', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.light_mode_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Тёмная', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.dark_mode_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.oled,
                    label: Text('OLED', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.contrast_rounded, size: 16),
                  ),
                ],
                selected: {themeProv.themeMode},
                onSelectionChanged: (set) => themeProv.setThemeMode(set.first),
              ),
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4), height: 1),
              const SizedBox(height: 14),

              // Accent Color Palette
              Text(
                'Цветовой акцент интерфейса',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AppAccentColor.values.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 10),
                  itemBuilder: (context, idx) {
                    final item = AppAccentColor.values[idx];
                    final isSelected = themeProv.accentColor == item;

                    return GestureDetector(
                      onTap: () => themeProv.setAccentColor(item),
                      child: Tooltip(
                        message: item.title,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.color,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              if (isSelected)
                                BoxShadow(
                                  color: item.color.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                            ],
                          ),
                          child: isSelected
                              ? const Center(
                                  child: Icon(Icons.check_rounded, color: Colors.white, size: 22),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCacheSection(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _cacheStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Память и кэш данных',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Размер сохранённого кэша',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    _isLoadingCacheStats ? '...' : (stats?.formattedTotalSize ?? '0 КБ'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Кэш обеспечивает мгновенный запуск и полную работу расписания и зачётки в подвальных аудиториях без интернета.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _clearCache,
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text('Очистить локальный кэш'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncRow(
    BuildContext context, {
    required String label,
    required String status,
    required String time,
    required String count,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const Icon(
          Icons.cloud_done_rounded,
          size: 20,
          color: Color(0xFF10B981),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                '$time • $count',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF10B981),
            ),
          ),
        ),
      ],
    );
  }

  void _showIosWidgetInstructions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.widgets_rounded, color: theme.colorScheme.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Виджет для iOS готов',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Расписание синхронизировано',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Чтобы разместить виджет на экране iPhone:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _buildStepRow(theme, '1', 'Перейдите на экран «Домой» и зажмите любую свободную область.'),
              const SizedBox(height: 8),
              _buildStepRow(theme, '2', 'Нажмите значок «+» в верхнем углу экрана.'),
              const SizedBox(height: 8),
              _buildStepRow(theme, '3', 'Найдите в списке BMSTU neo и выберите удобный размер виджета.'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Понятно', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(ThemeData theme, String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
