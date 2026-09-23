import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../services/widget_sync_service.dart';

class LiveActivitySettingsSheet extends StatefulWidget {
  const LiveActivitySettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LiveActivitySettingsSheet(),
    );
  }

  @override
  State<LiveActivitySettingsSheet> createState() => _LiveActivitySettingsSheetState();
}

class _LiveActivitySettingsSheetState extends State<LiveActivitySettingsSheet> {
  bool _notificationEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await WidgetSyncService.isLiveNotificationEnabled();
    if (mounted) {
      setState(() {
        _notificationEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleNotification(bool value) async {
    final sched = context.read<ScheduleProvider>();
    if (value) {
      final hasPermission = await WidgetSyncService.hasNotificationPermission();
      if (!hasPermission) {
        final granted = await WidgetSyncService.requestNotificationPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Для показа Live Activity требуется разрешить уведомления в системе',
                ),
              ),
            );
          }
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _notificationEnabled = value);
    await WidgetSyncService.setLiveNotificationEnabled(value, scheduleProvider: sched);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Live Activity уведомление включено'
                : 'Live Activity уведомление выключено',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: theme.colorScheme.primary, size: 26),
              const SizedBox(width: 12),
              Text(
                'Live Activity и виджет',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Activity Switch Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Activity в шторке',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Закрепленное системное уведомление с текущей и следующей парой. Появляется только в учебные дни.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _notificationEnabled,
                        onChanged: _toggleNotification,
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Widget Action
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            tileColor: isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerLow,
            leading: Icon(Icons.widgets_rounded, color: theme.colorScheme.primary),
            title: Text(
              'Добавить виджет на рабочий стол',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              'Живые часы и список пар на экране',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              Navigator.of(context).pop();
              final sched = context.read<ScheduleProvider>();
              await WidgetSyncService.updateScheduleWidget(scheduleProvider: sched);
              final pinned = await WidgetSyncService.pinWidget();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    pinned
                        ? 'Запрос на добавление виджета отправлен'
                        : 'Удерживайте палец на рабочем столе -> Виджеты -> BMSTU neo',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
