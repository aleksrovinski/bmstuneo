import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/app_update.dart';

/// Offers a newer APK, downloads it with progress and hands it to the system installer.
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final AppUpdater updater;

  const AppUpdateDialog({super.key, required this.info, required this.updater});

  /// Asks the website (throttled) and shows the dialog if there is something new.
  static Future<void> maybeShow(BuildContext context, {AppUpdater? updater}) async {
    if (!AppUpdater.isSupported) return;
    final u = updater ?? AppUpdater();
    final info = await u.check();
    if (info == null || !context.mounted) return;
    await show(context, info, u);
  }

  /// Manual check from settings: always asks and reports "up to date".
  static Future<void> checkNow(BuildContext context, {AppUpdater? updater}) async {
    final u = updater ?? AppUpdater();
    final info = await u.check(force: true);
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Установлена последняя версия')),
      );
      return;
    }
    await show(context, info, u);
  }

  static Future<void> show(BuildContext context, AppUpdateInfo info, AppUpdater updater) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AppUpdateDialog(info: info, updater: updater),
      );

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final _cancel = CancelToken();
  bool _downloading = false;
  double? _progress;
  String? _path;
  String? _message;

  @override
  void dispose() {
    if (_downloading) _cancel.cancel();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _message = null;
    });
    try {
      _path ??= await widget.updater.download(
        widget.info,
        cancel: _cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _message = 'Не удалось скачать обновление. Проверьте интернет и попробуйте ещё раз.';
      });
      return;
    }
    if (!mounted) return;
    final outcome = await widget.updater.install(_path!, widget.info);
    if (!mounted) return;
    if (outcome == InstallOutcome.started) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _downloading = false;
      switch (outcome) {
        case InstallOutcome.started:
          break;
        case InstallOutcome.needsPermission:
          _message = 'Разрешите BMSTU neo устанавливать приложения в открывшихся настройках, '
              'вернитесь и нажмите «Установить».';
        case InstallOutcome.corrupted:
          _path = null; // download again next time
          _message = 'Файл скачался с ошибкой. Попробуйте ещё раз.';
        case InstallOutcome.failed:
          _message = 'Не удалось открыть установщик. Скачайте APK с сайта bmstuneo.xyz.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final sizeMb = info.size > 0 ? ' · ${(info.size / 1000000).round()} МБ' : '';
    return AlertDialog(
      title: Text('Доступна версия ${info.versionName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.notes.isNotEmpty) ...[
              Text(info.notes, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            Text('Обновление скачается с bmstuneo.xyz$sizeMb. Данные и вход сохранятся.',
                style: theme.textTheme.bodySmall),
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () {
              widget.updater.skip(info);
              Navigator.of(context).pop();
            },
            child: const Text('Пропустить'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_downloading ? 'Отмена' : 'Позже'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _update,
          child: Text(_path != null ? 'Установить' : 'Обновить'),
        ),
      ],
    );
  }
}
