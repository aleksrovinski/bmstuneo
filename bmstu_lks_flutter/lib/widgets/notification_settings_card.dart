import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/background_sync.dart';

/// Settings switch for background progress notifications (scores, new work, deadlines).
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key});

  @override
  State<NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BackgroundSync.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final ok = await BackgroundSync.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = ok ? value : false;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Уведомления запрещены в настройках телефона. Разрешите их для BMSTU neo и попробуйте снова.'),
      ));
      return;
    }
    // First pass right away: remembers the current state and reports this week's deadlines
    if (value) BackgroundSync.run();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isFullAuth) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SwitchListTile(
        value: _enabled ?? false,
        onChanged: (_enabled == null || _busy) ? null : _toggle,
        secondary: Icon(Icons.notifications_active_rounded, color: theme.colorScheme.primary),
        title: const Text('Уведомления об успеваемости', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text(
          'Новые баллы за модули, выданные задания и сроки на этой неделе. '
          'Приложение проверяет ЛКС в фоне; данные не покидают телефон.',
        ),
        isThreeLine: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
