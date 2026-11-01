import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/mail_folder.dart';
import '../models/mail_message.dart';
import '../services/mail_credentials_storage.dart';
import '../services/mail_service.dart';

/// Student mail stand-in for the demo build: a few made-up letters kept in memory,
/// no network. Sending puts the letter into "Sent Items".
class DemoMailService extends MailService {
  DemoMailService();

  static const _me = MailIdentity(email: 'ias25r631@student.bmstu.ru', realName: 'Иванов Алексей Сергеевич');

  bool _signedIn = false;
  int _nextUid = 200;
  late final Map<String, List<_DemoLetter>> _boxes = _seed();

  Future<T> _reply<T>(T value) => Future.delayed(const Duration(milliseconds: 250), () => value);

  @override
  bool get isSignedIn => _signedIn;

  @override
  MailIdentity? get identity => _signedIn ? _me : null;

  @override
  Future<MailIdentity> login(String userName, String password) {
    _signedIn = true;
    return _reply(_me);
  }

  @override
  Future<void> logout({bool clearDownloads = true}) async => _signedIn = false;

  @override
  Future<List<MailFolder>> fetchFolders() => _reply([
    for (final e in _boxes.entries)
      MailFolder(name: e.key, total: e.value.length, unseen: e.value.where((l) => !l.flags.contains('Seen')).length),
  ]);

  @override
  Future<MailPage> fetchPage(String mailbox, {int from = 0, int count = MailService.pageSize, bool reopen = false}) {
    final letters = [...?_boxes[mailbox]]..sort((a, b) => b.date.compareTo(a.date));
    return _reply(
      MailPage(
        total: letters.length,
        unseen: letters.where((l) => !l.flags.contains('Seen')).length,
        items: letters.skip(from).take(count).map((l) => l.summary).toList(),
      ),
    );
  }

  @override
  Future<MailMessage> readMessage(String mailbox, int uid, {bool markSeen = true}) {
    final letter = _find(mailbox, uid);
    if (markSeen) letter.flags.add('Seen');
    return _reply(letter.message(mailbox));
  }

  @override
  Future<void> setFlag(String mailbox, int uid, String flag, bool on) {
    final flags = _find(mailbox, uid).flags;
    if (on) {
      flags.add(flag);
    } else {
      flags.remove(flag);
    }
    return _reply(null);
  }

  @override
  Future<void> remove(String mailbox, int uid) {
    final letter = _find(mailbox, uid);
    _boxes[mailbox]!.remove(letter);
    if (mailbox != 'Trash') _boxes['Trash']!.add(letter);
    return _reply(null);
  }

  @override
  Future<void> send(MailDraft draft, {String? saveToMailbox}) {
    final replied = draft.replyingTo;
    if (replied != null) _find(replied.mailbox, replied.uid).flags.add('Answered');
    _boxes[saveToMailbox ?? 'Sent Items']?.add(
      _DemoLetter(
        uid: _nextUid++,
        from: const MailAddress(email: 'ias25r631@student.bmstu.ru', name: 'Иванов Алексей Сергеевич'),
        to: draft.to,
        subject: draft.subject,
        date: DateTime.now(),
        text: draft.body,
        flags: {'Seen'},
        attachments: draft.forwardOf?.attachments ?? const [],
      ),
    );
    return _reply(null);
  }

