import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/mail_folder.dart';
import '../models/mail_message.dart';
import '../providers/mail_provider.dart';
import '../widgets/mail_common.dart';
import '../widgets/mail_login_form.dart';
import 'mail_compose_screen.dart';
import 'mail_message_screen.dart';

/// Student mail: folder picker in the title, newest letters first, pull to refresh.
class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MailScreen()));

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final mail = context.read<MailProvider>();
      await mail.restore();
      await mail.ensureListLoaded();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      context.read<MailProvider>().loadMore();
    }
  }

  Future<void> _compose() async {
    final sent = await MailComposeScreen.open(context);
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Письмо отправлено')));
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из почты?'),
        content: const Text('Логин и пароль от почты будут удалены с этого устройства. Вход в ЛКС сохранится.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<MailProvider>().signOut();
  }

  void _showFolders() {
    final mail = context.read<MailProvider>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (mail.identity != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    mail.identity!.email,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final folder in mail.folders)
                ListTile(
                  leading: Icon(mailFolderIcon(folder.role)),
                  title: Text(folder.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  selected: folder.name == mail.mailbox,
                  trailing: folder.unseen > 0
                      ? Text(
                          '${folder.unseen}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    mail.openFolder(folder.name);
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mail = context.watch<MailProvider>();
    final ready = mail.status == MailStatus.ready;
    final folder = mail.currentFolder;

    // Signed in from the form: load the inbox right away
    if (ready && !mail.listLoaded && !mail.isLoadingList && mail.listError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<MailProvider>().ensureListLoaded();
      });
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: ready ? 4 : null,
        title: ready
            ? InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showFolders,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Почта',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              folder.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down_rounded, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : const Text('Почта'),
        actions: [
          if (ready)
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              onSelected: (value) {
                if (value == 'folders') _showFolders();
                if (value == 'refresh') mail.refresh();
                if (value == 'signout') _confirmSignOut();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'folders', child: Text('Папки')),
                PopupMenuItem(value: 'refresh', child: Text('Обновить')),
                PopupMenuItem(value: 'signout', child: Text('Выйти из почты')),
              ],
            ),
        ],
      ),
      floatingActionButton: ready
          ? FloatingActionButton.extended(
              onPressed: _compose,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Написать', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: switch (mail.status) {
        _ when !mail.restored => const Center(child: CircularProgressIndicator()),
        MailStatus.signingIn when mail.signingInSaved => const Center(child: CircularProgressIndicator()),
        MailStatus.signedOut || MailStatus.signingIn => const MailLoginForm(),
        MailStatus.unavailable => _MailUnavailable(
            message: mail.loginError ?? 'Почта недоступна',
            onRetry: mail.retry,
          ),
        MailStatus.ready => _buildList(mail),
      },
    );
  }

  Widget _buildList(MailProvider mail) {
    final theme = Theme.of(context);
    final messages = mail.messages;
    final folder = mail.currentFolder;
    final inSent = folder.role == MailFolderRole.sent || folder.role == MailFolderRole.drafts;

    if (!mail.listLoaded && messages.isEmpty) {
      if (mail.listError != null) {
        return _MailUnavailable(message: mail.listError!, onRetry: mail.refresh);
      }
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: mail.refresh,
      child: messages.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Icon(mailFolderIcon(folder.role), size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'В папке «${folder.title}» нет писем',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: messages.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return mail.listError == null ? const SizedBox.shrink() : _ErrorStrip(message: mail.listError!);
                }
                if (index == messages.length + 1) {
                  if (mail.isLoadingMore) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
                    );
                  }
                  return const SizedBox(height: 8);
                }
                final summary = messages[index - 1];
                return _MailTile(
                  key: ValueKey('${mail.mailbox}/${summary.uid}'),
                  summary: summary,
                  showRecipient: inSent,
                  inTrash: folder.role == MailFolderRole.trash,
                  onTap: () => MailMessageScreen.open(context, mailbox: mail.mailbox, summary: summary),
                );
              },
            ),
    );
  }
}

class _MailTile extends StatelessWidget {
  final MailSummary summary;
  final bool showRecipient;
  final bool inTrash;
  final VoidCallback onTap;

  const _MailTile({
    super.key,
    required this.summary,
    required this.showRecipient,
    required this.inTrash,
    required this.onTap,
  });

  Future<bool> _onSwipe(BuildContext context, DismissDirection direction) async {
    final mail = context.read<MailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    HapticFeedback.selectionClick();
    try {
      if (direction == DismissDirection.startToEnd) {
        await mail.setSeen(summary, !summary.isSeen);
        return false;
      }
      if (inTrash) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить навсегда?'),
            content: const Text('Письмо будет удалено из корзины без возможности восстановления.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
            ],
          ),
        );
        if (ok != true) return false;
      }
      await mail.delete(mail.mailbox, summary.uid);
      messenger.showSnackBar(SnackBar(content: Text(inTrash ? 'Письмо удалено' : 'Письмо перемещено в корзину')));
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: errorColor));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !summary.isSeen;
    final who = showRecipient ? (summary.to.isEmpty ? 'Без получателя' : 'Кому: ${summary.to}') : summary.from;
    final weight = unread ? FontWeight.w800 : FontWeight.w500;

    return Dismissible(
      key: ValueKey('dismiss-${summary.uid}'),
      confirmDismiss: (direction) => _onSwipe(context, direction),
      background: _SwipeBackground(
        color: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
        icon: unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
        label: unread ? 'Прочитано' : 'Не прочитано',
        alignStart: true,
      ),
      secondaryBackground: _SwipeBackground(
        color: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
        icon: Icons.delete_outline_rounded,
        label: 'Удалить',
        alignStart: false,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MailAvatar(name: showRecipient ? summary.to : summary.from),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            who.isEmpty ? 'Без отправителя' : who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: weight, color: theme.colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mailListDate(summary.date, DateTime.now()),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                            color: unread ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (summary.isAnswered) ...[
                          Icon(Icons.reply_rounded, size: 15, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            summary.subject.isEmpty ? '(без темы)' : summary.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                              color: unread ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (summary.hasAttachments) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.attach_file_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        ],
                        if (summary.isFlagged) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.flag_rounded, size: 16, color: theme.colorScheme.error),
                        ],
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final bool alignStart;

  const _SwipeBackground({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.alignStart,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: foreground),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignStart ? children : children.reversed.toList(),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  final String message;
  const _ErrorStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: scheme.onErrorContainer))),
        ],
      ),
    );
  }
}

class _MailUnavailable extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _MailUnavailable({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
