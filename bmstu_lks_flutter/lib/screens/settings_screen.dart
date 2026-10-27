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
import '../widgets/live_activity_settings_sheet.dart';
import '../widgets/notification_settings_card.dart';

/// Everything configurable, opened from the gear on the profile tab.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
        const SnackBar(content: Text('Кэш данных очищен')),
      );
    }
  }

  Future<void> _syncAll() async {
    final auth = context.read<AuthProvider>();
    final sched = context.read<ScheduleProvider>();
    final prog = context.read<ProgressProvider>();
    await sched.refresh();
    if (auth.isFullAuth && (auth.userProfile?.stageUuid.isNotEmpty ?? false)) {
      await prog.refresh();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные обновлены из ЛКС')),
      );
    }
  }

  Future<void> _addWidget() async {
    final sched = context.read<ScheduleProvider>();
    await WidgetSyncService.updateScheduleWidget(scheduleProvider: sched);
    if (!mounted) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _showIosWidgetInstructions(context);
      return;
    }

    final pinned = await WidgetSyncService.isPinningSupported() && await WidgetSyncService.pinWidget();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pinned
            ? 'Подтвердите добавление виджета на экране'
            : 'Удерживайте палец на рабочем столе → Виджеты → BMSTU neo'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sched = context.watch<ScheduleProvider>();
    final prog = context.watch<ProgressProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final timeFormat = DateFormat('dd.MM HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SectionTitle('Оформление'),
          _Group(children: [_buildThemeTile(context, themeProv)]),

          const _SectionTitle('Уведомления и виджет'),
          if (auth.isFullAuth) ...[
            const NotificationSettingsCard(),
            const SizedBox(height: 8),
          ],
          _Group(children: [
            ListTile(
              leading: const Icon(Icons.timelapse_rounded),
              title: const Text('Текущая пара в уведомлении'),
              subtitle: const Text('Live Update с таймером'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => LiveActivitySettingsSheet.show(context),
            ),
            ListTile(
              leading: const Icon(Icons.widgets_rounded),
              title: const Text('Виджет на рабочий стол'),
              subtitle: const Text('Пары на сегодня или на завтра'),
              trailing: const Icon(Icons.add_rounded),
              onTap: _addWidget,
            ),
          ]),

          const _SectionTitle('Данные'),
          _Group(children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Расписание группы'),
              subtitle: Text(_syncLine(sched.syncStatus?.isLive, sched.syncStatus?.lastUpdated, timeFormat,
                  '${sched.allLessons.length} занятий')),
            ),
            if (auth.isFullAuth)
              ListTile(
                leading: const Icon(Icons.school_rounded),
                title: const Text('Успеваемость'),
                subtitle: Text(_syncLine(prog.syncStatus?.isLive, prog.syncStatus?.lastUpdated, timeFormat,
                    '${prog.disciplines.length} дисциплин')),
              ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Обновить всё сейчас'),
              enabled: !(sched.isLoading || prog.isLoading),
              onTap: _syncAll,
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_rounded),
              title: const Text('Очистить кэш'),
              subtitle: const Text('Нужен для работы без интернета'),
              trailing: Text(
                _isLoadingCacheStats ? '…' : (_cacheStats?.formattedTotalSize ?? '0 КБ'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              onTap: _clearCache,
            ),
          ]),

          const _SectionTitle('О приложении'),
          _Group(children: [
            ListTile(
              leading: const BmstuNeoLogo(size: 32),
              title: Text('${AppVersion.appName} ${AppVersion.displayVersion}'),
              subtitle: const Text('Неофициальный клиент ЛКС МГТУ им. Н.Э. Баумана'),
            ),
          ]),
        ],
      ),
    );
  }

  String _syncLine(bool? isLive, DateTime? updated, DateFormat format, String count) {
    if (updated == null) return 'Ещё не загружено';
    return '${isLive == true ? 'Обновлено' : 'Сохранённая копия'} ${format.format(updated)} · $count';
  }

  Widget _buildThemeTile(BuildContext context, ThemeProvider themeProv) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeMode>(
              segments: [
                for (final mode in AppThemeMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(mode.icon, size: 18),
                    label: Text(mode == AppThemeMode.system ? 'Авто' : mode.title),
                  ),
              ],
              showSelectedIcon: false,
              selected: {themeProv.themeMode},
              onSelectionChanged: (set) => themeProv.setThemeMode(set.first),
            ),
          ),
          const SizedBox(height: 16),
          Text('Цвет: ${themeProv.accentColor.title}', style: theme.textTheme.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in AppAccentColor.values)
                _AccentSwatch(
                  color: item,
                  selected: themeProv.accentColor == item,
                  onTap: () => themeProv.setAccentColor(item),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showIosWidgetInstructions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Как добавить виджет', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('1. Зажмите свободное место на экране «Домой».'),
              const SizedBox(height: 6),
              const Text('2. Нажмите «+» в верхнем углу.'),
              const SizedBox(height: 6),
              const Text('3. Найдите BMSTU neo и выберите размер.'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Rounded block that holds related rows, separated by thin dividers.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final AppAccentColor color;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDynamic = color == AppAccentColor.dynamicColor;
    return Tooltip(
      message: color.title,
      child: Semantics(
        button: true,
        selected: selected,
        label: color.title,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isDynamic
                  ? const SweepGradient(colors: [
                      Color(0xFF388E3C),
                      Color(0xFF1976D2),
                      Color(0xFF7B1FA2),
                      Color(0xFFE64A19),
                      Color(0xFF388E3C),
                    ])
                  : null,
              color: isDynamic ? null : color.color,
              border: Border.all(
                color: selected ? theme.colorScheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : (isDynamic ? const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18) : null),
          ),
        ),
      ),
    );
  }
}
