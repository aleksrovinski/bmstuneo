import 'dart:convert';

enum NotificationKind { progress, mail }

/// Where tapping a notification leads; travels as the notification payload.
class NotificationTarget {
  final NotificationKind kind;

  /// Progress: the discipline to show; empty for a summary
  final String discipline;

  /// Mail: the letter to open; null for a summary of several letters
  final String mailbox;
  final int? uid;
  final String from;
  final String subject;

  const NotificationTarget._({
    required this.kind,
    this.discipline = '',
    this.mailbox = 'INBOX',
    this.uid,
    this.from = '',
    this.subject = '',
  });

  const NotificationTarget.progress({String discipline = ''})
    : this._(kind: NotificationKind.progress, discipline: discipline);

  const NotificationTarget.mail({String mailbox = 'INBOX', int? uid, String from = '', String subject = ''})
    : this._(kind: NotificationKind.mail, mailbox: mailbox, uid: uid, from: from, subject: subject);

  String encode() => jsonEncode({
    'kind': kind.name,
    if (discipline.isNotEmpty) 'discipline': discipline,
    if (kind == NotificationKind.mail) 'mailbox': mailbox,
    if (uid != null) 'uid': uid,
    if (from.isNotEmpty) 'from': from,
    if (subject.isNotEmpty) 'subject': subject,
  });

  /// Null for a missing or unknown payload: the app then just opens as usual.
  static NotificationTarget? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map<String, dynamic>) return null;
      String text(String key) => json[key] is String ? json[key] as String : '';
      switch (json['kind']) {
        case 'progress':
          return NotificationTarget.progress(discipline: text('discipline'));
        case 'mail':
          return NotificationTarget.mail(
            mailbox: text('mailbox').isEmpty ? 'INBOX' : text('mailbox'),
            uid: json['uid'] is int ? json['uid'] as int : null,
            from: text('from'),
            subject: text('subject'),
          );
      }
    } catch (_) {}
    return null;
  }
}
