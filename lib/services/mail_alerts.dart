import '../models/mail_message.dart';

/// Letters to notify about after a background look at the newest inbox letters:
/// unread ones that arrived after the last check (mailbox UIDs only grow).
///
/// [lastUid] is null on the very first check: then nothing is reported and only the
/// newest UID is remembered, so turning notifications on doesn't announce the whole
/// unread backlog. Returns the letters and the UID to remember for the next check.
({List<MailSummary> fresh, int? lastUid}) newMailSince(List<MailSummary> inbox, int? lastUid) {
  var newest = lastUid;
  for (final m in inbox) {
    if (newest == null || m.uid > newest) newest = m.uid;
  }
  if (lastUid == null) return (fresh: const [], lastUid: newest);
  return (
    fresh: inbox.where((m) => m.uid > lastUid && !m.isSeen).toList(),
    lastUid: newest,
  );
}

/// "1 новое письмо", "3 новых письма", "12 новых писем".
String newLettersCount(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n новое письмо';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n новых письма';
  return '$n новых писем';
}
