import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_mode.dart';
import '../providers/auth_provider.dart';
import '../providers/mail_provider.dart';
import '../services/background_sync.dart';

/// Settings switches for background notifications: progress (scores, new work,
/// deadlines) for a signed-in student, new mail once the mail is signed in.
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key});

  @override
  State<NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> {
  bool? _enabled;
  bool? _mailEnabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BackgroundSync.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
    BackgroundSync.isMailEnabled().then((value) {
      if (mounted) setState(() => _mailEnabled = value);
    });
  }

  Future<void> _toggle(bool value, {required bool mail}) async {
    setState(() => _busy = true);
    final ok = mail ? await BackgroundSync.setMailEnabled(value) : await BackgroundSync.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (mail) {
        _mailEnabled = ok ? value : false;
      } else {
        _enabled = ok ? value : false;
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Уведомления запрещены в настройках телефона. Разрешите их для BMSTU neo и попробуйте снова.'),
        ),
      );
      return;
    }
    // First pass right away: remembers the current state (and reports this week's deadlines)
    if (value) BackgroundSync.run();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Absent in widget tests that build settings without mail
    final mail = context.watch<MailProvider?>();
    // The demo has no real LKS session or mailbox to check in the background
    if (AppMode.isDemo) return const SizedBox.shrink();
    final showProgress = auth.isFullAuth;
    final showMail = mail?.status == MailStatus.ready || (_mailEnabled ?? false);
    if (!showProgress && !showMail) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // Material, not a coloured Container: the switches' ink splashes paint on it
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (showProgress)
              SwitchListTile(
                value: _enabled ?? false,
                onChanged: (_enabled == null || _busy) ? null : (v) => _toggle(v, mail: false),
                secondary: Icon(Icons.notifications_active_rounded, color: theme.colorScheme.primary),
                title: const Text('Уведомления об успеваемости', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'Новые баллы за модули, выданные задания и сроки на этой неделе. '
                  'Приложение проверяет ЛКС в фоне; данные не покидают телефон.',
                ),
                isThreeLine: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            if (showProgress && showMail)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            if (showMail)
              SwitchListTile(
                value: _mailEnabled ?? false,
                onChanged: (_mailEnabled == null || _busy) ? null : (v) => _toggle(v, mail: true),
                secondary: Icon(Icons.mark_email_unread_rounded, color: theme.colorScheme.primary),
                title: const Text('Новые письма', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'Отправитель и тема новых писем в ящике @student.bmstu.ru. '
                  'Приложение проверяет почту в фоне примерно раз в час.',
                ),
                isThreeLine: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
          ],
        ),
      ),
    );
  }
}
