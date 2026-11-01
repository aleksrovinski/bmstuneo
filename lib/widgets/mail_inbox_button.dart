import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mail_provider.dart';
import '../screens/mail_screen.dart';

/// Mail icon with the unread count of the inbox; opens the mail screen.
class MailInboxButton extends StatefulWidget {
  const MailInboxButton({super.key});

  @override
  State<MailInboxButton> createState() => _MailInboxButtonState();
}

class _MailInboxButtonState extends State<MailInboxButton> {
  @override
  void initState() {
    super.initState();
    // Signs in with the remembered mail login so the badge is right from the start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MailProvider?>()?.restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Absent in widget tests that build the home screen without mail
    final mail = context.watch<MailProvider?>();
    if (mail == null) return const SizedBox.shrink();
    final unseen = mail.status == MailStatus.ready ? mail.inboxUnseen : 0;
    return IconButton(
      tooltip: unseen > 0 ? 'Почта: $unseen непрочитанных' : 'Почта',
      onPressed: () => MailScreen.open(context),
      icon: Badge(
        isLabelVisible: unseen > 0,
        label: Text(unseen > 99 ? '99+' : '$unseen'),
        child: const Icon(Icons.mail_outline_rounded),
      ),
    );
  }
}
