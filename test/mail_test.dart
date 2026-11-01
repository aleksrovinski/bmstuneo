import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:bmstu_neo/demo/demo_api_service.dart';
import 'package:bmstu_neo/demo/demo_mail_service.dart';
import 'package:bmstu_neo/models/mail_folder.dart';
import 'package:bmstu_neo/models/mail_message.dart';
import 'package:bmstu_neo/providers/auth_provider.dart';
import 'package:bmstu_neo/providers/mail_provider.dart';
import 'package:bmstu_neo/services/background_sync.dart';
import 'package:bmstu_neo/services/bmstu_api_service.dart';
import 'package:bmstu_neo/services/mail_alerts.dart';
import 'package:bmstu_neo/services/mail_credentials_storage.dart';
import 'package:bmstu_neo/services/mail_service.dart';
import 'package:bmstu_neo/widgets/notification_settings_card.dart';

class FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _xml(String body, [int status = 200]) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/xml; charset=utf-8'],
      },
    );

const _letter = '''
<EMail>
  <From realName="Орлов Дмитрий Олегович">orlov.do@bmstu.ru</From>
  <To realName="Несененко Александр Алексеевич">naa25r209@student.bmstu.ru</To>
  <Cc>group@bmstu.ru</Cc>
  <Subject>Лабораторная работа №4</Subject>
  <Date localTime="20261030T120000" timeShift="10800">20261030T090000Z</Date>
  <Message-ID>&lt;lab4-123@bmstu.ru&gt;</Message-ID>
  <MIME type="multipart" subtype="mixed" partID="">
    <MIME type="multipart" subtype="alternative" partID="01">
      <MIME type="text" subtype="plain" charset="utf-8" partID="01-01">Добрый день!&#x0A;Шаблон во вложении.</MIME>
      <MIME type="text" subtype="html" charset="utf-8" partID="01-02">&lt;p&gt;Добрый день!&lt;/p&gt;</MIME>
    </MIME>
    <MIME type="application" subtype="pdf" disposition="attachment" Disposition-filename="Шаблон ЛР4.pdf" estimatedSize="48211" partID="02"/>
  </MIME>
</EMail>''';

/// A tiny CommuniGate Pro stand-in: XIMSSLogin plus the sync requests the app sends.
class _FakeCgp {
  final requests = <RequestOptions>[];
  int logins = 0;
  String session = '';
  bool dropSession = false;

  List<XmlElement> syncRequests() => [
        for (final o in requests.where((o) => o.uri.path.endsWith('/sync')))
          ...XmlDocument.parse(o.data as String).rootElement.childElements,
      ];

