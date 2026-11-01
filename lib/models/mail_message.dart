/// One mail address with its optional display name.
class MailAddress {
  final String email;
  final String name;

  const MailAddress({required this.email, this.name = ''});

  /// The name when the sender has one, otherwise the bare address.
  String get display => name.isNotEmpty ? name : email;

  @override
  String toString() => name.isNotEmpty ? '$name <$email>' : email;

  static final _emailPattern = RegExp(r'^[^\s@<>",;]+@[^\s@<>",;]+\.[^\s@<>",;]+$');

  /// `ivanov@bmstu.ru`, `Иванов И. <ivanov@bmstu.ru>` or `<ivanov@bmstu.ru>`;
  /// null when there is no valid address in [raw].
  static MailAddress? tryParse(String raw) {
    final text = raw.trim();
    final angle = RegExp(r'^(.*)<([^<>]+)>\s*$').firstMatch(text);
    final email = (angle?.group(2) ?? text).trim();
    if (!_emailPattern.hasMatch(email)) return null;
    var name = (angle?.group(1) ?? '').trim();
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1).trim();
    }
    return MailAddress(email: email, name: name);
  }

  /// Splits a recipients field on commas and semicolons (not inside quoted names).
  /// Returns the parsed addresses and the pieces that are not addresses.
  static ({List<MailAddress> valid, List<String> invalid}) parseList(String input) {
    final pieces = <String>[];
    final current = StringBuffer();
    var quoted = false;
    var angled = false;
    for (final ch in input.split('')) {
      if (ch == '"') quoted = !quoted;
      if (ch == '<') angled = true;
      if (ch == '>') angled = false;
      if ((ch == ',' || ch == ';') && !quoted && !angled) {
        pieces.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    pieces.add(current.toString());

    final valid = <MailAddress>[];
    final invalid = <String>[];
    for (final piece in pieces.map((p) => p.trim()).where((p) => p.isNotEmpty)) {
      final address = tryParse(piece);
      if (address != null) {
        valid.add(address);
      } else {
        invalid.add(piece);
      }
    }
    return (valid: valid, invalid: invalid);
  }
}

/// A message as shown in the folder list: viewer fields only, no body.
class MailSummary {
  final int uid;
  /// Display name (or address) of the sender
  final String from;
  /// Display name (or address) of the first recipient; shown in "Sent"
  final String to;
  final String subject;
  final DateTime? date;
  final Set<String> flags;
  final int size;
  final bool hasAttachments;

  const MailSummary({
    required this.uid,
    this.from = '',
    this.to = '',
    this.subject = '',
    this.date,
    this.flags = const {},
    this.size = 0,
    this.hasAttachments = false,
  });

  bool get isSeen => flags.contains('Seen');
  bool get isAnswered => flags.contains('Answered');
  bool get isFlagged => flags.contains('Flagged');

  MailSummary copyWith({Set<String>? flags}) => MailSummary(
        uid: uid,
        from: from,
        to: to,
        subject: subject,
        date: date,
        flags: flags ?? this.flags,
        size: size,
        hasAttachments: hasAttachments,
      );

  MailSummary withFlag(String flag, bool on) =>
      copyWith(flags: on ? ({...flags, flag}) : (Set.of(flags)..remove(flag)));
}

/// A file attached to a message; downloaded on demand by its MIME part ID.
class MailAttachment {
  /// Empty when the whole message body is the file
  final String partId;
  final String fileName;
  /// "image/png", "application/pdf"...
  final String contentType;
  final int size;

  const MailAttachment({
    required this.partId,
    required this.fileName,
    this.contentType = 'application/octet-stream',
    this.size = 0,
  });

  /// File extension for the download URL: from the name, else from the subtype.
  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toLowerCase();
    }
    final slash = contentType.indexOf('/');
    final subtype = slash >= 0 ? contentType.substring(slash + 1) : '';
    return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(subtype) ? subtype : 'bin';
  }

  bool get isImage => contentType.startsWith('image/');
}

/// A fully read message: headers, readable text and the list of attachments.
class MailMessage {
  final String mailbox;
  final int uid;
  final String subject;
  final MailAddress? from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final MailAddress? replyTo;
  final DateTime? date;
  final String messageId;
  /// Plain text of the message; HTML-only letters are converted to text
  final String text;
  final List<MailAttachment> attachments;

  const MailMessage({
    required this.mailbox,
    required this.uid,
    this.subject = '',
    this.from,
    this.to = const [],
    this.cc = const [],
    this.replyTo,
    this.date,
    this.messageId = '',
    this.text = '',
    this.attachments = const [],
  });
}

/// A letter the student is about to send.
class MailDraft {
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final String subject;
  final String body;
  /// Message-ID of the letter being answered (threads the reply in mail apps)
  final String? inReplyTo;
  /// The answered letter, marked "Answered" once the reply is sent
  final MailMessage? replyingTo;
  /// Attachments of [forwardOf] are copied server-side into the forwarded letter
  final MailMessage? forwardOf;

  const MailDraft({
    required this.to,
    this.cc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
    this.replyingTo,
    this.forwardOf,
  });
}

/// One page of a folder listing, newest first.
class MailPage {
  /// Messages in the folder; null when the page was read without reopening the folder
  final int? total;
  final int? unseen;
  final List<MailSummary> items;

  const MailPage({this.total, this.unseen, this.items = const []});
}
