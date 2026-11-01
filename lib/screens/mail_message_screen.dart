import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/mail_folder.dart';
import '../models/mail_message.dart';
import '../providers/mail_provider.dart';
import '../widgets/mail_common.dart';
import 'mail_compose_screen.dart';

/// One letter: headers, text, attachments; reply, forward, delete.
class MailMessageScreen extends StatefulWidget {
  final String mailbox;
  final MailSummary summary;

  const MailMessageScreen({super.key, required this.mailbox, required this.summary});

  static Future<void> open(BuildContext context, {required String mailbox, required MailSummary summary}) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailMessageScreen(mailbox: mailbox, summary: summary)),
      );

  @override
  State<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends State<MailMessageScreen> {
  MailMessage? _message;
  String? _error;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final message = await context.read<MailProvider>().readMessage(widget.mailbox, widget.summary);
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  Future<void> _compose(MailDraft draft) async {
    final sent = await MailComposeScreen.open(context, initial: draft);
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Письмо отправлено')));
    }
  }

  void _reply({required bool all}) {
    final message = _message;
    if (message == null) return;
    final me = context.read<MailProvider>().identity?.email;
    _compose(MailComposeScreen.replyDraft(message, all: all, myEmail: me));
  }

  void _forward() {
    final message = _message;
    if (message != null) _compose(MailComposeScreen.forwardDraft(message));
  }

  Future<void> _delete() async {
    final mail = context.read<MailProvider>();
    final inTrash = MailFolder.roleOf(widget.mailbox) == MailFolderRole.trash;
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
      if (ok != true) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await mail.delete(widget.mailbox, widget.summary.uid);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(inTrash ? 'Письмо удалено' : 'Письмо перемещено в корзину')));
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _markUnread() async {
    final navigator = Navigator.of(context);
    try {
      await context.read<MailProvider>().setSeen(widget.summary.withFlag('Seen', true), false);
      navigator.pop();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _openAttachment(MailAttachment attachment, BuildContext tileContext) async {
    final message = _message;
    if (message == null || _downloading.contains(attachment.partId)) return;
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _downloading.add(attachment.partId));
    try {
      final file = await context.read<MailProvider>().downloadAttachment(message, attachment);
      // The system sheet opens the file in a viewer, saves it to Files or sends it on
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: attachment.contentType, name: attachment.fileName)],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _downloading.remove(attachment.partId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            enabled: message != null,
            onSelected: (value) {
              if (value == 'replyAll') _reply(all: true);
              if (value == 'forward') _forward();
              if (value == 'unread') _markUnread();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'replyAll', child: Text('Ответить всем')),
              PopupMenuItem(value: 'forward', child: Text('Переслать')),
              PopupMenuItem(value: 'unread', child: Text('Отметить непрочитанным')),
            ],
          ),
        ],
      ),
      body: message != null
          ? _buildMessage(message)
          : _error != null
              ? _buildError(_error!)
              : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: message == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _reply(all: false),
                        icon: const Icon(Icons.reply_rounded),
                        label: const Text('Ответить'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _forward,
                        icon: const Icon(Icons.forward_rounded),
                        label: const Text('Переслать'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildError(String error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(MailMessage message) {
    final theme = Theme.of(context);
    final muted = TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant);
    final from = message.from;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SelectableText(
          message.subject.isEmpty ? '(без темы)' : message.subject,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.25, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MailAvatar(name: from?.display ?? '?', size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    from?.display ?? 'Без отправителя',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                  ),
                  if (from != null && from.name.isNotEmpty) SelectableText(from.email, style: muted),
                  if (message.date != null) ...[
                    const SizedBox(height: 2),
                    Text(mailFullDate(message.date!), style: muted),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (message.to.isNotEmpty) _Recipients(label: 'Кому', addresses: message.to),
        if (message.cc.isNotEmpty) _Recipients(label: 'Копия', addresses: message.cc),
        if (message.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final a in message.attachments)
            Builder(
              builder: (tileContext) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Icon(mailFileIcon(a.contentType, a.fileName), color: theme.colorScheme.primary),
                  title: Text(
                    a.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: a.size > 0 ? Text(mailFileSize(a.size)) : null,
                  trailing: _downloading.contains(a.partId)
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.ios_share_rounded),
                  onTap: () => _openAttachment(a, tileContext),
                ),
              ),
            ),
        ],
        Divider(height: 28, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        if (message.text.isEmpty)
          Text('Письмо без текста', style: muted.copyWith(fontStyle: FontStyle.italic))
        else
          SelectableText(
            message.text,
            style: TextStyle(fontSize: 15, height: 1.45, color: theme.colorScheme.onSurface),
          ),
      ],
    );
  }
}

class _Recipients extends StatelessWidget {
  final String label;
  final List<MailAddress> addresses;

  const _Recipients({required this.label, required this.addresses});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText.rich(
        TextSpan(
          style: TextStyle(fontSize: 13, height: 1.35, color: theme.colorScheme.onSurfaceVariant),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: addresses.join(', ')),
          ],
        ),
      ),
    );
  }
}
