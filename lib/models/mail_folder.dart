/// What a mailbox is for; standard mailboxes get Russian titles and their own icons.
enum MailFolderRole { inbox, sent, drafts, trash, junk, other }

/// A mailbox of the student's mail on student.bmstu.ru with its message counters.
class MailFolder {
  /// The server-side Mailbox name ("INBOX", "Sent Items", "INBOX/Курсовая").
  final String name;
  final int total;
  final int unseen;

  const MailFolder({required this.name, this.total = 0, this.unseen = 0});

  MailFolderRole get role => roleOf(name);

  static MailFolderRole roleOf(String name) {
    switch (name.trim().toLowerCase()) {
      case 'inbox':
      case 'входящие':
        return MailFolderRole.inbox;
      case 'sent items':
      case 'sent':
      case 'sent messages':
      case 'отправленные':
        return MailFolderRole.sent;
      case 'drafts':
      case 'черновики':
        return MailFolderRole.drafts;
      case 'trash':
      case 'deleted items':
      case 'deleted messages':
      case 'корзина':
        return MailFolderRole.trash;
      case 'junk':
      case 'junk e-mail':
      case 'spam':
      case 'спам':
        return MailFolderRole.junk;
      default:
        return MailFolderRole.other;
    }
  }

  String get title {
    switch (role) {
      case MailFolderRole.inbox:
        return 'Входящие';
      case MailFolderRole.sent:
        return 'Отправленные';
      case MailFolderRole.drafts:
        return 'Черновики';
      case MailFolderRole.trash:
        return 'Корзина';
      case MailFolderRole.junk:
        return 'Спам';
      case MailFolderRole.other:
        return name.replaceAll('/', ' / ');
    }
  }

  MailFolder copyWith({int? total, int? unseen}) =>
      MailFolder(name: name, total: total ?? this.total, unseen: unseen ?? this.unseen);
}