  @override
  Future<File> downloadAttachment(MailMessage message, MailAttachment attachment) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/mail/demo');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${MailService.safeFileName(attachment.fileName)}');
    await file.writeAsBytes(utf8.encode('Демо-вложение «${attachment.fileName}» из BMSTU neo'));
    return file;
  }

  _DemoLetter _find(String mailbox, int uid) => _boxes[mailbox]!.firstWhere((l) => l.uid == uid);

  /// A full mailbox for screenshots: unread and read letters, replies, flags,
  /// attachments and a folder of the student's own. Dates are relative to now.
  static Map<String, List<_DemoLetter>> _seed() {
    final now = DateTime.now();
    DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
        now.subtract(Duration(days: days, hours: hours, minutes: minutes));
    const me = MailAddress(email: 'ias25r631@student.bmstu.ru', name: 'Иванов Алексей Сергеевич');
    const orlov = MailAddress(email: 'orlov.do@bmstu.ru', name: 'Орлов Дмитрий Олегович');
    const sokolova = MailAddress(email: 'sokolova.ma@bmstu.ru', name: 'Соколова Марина Андреевна');
    const belova = MailAddress(email: 'belova.av@bmstu.ru', name: 'Белова Анна Викторовна');
    const lukina = MailAddress(email: 'lukina.kb@bmstu.ru', name: 'Лукина Ксения Борисовна');
    const mironova = MailAddress(email: 'mironova.oi@bmstu.ru', name: 'Миронова Ольга Игоревна');
    const starosta = MailAddress(email: 'pkn25r612@student.bmstu.ru', name: 'Петрова Ксения, староста РК6-31Б');
    const group = MailAddress(email: 'rk6-31b@student.bmstu.ru', name: 'РК6-31Б');
    return {
      'INBOX': [
        _DemoLetter(
          uid: 140,
          from: orlov,
          to: const [me],
          subject: 'Лабораторная работа №4 — сроки защиты',
          date: ago(minutes: 25),
          text:
              'Добрый день!\n\nЗащита лабораторной работы №4 по программированию переносится на '
              'следующую неделю. Отчёты присылайте ответом на это письмо до пятницы.\n\n'
              'Шаблон отчёта во вложении. Проверьте, что программа собирается без предупреждений '
              'с флагами -Wall -Wextra.\n\nС уважением,\nД. О. Орлов',
          attachments: const [
            MailAttachment(
              partId: '02',
              fileName: 'Шаблон отчёта ЛР4.docx',
              contentType: 'application/msword',
              size: 48211,
            ),
          ],
        ),
        _DemoLetter(
          uid: 139,
          from: starosta,
          to: const [group],
          subject: 'Перенос семинара по матанализу на четверг',
          date: ago(hours: 2, minutes: 10),
          text:
              'Всем привет!\n\nМарина Андреевна попросила передать: семинар в пятницу переносится '
              'на четверг, 4-я пара, ауд. 532 ГУК. РК-2 остаётся по плану.\n\nКсения',
        ),
        _DemoLetter(
          uid: 138,
          from: belova,
          to: const [me],
          subject: 'Замечания к чертежу «Корпус»',
          date: ago(hours: 5),
          text:
              'Алексей, добрый день.\n\nПосмотрела ваш чертёж. Замечания:\n'
              '1. На главном виде не хватает размера отверстия Ø12.\n'
              '2. Разрез А–А обозначен не по ГОСТ 2.305.\n'
              '3. Шероховатость указана не на всех поверхностях.\n\n'
              'Исправленный вариант принесите на ближайшее занятие.\n\nА. В. Белова',
          flags: {'Flagged'},
          attachments: const [
            MailAttachment(
              partId: '02',
              fileName: 'Корпус_замечания.pdf',
              contentType: 'application/pdf',
              size: 1240331,
            ),
          ],
        ),
        _DemoLetter(
          uid: 137,
          from: const MailAddress(email: 'dekanat-rk@bmstu.ru', name: 'Деканат РК'),
          to: const [me],
          subject: 'Расписание сессии опубликовано',
          date: ago(days: 1, hours: 3),
          text:
              'Уважаемые студенты!\n\nРасписание зимней экзаменационной сессии опубликовано в '
              'личном кабинете студента. Проверьте даты консультаций и экзаменов своей группы.\n\n'
              'Допуск к сессии — при закрытых рубежных контролях и лабораторных работах.\n\nДеканат',
          flags: {'Seen'},
        ),
        _DemoLetter(
          uid: 136,
          from: lukina,
          to: const [group],
          subject: 'Физпрактикум: график отработок',
          date: ago(days: 1, hours: 7),
          text:
              'Здравствуйте!\n\nОтработки пропущенных лабораторных работ — по средам с 15:40 '
              'в лаборатории каф. ФН4. Запись у лаборанта. При себе иметь подготовленный протокол.\n\n'
              'К. Б. Лукина',
          flags: {'Seen'},
          attachments: const [
            MailAttachment(
              partId: '02',
              fileName: 'График отработок.xlsx',
              contentType: 'application/vnd.ms-excel',
              size: 18744,
            ),
          ],
        ),
        _DemoLetter(
          uid: 135,
          from: sokolova,
          to: const [me],
          subject: 'Рубежный контроль по математическому анализу',
          date: ago(days: 2, hours: 4),
          text:
              'Коллеги, напоминаю: РК-2 пройдёт на следующем семинаре. Темы: ряды, '
              'признаки сходимости, степенные ряды. Список задач для подготовки прилагаю.',
          flags: {'Seen', 'Answered'},
          attachments: const [
            MailAttachment(partId: '02', fileName: 'Задачи к РК-2.pdf', contentType: 'application/pdf', size: 312004),
          ],
        ),
        _DemoLetter(
          uid: 134,
          from: mironova,
          to: const [group],
          subject: 'English: presentation topics',
          date: ago(days: 3, hours: 1),
          text:
              'Dear students,\n\nPlease choose a topic for your presentation by next Monday. '
              'The list is attached. Each talk should take 5–7 minutes.\n\nBest regards,\nO. I. Mironova',
          flags: {'Seen'},
          attachments: const [
            MailAttachment(
              partId: '02',
              fileName: 'Presentation topics.pdf',
              contentType: 'application/pdf',
              size: 96310,
            ),
          ],
        ),
        _DemoLetter(
          uid: 133,
          from: const MailAddress(email: 'profkom@bmstu.ru', name: 'Профком студентов'),
          to: const [me],
          subject: 'Запись на зимний выезд в «Бауманец»',
          date: ago(days: 4),
          text:
              'Открыта запись на зимний выезд в спортивно-оздоровительный лагерь «Бауманец». '
              'Количество мест ограничено, заявки принимаются в профкоме до конца месяца.',
          flags: {'Seen'},
        ),
        _DemoLetter(
          uid: 132,
          from: const MailAddress(email: 'sport@bmstu.ru', name: 'Кафедра физвоспитания'),
          to: const [me],
          subject: 'Зачётные нормативы по физкультуре',
          date: ago(days: 5, hours: 2),
          text:
              'Сдача зачётных нормативов пройдёт на последней неделе семестра. Баллы и посещения '
              'можно посмотреть в разделе ФКиС личного кабинета.',
          flags: {'Seen', 'Flagged'},
        ),
        _DemoLetter(
          uid: 131,
          from: const MailAddress(email: 'library@bmstu.ru', name: 'Научно-техническая библиотека'),
          to: const [me],
          subject: 'Срок возврата книг',
          date: ago(days: 6),
          text:
              'Напоминаем, что срок возврата учебной литературы истекает через неделю. '
              'Продлить книги можно на абонементе.',
          flags: {'Seen'},
        ),
        _DemoLetter(
          uid: 130,
          from: const MailAddress(email: 'it@bmstu.ru', name: 'Управление информатизации'),
          to: const [me],
          subject: 'Доступ к Wi-Fi bmstu_lk',
          date: ago(days: 9),
          text: 'Для подключения к сети bmstu_lk используйте логин и пароль от личного кабинета студента.',
          flags: {'Seen'},
        ),
      ],
      'Курсовая': [
        _DemoLetter(
          uid: 20,
          from: orlov,
          to: const [me],
          subject: 'Тема курсовой работы утверждена',
          date: ago(days: 12),
          text:
              'Алексей, тема «Планировщик расписания на C++» утверждена. Первый этап — '
              'техническое задание — до конца месяца.',
          flags: {'Seen', 'Answered'},
          attachments: const [
            MailAttachment(partId: '02', fileName: 'ТЗ_пример.docx', contentType: 'application/msword', size: 35120),
          ],
        ),
      ],
      'Sent Items': [
        _DemoLetter(
          uid: 41,
          from: me,
          to: const [sokolova],
          subject: 'Re: Рубежный контроль по математическому анализу',
          date: ago(days: 2, hours: 1),
          text:
              'Марина Андреевна, добрый день!\n\nСпасибо, задачи получил. Можно ли прийти на '
              'консультацию перед РК?\n\nИванов А. С., РК6-31Б',
          flags: {'Seen'},
        ),
        _DemoLetter(
          uid: 40,
          from: me,
          to: const [orlov],
          subject: 'Re: Лабораторная работа №3',
          date: ago(days: 9),
          text: 'Дмитрий Олегович, добрый день!\n\nОтчёт по ЛР3 во вложении.\n\nИванов А. С., РК6-31Б',
          flags: {'Seen'},
          attachments: const [
            MailAttachment(partId: '02', fileName: 'Отчёт ЛР3.pdf', contentType: 'application/pdf', size: 402118),
          ],
        ),
      ],
      'Drafts': [],
      'Trash': [],
    };
  }
}

