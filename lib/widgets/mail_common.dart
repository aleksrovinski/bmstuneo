import 'package:flutter/material.dart';
import '../models/mail_folder.dart';

const _shortMonths = ['янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'];
const _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Compact date for the message list: time today, "вчера", "5 окт." or "05.10.24".
String mailListDate(DateTime? date, DateTime now) {
  if (date == null) return '';
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return '${_two(date.hour)}:${_two(date.minute)}';
  if (day == today.subtract(const Duration(days: 1))) return 'вчера';
  if (date.year == now.year) return '${date.day} ${_shortMonths[date.month - 1]}';
  return '${_two(date.day)}.${_two(date.month)}.${date.year % 100}';
}

/// "5 октября 2026, 14:03"
String mailFullDate(DateTime date) =>
    '${date.day} ${_monthsGenitive[date.month - 1]} ${date.year}, ${_two(date.hour)}:${_two(date.minute)}';

String mailFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
}

IconData mailFolderIcon(MailFolderRole role) {
  switch (role) {
    case MailFolderRole.inbox:
      return Icons.inbox_rounded;
    case MailFolderRole.sent:
      return Icons.send_rounded;
    case MailFolderRole.drafts:
      return Icons.edit_note_rounded;
    case MailFolderRole.trash:
      return Icons.delete_outline_rounded;
    case MailFolderRole.junk:
      return Icons.report_outlined;
    case MailFolderRole.other:
      return Icons.folder_outlined;
  }
}

IconData mailFileIcon(String contentType, String fileName) {
  final name = fileName.toLowerCase();
  if (contentType.startsWith('image/')) return Icons.image_outlined;
  if (contentType == 'application/pdf' || name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (name.endsWith('.zip') || name.endsWith('.rar') || name.endsWith('.7z')) return Icons.folder_zip_outlined;
  if (name.endsWith('.xls') || name.endsWith('.xlsx') || name.endsWith('.csv')) return Icons.table_chart_outlined;
  if (contentType.startsWith('message/')) return Icons.mail_outline_rounded;
  return Icons.insert_drive_file_outlined;
}

/// Round avatar with the first letter of the sender; its tint is stable per name.
class MailAvatar extends StatelessWidget {
  final String name;
  final double size;

  const MailAvatar({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final palette = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (background, foreground) = palette[name.hashCode.abs() % palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: foreground),
      ),
    );
  }
}