  ResponseBody handle(RequestOptions o) {
    requests.add(o);
    final path = o.uri.path;
    if (path == '/XIMSSLogin/') {
      final form = o.data as Map;
      if (form['password'] != 'secret') {
        return _xml('<XIMSS><response errorText="incorrect password or account name"/></XIMSS>');
      }
      logins++;
      session = '1-sess$logins';
      return _xml('<XIMSS><session urlID="$session" userName="naa25r209@student.bmstu.ru" '
          'realName="Несененко Александр Алексеевич" version="6.5.6"/></XIMSS>');
    }
    if (dropSession || !path.startsWith('/Session/$session/')) {
      dropSession = false;
      return ResponseBody.fromString('', 550);
    }

    final out = StringBuffer('<XIMSS>');
    // Asynchronous notifications carry no id and must be ignored
    out.write('<folderReport folder="INBOX" mode="notify"/>');
    for (final req in XmlDocument.parse(o.data as String).rootElement.childElements) {
      final id = req.getAttribute('id');
      switch (req.localName) {
        case 'mailboxList':
          out.write('<mailbox id="$id" mailbox="Contacts" Class="IPF.Contact" pureFolder="yes"/>'
              '<mailbox id="$id" mailbox="Trash" MESSAGES="0" UNSEEN="0"/>'
              '<mailbox id="$id" mailbox="Sent Items" Messages="7" Unseen="0"/>'
              '<mailbox id="$id" mailbox="INBOX" MESSAGES="172" UNSEEN="35" UIDNEXT="236"/>');
        case 'folderOpen' || 'folderReopen':
          out.write('<folderReport id="$id" folder="INBOX" mode="init" messages="2" unseen="1"/>');
        case 'folderBrowse':
          out.write('<folderReport id="$id" folder="INBOX" index="0" UID="235">'
              '<FLAGS>Recent</FLAGS><From>Орлов Дмитрий Олегович</From><Subject>Лабораторная работа №4</Subject>'
              '<INTERNALDATE localTime="20261030T120000">20261030T090000Z</INTERNALDATE><SIZE>51234</SIZE>'
              '<Content-Type>multipart/mixed; boundary="x"</Content-Type></folderReport>'
              '<folderReport id="$id" folder="INBOX" index="1" UID="230">'
              '<FLAGS>Seen,Answered</FLAGS><From>Деканат</From><Subject>Сессия</Subject>'
              '<INTERNALDATE>20261028T070000Z</INTERNALDATE><SIZE>2048</SIZE></folderReport>');
        case 'folderRead':
          out.write('<folderMessage id="$id" folder="INBOX" UID="${req.getAttribute('UID')}">$_letter</folderMessage>');
      }
      out.write('<response id="$id"/>');
    }
    out.write('</XIMSS>');
    return _xml(out.toString());
  }
}

