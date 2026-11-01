import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/mail_message.dart';
import '../providers/mail_provider.dart';
import '../widgets/mail_common.dart';

/// New letter, reply or forward. Pops with true once the letter is sent.
class MailComposeScreen extends StatefulWidget {
  /// Prefilled fields; reply and forward drafts come from [replyDraft] / [forwardDraft]
  final MailDraft? initial;

  const MailComposeScreen({super.key, this.initial});

  static Future<bool?> open(BuildContext context, {MailDraft? initial}) => Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => MailComposeScreen(initial: initial)),
      );

  /// Answer to the sender ([all]: and to everyone else on the letter but me).
  static MailDraft replyDraft(MailMessage original, {required bool all, String? myEmail}) {
    final target = original.replyTo ?? original.from;
    final me = myEmail?.toLowerCase();
    final seen = <String>{?me, if (target != null) target.email.toLowerCase()};
    final cc = <MailAddress>[];
    if (all) {
      for (final a in [...original.to, ...original.cc]) {
        if (seen.add(a.email.toLowerCase())) cc.add(a);
      }
    }
    final subject = original.subject;
    return MailDraft(
      to: [?target],
      cc: cc,
      subject: RegExp(r'^\s*(re|ответ)\s*:', caseSensitive: false).hasMatch(subject) ? subject : 'Re: $subject',
      body: '\n\n${_quoteHeader(original)}\n${original.text.split('\n').map((l) => '> $l').join('\n')}',
      inReplyTo: original.messageId.isEmpty ? null : original.messageId,
      replyingTo: original,
    );
  }

  /// The letter's text inline; its attachments are copied by the server.
  static MailDraft forwardDraft(MailMessage original) {
    final subject = original.subject;
    final lines = [
      '---------- Пересланное письмо ----------',
      if (original.from != null) 'От: ${original.from}',
      if (original.date != null) 'Дата: ${mailFullDate(original.date!)}',
      'Тема: $subject',
      if (original.to.isNotEmpty) 'Кому: ${original.to.join(', ')}',
      '',
      original.text,
    ];
    return MailDraft(
      to: const [],
      subject: RegExp(r'^\s*(fwd?|пересл)\s*:', caseSensitive: false).hasMatch(subject) ? subject : 'Fwd: $subject',
      body: '\n\n${lines.join('\n')}',
      forwardOf: original,
    );
  }

  static String _quoteHeader(MailMessage m) {
    final who = m.from?.toString() ?? 'отправитель';
    return m.date == null ? '$who пишет:' : '${mailFullDate(m.date!)}, $who пишет:';
  }

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  late final TextEditingController _to;
  late final TextEditingController _cc;
  late final TextEditingController _subject;
  late final TextEditingController _body;
  final FocusNode _bodyFocus = FocusNode();
  late bool _showCc;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _to = TextEditingController(text: d?.to.map((a) => a.toString()).join(', ') ?? '');
    _cc = TextEditingController(text: d?.cc.map((a) => a.toString()).join(', ') ?? '');
    _subject = TextEditingController(text: d?.subject ?? '');
    // The cursor goes above the quoted text
    _body = TextEditingController(text: d?.body ?? '')..selection = const TextSelection.collapsed(offset: 0);
    _showCc = _cc.text.isNotEmpty;
    if (d != null && d.to.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bodyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final d = widget.initial;
    return _to.text.trim() != (d?.to.map((a) => a.toString()).join(', ') ?? '') ||
        _subject.text != (d?.subject ?? '') ||
        _body.text != (d?.body ?? '');
  }

  Future<void> _send() async {
    final to = MailAddress.parseList(_to.text);
    final cc = MailAddress.parseList(_showCc ? _cc.text : '');
    final invalid = [...to.invalid, ...cc.invalid];
    if (to.valid.isEmpty) {
      setState(() => _error = 'Укажите адрес получателя');
      return;
    }
    if (invalid.isNotEmpty) {
      setState(() => _error = 'Не похоже на адрес: ${invalid.join(', ')}');
      return;
    }
    if (_subject.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отправить без темы?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отправить')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    final d = widget.initial;
    try {
      await context.read<MailProvider>().send(MailDraft(
            to: to.valid,
            cc: cc.valid,
            subject: _subject.text.trim(),
            body: _body.text,
            inReplyTo: d?.inReplyTo,
            replyingTo: d?.replyingTo,
            forwardOf: d?.forwardOf,
          ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить черновик?'),
        content: const Text('Письмо не отправлено, текст пропадёт.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Продолжить')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mail = context.watch<MailProvider>();
    final forwarded = widget.initial?.forwardOf?.attachments ?? const <MailAttachment>[];
    final title = widget.initial?.replyingTo != null
        ? 'Ответ'
        : widget.initial?.forwardOf != null
            ? 'Пересылка'
            : 'Новое письмо';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _sending) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    )
                  : IconButton.filled(
                      tooltip: 'Отправить',
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (mail.identity != null)
              _FieldRow(
                label: 'От',
                child: Text(
                  mail.identity!.email,
                  style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            _FieldRow(
              label: 'Кому',
              trailing: _showCc
                  ? null
                  : TextButton(onPressed: () => setState(() => _showCc = true), child: const Text('Копия')),
              child: TextField(
                controller: _to,
                enabled: !_sending,
                autofocus: widget.initial == null || widget.initial!.to.isEmpty,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration.collapsed(hintText: 'адрес@bmstu.ru, ещё@student.bmstu.ru'),
              ),
            ),
            if (_showCc)
              _FieldRow(
                label: 'Копия',
                child: TextField(
                  controller: _cc,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration.collapsed(hintText: 'адреса через запятую'),
                ),
              ),
            _FieldRow(
              label: 'Тема',
              child: TextField(
                controller: _subject,
                enabled: !_sending,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration.collapsed(hintText: 'тема письма'),
              ),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: TextStyle(fontSize: 13, color: theme.colorScheme.onErrorContainer)),
              ),
            if (forwarded.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in forwarded)
                      Chip(
                        avatar: Icon(mailFileIcon(a.contentType, a.fileName), size: 18),
                        label: Text(a.fileName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _body,
                focusNode: _bodyFocus,
                enabled: !_sending,
                minLines: 10,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15, height: 1.45),
                decoration: const InputDecoration.collapsed(hintText: 'Текст письма'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;

  const _FieldRow({required this.label, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: child),
          ?trailing,
        ],
      ),
    );
  }
}
