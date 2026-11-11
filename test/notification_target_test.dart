import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/services/notification_target.dart';

void main() {
  test('A letter notification leads back to that letter', () {
    const letter = NotificationTarget.mail(uid: 140, from: 'Орлов Дмитрий Олегович', subject: 'ЛР №4');
    final back = NotificationTarget.decode(letter.encode())!;
    expect(back.kind, NotificationKind.mail);
    expect(back.mailbox, 'INBOX');
    expect(back.uid, 140);
    expect(back.from, 'Орлов Дмитрий Олегович');
    expect(back.subject, 'ЛР №4');
  });

  test('Summaries lead to the inbox or to all of the progress', () {
    final inbox = NotificationTarget.decode(const NotificationTarget.mail().encode())!;
    expect(inbox.kind, NotificationKind.mail);
    expect(inbox.uid, isNull);

    final progress = NotificationTarget.decode(const NotificationTarget.progress().encode())!;
    expect(progress.kind, NotificationKind.progress);
    expect(progress.discipline, isEmpty);
    expect(
      NotificationTarget.decode(const NotificationTarget.progress(discipline: 'Физика').encode())!.discipline,
      'Физика',
    );
  });

  test('Old or broken payloads just open the app', () {
    expect(NotificationTarget.decode(null), isNull);
    expect(NotificationTarget.decode(''), isNull);
    expect(NotificationTarget.decode('not json'), isNull);
    expect(NotificationTarget.decode('{"kind":"weather"}'), isNull);
  });
}