MailService _service(_FakeCgp server) => MailService()..httpClientAdapter = FakeAdapter(server.handle);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MailService over XIMSS', () {
    test('signs in, lists folders, pages the inbox and reads a letter', () async {
      final server = _FakeCgp();
      final mail = _service(server);

      final me = await mail.login(' naa25r209 ', 'secret');
      expect(me.email, 'naa25r209@student.bmstu.ru');
      expect(me.realName, 'Несененко Александр Алексеевич');
      final form = server.requests.first.data as Map;
      expect(form['userName'], 'naa25r209');
      expect(form['errorAsXML'], '1');

      final folders = await mail.fetchFolders();
      expect(folders.map((f) => f.name), ['INBOX', 'Sent Items', 'Trash'], reason: 'contacts skipped, inbox first');
      expect(folders.first.unseen, 35);
      expect(folders[1].total, 7, reason: 'attribute case differs between servers');

      final page = await mail.fetchPage('INBOX', reopen: true);
      expect(page.total, 2);
      expect(page.unseen, 1);
      expect(page.items.map((m) => m.uid), [235, 230]);
      expect(page.items.first.isSeen, isFalse);
      expect(page.items.first.hasAttachments, isTrue);
      expect(page.items.first.date, DateTime.utc(2026, 10, 30, 9).toLocal());
      expect(page.items.last.isAnswered, isTrue);

      final browse = server.syncRequests().firstWhere((e) => e.localName == 'folderBrowse');
      final index = browse.getElement('index')!;
      expect(index.getAttribute('from'), '0');
      expect(index.getAttribute('till'), '${MailService.pageSize - 1}');

      final letter = await mail.readMessage('INBOX', 235);
      expect(letter.subject, 'Лабораторная работа №4');
      expect(letter.from!.email, 'orlov.do@bmstu.ru');
      expect(letter.cc.single.email, 'group@bmstu.ru');
      expect(letter.messageId, 'lab4-123@bmstu.ru');
      expect(letter.text, 'Добрый день!\nШаблон во вложении.', reason: 'plain text preferred over html');
      expect(letter.attachments.single.fileName, 'Шаблон ЛР4.pdf');

      final requests = server.syncRequests();
      expect(requests.where((e) => e.localName == 'folderOpen'), hasLength(1), reason: 'folder opened once per session');
      final mark = requests.lastWhere((e) => e.localName == 'messageMark');
      expect(mark.getAttribute('flags'), 'Seen');
      expect(mark.getElement('UID')!.innerText, '235');
    });

    test('a dropped session is renewed and the folder opened again', () async {
      final server = _FakeCgp();
      final mail = _service(server);
      await mail.login('naa25r209', 'secret');
      await mail.fetchPage('INBOX');

      server.dropSession = true;
      final page = await mail.fetchPage('INBOX', from: 30);

      expect(page.items, hasLength(2));
      expect(server.logins, 2);
      expect(server.syncRequests().where((e) => e.localName == 'folderOpen'), hasLength(2));
    });

    test('a wrong password is reported as MailAuthException', () async {
      final mail = _service(_FakeCgp());
      await expectLater(mail.login('naa25r209', 'wrong'), throwsA(isA<MailAuthException>()));
      expect(mail.isSignedIn, isFalse);
    });

    test('sends a reply and a forward with server-side copies of attachments', () async {
      final server = _FakeCgp();
      final mail = _service(server);
      await mail.login('naa25r209', 'secret');
      final original = await mail.readMessage('INBOX', 235);

      await mail.send(
        MailDraft(
          to: [MailAddress.tryParse('Орлов Д. О. <orlov.do@bmstu.ru>')!],
          subject: 'Re: ${original.subject}',
          body: 'Спасибо!\r\nОтчёт пришлю.',
          inReplyTo: original.messageId,
          replyingTo: original,
        ),
        saveToMailbox: 'Sent Items',
      );
      var submit = server.syncRequests().lastWhere((e) => e.localName == 'messageSubmit');
      expect(submit.getAttribute('targetMailbox'), 'Sent Items');
      final email = submit.getElement('EMail')!;
      expect(email.getElement('From')!.innerText, 'naa25r209@student.bmstu.ru');
      expect(email.getElement('To')!.getAttribute('realName'), 'Орлов Д. О.');
      expect(email.getElement('To')!.innerText, 'orlov.do@bmstu.ru');
      expect(email.getElement('In-Reply-To')!.innerText, '<lab4-123@bmstu.ru>');
      expect(email.getElement('MIME')!.innerText, 'Спасибо!\nОтчёт пришлю.');
      final answered = server.syncRequests().lastWhere((e) => e.localName == 'messageMark');
      expect(answered.getAttribute('flags'), 'Answered');

      await mail.send(MailDraft(
        to: [const MailAddress(email: 'friend@student.bmstu.ru')],
        subject: 'Fwd: ${original.subject}',
        forwardOf: original,
      ));
      submit = server.syncRequests().lastWhere((e) => e.localName == 'messageSubmit');
      final copy = submit.findAllElements('copyMIME').single;
      expect(copy.getAttribute('folder'), 'INBOX');
      expect(copy.getAttribute('UID'), '235');
      expect(copy.getAttribute('partID'), '02');
    });
  });

  group('XIMSS parsing', () {
    test('html-only letters are turned into readable text', () {
      final email = XmlDocument.parse('''
<EMail><Subject>Новости</Subject>
  <MIME type="text" subtype="html" partID="">&lt;html&gt;&lt;head&gt;&lt;style&gt;p{color:red}&lt;/style&gt;&lt;/head&gt;&lt;body&gt;
  &lt;p&gt;Привет,&amp;nbsp;группа!&lt;/p&gt;&lt;ul&gt;&lt;li&gt;Раз&lt;/li&gt;&lt;li&gt;Два&lt;/li&gt;&lt;/ul&gt;
  &lt;a href="https://lks.bmstu.ru"&gt;ЛКС&lt;/a&gt;&lt;/body&gt;&lt;/html&gt;</MIME>
</EMail>''').rootElement;
      final letter = MailService.parseEmail(email, mailbox: 'INBOX', uid: 1);
      expect(letter.text, 'Привет, группа!\n\n• Раз\n• Два\nЛКС (https://lks.bmstu.ru)');
      expect(letter.attachments, isEmpty);
    });

    test('attachment download path follows the CommuniGate MIME URL scheme', () {
      const message = MailMessage(mailbox: 'Sent Items', uid: 567);
      const file = MailAttachment(partId: '02-01', fileName: 'Отчёт 1.pdf', contentType: 'application/pdf');
      expect(
        MailService.attachmentPath('1-abc', message, file),
        '/Session/1-abc/MIME/Sent%20Items/567-02-01-B.pdf/%D0%9E%D1%82%D1%87%D1%91%D1%82%201.pdf',
      );
      const noName = MailAttachment(partId: '03', fileName: 'image', contentType: 'image/png');
      expect(noName.extension, 'png');
    });

    test('server errors on login other than bad credentials keep their text', () {
      expect(
        () => MailService.parseLoginResponse('<XIMSS><response errorText="account is disabled"/></XIMSS>'),
        throwsA(isA<MailServerException>().having((e) => e.message, 'message', contains('account is disabled'))),
      );
      expect(() => MailService.parseLoginResponse('<html>Bad gateway</html>'), throwsA(isA<MailServerException>()));
    });

    test('recipient lists accept names, quotes and both separators', () {
      final parsed = MailAddress.parseList('"Иванов, И. И." <ivanov@bmstu.ru>; petrov@student.bmstu.ru, не адрес');
      expect(parsed.valid.map((a) => a.email), ['ivanov@bmstu.ru', 'petrov@student.bmstu.ru']);
      expect(parsed.valid.first.name, 'Иванов, И. И.');
      expect(parsed.invalid, ['не адрес']);
    });

    test('standard folders get Russian titles', () {
      expect(const MailFolder(name: 'Sent Items').title, 'Отправленные');
      expect(const MailFolder(name: 'INBOX').role, MailFolderRole.inbox);
      expect(const MailFolder(name: 'INBOX/Курсовая').title, 'INBOX / Курсовая');
    });
  });

  group('MailProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    MailProvider demoProvider() => MailProvider(
          mailService: DemoMailService(),
          storage: DemoMailCredentialsStorage(),
          authStorage: DemoAuthStorage(),
        );

    test('restores the saved login and keeps unread counters in sync', () async {
      final mail = demoProvider();
      await mail.restore();
      expect(mail.status, MailStatus.ready);
      expect(mail.inboxUnseen, 3);

      await mail.ensureListLoaded();
      final unread = mail.messages.firstWhere((m) => !m.isSeen);
      await mail.readMessage('INBOX', unread);
      expect(mail.inboxUnseen, 2);
      expect(mail.messages.firstWhere((m) => m.uid == unread.uid).isSeen, isTrue);

      await mail.delete('INBOX', unread.uid);
      expect(mail.messages.any((m) => m.uid == unread.uid), isFalse);
    });

    test('signing out of the app signs out of mail', () async {
      final mail = demoProvider();
      mail.onAuthChanged(true);
      await mail.restore();
      expect(mail.status, MailStatus.ready);

      mail.onAuthChanged(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(mail.status, MailStatus.signedOut);
      expect((await mail.storage.read()).username, isNull);
    });

    test('an app start before the session is restored does not sign out of mail', () async {
      final mail = demoProvider();
      mail.onAuthChanged(false);
      await Future<void>.delayed(Duration.zero);
      expect((await mail.storage.read()).username, 'demo');
    });
  });

  group('New mail notifications', () {
    MailSummary letter(int uid, {bool seen = false}) =>
        MailSummary(uid: uid, from: 'Отправитель $uid', subject: 'Тема $uid', flags: {if (seen) 'Seen'});

    test('the first check only remembers the inbox, later ones report unread new letters', () {
      final first = newMailSince([letter(12), letter(10), letter(9, seen: true)], null);
      expect(first.fresh, isEmpty, reason: 'no announcement of the unread backlog');
      expect(first.lastUid, 12);

      final next = newMailSince([letter(15), letter(14, seen: true), letter(12), letter(10)], 12);
      expect(next.fresh.map((m) => m.uid), [15], reason: 'read on another device or already announced');
      expect(next.lastUid, 15);

      expect(newMailSince(const [], 15).lastUid, 15, reason: 'an empty inbox keeps the mark');
    });

    test('letter counts are declined in Russian', () {
      expect(newLettersCount(1), '1 новое письмо');
      expect(newLettersCount(3), '3 новых письма');
      expect(newLettersCount(5), '5 новых писем');
      expect(newLettersCount(11), '11 новых писем');
      expect(newLettersCount(12), '12 новых писем');
      expect(newLettersCount(21), '21 новое письмо');
      expect(newLettersCount(24), '24 новых письма');
    });

    test('a background pass with only mail on checks the inbox and ends the session', () async {
      FlutterSecureStorage.setMockInitialValues({
        'bmstu_mail_username': 'naa25r209',
        'bmstu_mail_password': 'secret',
      });
      final lks = BmstuApiService()
        ..httpClientAdapter = FakeAdapter((o) => fail('LKS must not be called: ${o.uri}'));
      final delivered = <MailSummary>[];
      Future<List<MailSummary>> pass(_FakeCgp server) async {
        delivered.clear();
        await BackgroundSync.run(
          api: lks,
          mailService: _service(server),
          mailStorage: MailCredentialsStorage(),
          deliverMail: (letters) async => delivered.addAll(letters),
        );
        return List.of(delivered);
      }

      SharedPreferences.setMockInitialValues({BackgroundSync.mailEnabledKey: true});
      final server = _FakeCgp();
      expect(await pass(server), isEmpty, reason: 'first pass sets the baseline');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(BackgroundSync.mailLastUidKey), 235);
      expect(server.syncRequests().map((e) => e.localName), contains('bye'));
      final browse = server.syncRequests().firstWhere((e) => e.localName == 'folderBrowse');
      expect(browse.getElement('index')!.getAttribute('till'), '9');

      // A letter arrived after a check that had seen up to UID 232
      await prefs.setInt(BackgroundSync.mailLastUidKey, 232);
      final fresh = await pass(_FakeCgp());
      expect(fresh.map((m) => m.uid), [235], reason: '230 is older and already read');
      expect(fresh.single.from, 'Орлов Дмитрий Олегович');
      expect(await pass(_FakeCgp()), isEmpty, reason: 'never announced twice');
    });

    test('mail stays quiet while its notifications are off', () async {
      SharedPreferences.setMockInitialValues({BackgroundSync.mailEnabledKey: false});
      final server = _FakeCgp();
      await BackgroundSync.run(mailService: _service(server), deliverMail: (_) async => fail('no mail check'));
      expect(server.requests, isEmpty);
    });
  });

  testWidgets('settings offer the new-mail switch once mail is signed in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider(apiService: DemoApiService(), authStorage: DemoAuthStorage());
    final mail = MailProvider(
      mailService: DemoMailService(),
      storage: DemoMailCredentialsStorage(),
      authStorage: DemoAuthStorage(),
    );
    Future<void> pumpCard() => tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: mail),
          ],
          child: const MaterialApp(home: Scaffold(body: NotificationSettingsCard())),
        ));

    await pumpCard();
    await tester.pumpAndSettle();
    expect(find.text('Новые письма'), findsNothing, reason: 'no mail login, no LKS profile: nothing to offer');

    await tester.runAsync(mail.restore);
    await tester.pumpAndSettle();
    expect(find.text('Новые письма'), findsOneWidget);
    expect(find.text('Уведомления об успеваемости'), findsNothing, reason: 'not signed in to LKS');
  });
}