class _DemoLetter {
  final int uid;
  final MailAddress from;
  final List<MailAddress> to;
  final String subject;
  final DateTime date;
  final String text;
  final Set<String> flags;
  final List<MailAttachment> attachments;

  _DemoLetter({
    required this.uid,
    required this.from,
    required this.to,
    required this.subject,
    required this.date,
    required this.text,
    Set<String>? flags,
    this.attachments = const [],
  }) : flags = flags ?? {};

  MailSummary get summary => MailSummary(
    uid: uid,
    from: from.display,
    to: to.isEmpty ? '' : to.first.display,
    subject: subject,
    date: date,
    flags: Set.of(flags),
    size: text.length,
    hasAttachments: attachments.isNotEmpty,
  );

  MailMessage message(String mailbox) => MailMessage(
    mailbox: mailbox,
    uid: uid,
    subject: subject,
    from: from,
    to: to,
    date: date,
    messageId: 'demo-$uid@bmstu.ru',
    text: text,
    attachments: attachments,
  );
}

/// The demo mail account signs in by itself and never touches the real Keychain entries.
class DemoMailCredentialsStorage extends MailCredentialsStorage {
  bool _cleared = false;

  @override
  Future<bool> save(String username, String password) async {
    _cleared = false;
    return true;
  }

  @override
  Future<({String? username, String? password})> read() async =>
      _cleared ? (username: null, password: null) : (username: 'demo', password: 'demo');

  @override
  Future<void> forgetPassword() async {}

  @override
  Future<void> clear() async => _cleared = true;
}
